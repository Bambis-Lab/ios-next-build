"""Experimental call key-offer registry and opaque audio transport core.

The adapter must hold a valid accepted-call authorization for both devices.
Only public signed offers and encrypted frames enter this component.
"""
import base64
import threading
from cryptography.hazmat.primitives.asymmetric import ed25519,x25519
from .audio_crypto_reference import transcript
from .audio_packet_buffer import AudioPacketBuffer

class AudioSession:
    def __init__(self, call_id, caller, callee, signing_keys):
        self.call_id=call_id
        self.caller=caller
        self.callee=callee
        self.participants=(caller,callee)
        if set(signing_keys)!=set(self.participants):
            raise ValueError("missing_signing_keys")
        self.keys={p:ed25519.Ed25519PublicKey.from_public_bytes(k) for p,k in signing_keys.items()}
        self.offers={}
        self.buffer=AudioPacketBuffer(self.participants)
        self.lock=threading.RLock()
        self.closed=False

    def _require(self,actor):
        if self.closed or actor not in self.participants:
            raise PermissionError("audio_unavailable")

    @staticmethod
    def _decode(value,length):
        if not isinstance(value,str) or len(value)>128:
            raise ValueError("invalid_offer")
        raw=base64.b64decode(value,validate=True)
        if len(raw)!=length:
            raise ValueError("invalid_offer")
        return raw

    def publish(self,actor,ephemeral,signature):
        with self.lock:
            self._require(actor)
            key=self._decode(ephemeral,32)
            sig=self._decode(signature,64)
            x25519.X25519PublicKey.from_public_bytes(key)
            self.keys[actor].verify(sig,transcript(self.call_id,self.caller,self.callee,actor,key))
            existing=self.offers.get(actor)
            candidate=(ephemeral,signature)
            if existing is not None and existing!=candidate:
                raise ValueError("offer_already_bound")
            self.offers[actor]=candidate

    def peer_offer(self,actor):
        with self.lock:
            self._require(actor)
            peer=self.callee if actor==self.caller else self.caller
            offer=self.offers.get(peer)
            return None if offer is None else {"ephemeral":offer[0],"signature":offer[1]}

    def push(self,actor,sequence,ciphertext):
        with self.lock:
            self._require(actor)
            if len(self.offers)!=2:
                raise PermissionError("handshake_pending")
            self.buffer.push(actor,sequence,ciphertext)

    def drain(self,actor):
        with self.lock:
            self._require(actor)
            if len(self.offers)!=2:
                raise PermissionError("handshake_pending")
            return self.buffer.drain(actor)

    def close(self):
        with self.lock:
            self.closed=True
            self.offers.clear()
            self.buffer.close()
