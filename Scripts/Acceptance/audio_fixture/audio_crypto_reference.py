"""Reference authenticated audio key exchange and packet codec.

Experimental protocol; not connected to the live broker or native client.
Peer signing keys MUST be independently authenticated/pinned by the caller.
"""
import json
import struct
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import x25519, ed25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

DOMAIN=b"iosnext-audio-v1"

def public(key):
    return key.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)

def transcript(call_id, caller, callee, actor, ephemeral):
    if not isinstance(call_id,str) or len(call_id)!=32 or any(c not in "0123456789abcdef" for c in call_id):
        raise ValueError("invalid_call")
    if any(not isinstance(p,tuple) or len(p)!=2 or any(not isinstance(v,str) or not 1<=len(v)<=64 for v in p) for p in (caller,callee,actor)):
        raise ValueError("invalid_identity")
    if caller==callee or actor not in (caller,callee) or len(ephemeral)!=32:
        raise ValueError("invalid_transcript")
    return DOMAIN+b"\x00"+json.dumps([call_id,caller,callee,actor,ephemeral.hex()],ensure_ascii=True,separators=(",",":")).encode("ascii")

def offer(call_id,caller,callee,actor,ephemeral_private,signing_private):
    ephemeral=public(ephemeral_private)
    return ephemeral,signing_private.sign(transcript(call_id,caller,callee,actor,ephemeral))

def establish(call_id,caller,callee,actor,private,peer_public,peer_signature,pinned_signing_key):
    peer=callee if actor==caller else caller
    local=public(private)
    transcript(call_id,caller,callee,actor,local)
    ed25519.Ed25519PublicKey.from_public_bytes(pinned_signing_key).verify(
        peer_signature,transcript(call_id,caller,callee,peer,peer_public))
    shared=private.exchange(x25519.X25519PublicKey.from_public_bytes(peer_public))
    first,second=(local,peer_public) if actor==caller else (peer_public,local)
    context=transcript(call_id,caller,callee,caller,first)+b"\x00"+transcript(call_id,caller,callee,callee,second)
    keys=HKDF(algorithm=hashes.SHA256(),length=64,salt=None,info=context).derive(shared)
    return AudioCodec(keys[:32],keys[32:],context) if actor==caller else AudioCodec(keys[32:],keys[:32],context)

class AudioCodec:
    """Single-writer ordered codec. A fresh ephemeral key per call is required."""
    def __init__(self,send_key,receive_key,context):
        self.send=ChaCha20Poly1305(send_key)
        self.receive=ChaCha20Poly1305(receive_key)
        self.context=context
        self.sent=-1
        self.received=-1

    def _nonce(self,sequence):
        if type(sequence) is not int or not 0<=sequence<2**63:
            raise ValueError("invalid_sequence")
        return struct.pack(">IQ",0,sequence)

    def seal(self,sequence,frame):
        nonce=self._nonce(sequence)
        if sequence<=self.sent or not isinstance(frame,bytes) or not 1<=len(frame)<=4080:
            raise ValueError("invalid_frame")
        result=self.send.encrypt(nonce,frame,self.context+nonce)
        self.sent=sequence
        return result

    def open(self,sequence,packet):
        nonce=self._nonce(sequence)
        if sequence<=self.received or not isinstance(packet,bytes) or not 17<=len(packet)<=4096:
            raise ValueError("invalid_packet")
        frame=self.receive.decrypt(nonce,packet,self.context+nonce)
        self.received=sequence
        return frame
