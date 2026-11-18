"""Bounded in-memory call signalling state machine.

No audio transport, external network, credentials or automatic call acceptance.
The HTTP adapter must derive the actor from authenticated family device claims.
"""
import secrets
import threading
import time
from .audio_session import AudioSession

class CallSignalling:
    def __init__(self, clock=time.monotonic, ttl=60, capacity=32, accepted_ttl=3600):
        self.clock=clock
        self.ttl=ttl
        self.accepted_ttl=accepted_ttl
        self.capacity=capacity
        self.lock=threading.RLock()
        self.calls={}
        self.audio={}

    def _purge(self):
        now=self.clock()
        for ident in list(self.calls):
            if self.calls[ident]["expires"] <= now:
                self._drop(ident)

    @staticmethod
    def _public(call):
        return {k:v for k,v in call.items() if k!="expires"}

    def invite(self, actor, recipient):
        if actor==recipient:
            raise ValueError("self_call")
        with self.lock:
            self._purge()
            if len(self.calls)>=self.capacity:
                raise OverflowError("call_capacity")
            for c in self.calls.values():
                if c["state"] in ("ringing","accepted") and (
                    actor in (c["caller"],c["callee"]) or recipient in (c["caller"],c["callee"])
                ):
                    raise ValueError("participant_busy")
            ident=secrets.token_hex(16)
            call={"id":ident,"caller":actor,"callee":recipient,"state":"ringing",
                  "expires":self.clock()+self.ttl}
            self.calls[ident]=call
            return self._public(call)

    def transition(self, actor, ident, action):
        with self.lock:
            self._purge()
            c=self.calls.get(ident)
            if c is None or actor not in (c["caller"],c["callee"]):
                raise PermissionError("call_unavailable")
            state=c["state"]
            if action in ("accept","decline") and actor==c["callee"] and state=="ringing":
                c["state"]="accepted" if action=="accept" else "declined"
            elif action=="cancel" and actor==c["caller"] and state=="ringing":
                c["state"]="cancelled"
            elif action=="hangup" and state=="accepted":
                c["state"]="ended"
            else:
                raise ValueError("invalid_call_transition")
            if c["state"] != "accepted":
                self._close_audio(ident)
            c["expires"]=self.clock()+(self.accepted_ttl if c["state"]=="accepted" else self.ttl)
            return self._public(c)

    def list_for(self, actor):
        with self.lock:
            self._purge()
            return [self._public(c) for c in self.calls.values() if actor in (c["caller"],c["callee"])]

    def revoke(self, actor):
        with self.lock:
            for ident in list(self.calls):
                c=self.calls[ident]
                if actor in (c["caller"],c["callee"]):
                    self._drop(ident)

    def _close_audio(self, ident):
        session=self.audio.pop(ident,None)
        if session is not None:
            session.close()

    def _drop(self, ident):
        self._close_audio(ident)
        del self.calls[ident]

    def audio_action(self, actor, ident, authorize, signing_keys, payload):
        """The supplied authorization callback must consult the active registry."""
        with self.lock:
            self._purge()
            c=self.calls.get(ident)
            if c is None or c["state"]!="accepted" or actor not in (c["caller"],c["callee"]):
                raise PermissionError("audio_unavailable")
            participants=(c["caller"],c["callee"])
            if not all(authorize(*p) for p in participants):
                self._drop(ident)
                raise PermissionError("audio_unavailable")
            action=payload.get("action")
            if action=="heartbeat" and set(payload)=={"action"}:
                return {"active":True}
            if action=="offer":
                if set(payload)!={"action","ephemeral","signature"}:
                    raise ValueError("invalid_offer")
                session=self.audio.get(ident)
                if session is None:
                    session=AudioSession(ident,*participants,{p:signing_keys(*p) for p in participants})
                    session.publish(actor,payload["ephemeral"],payload["signature"])
                    self.audio[ident]=session
                else:
                    session.publish(actor,payload["ephemeral"],payload["signature"])
                return {"published":True}
            session=self.audio.get(ident)
            if action=="stream_drain" and set(payload)=={"action"}:
                if session is None or session.peer_offer(actor) is None or session.peer_offer(next(p for p in participants if p!=actor)) is None:
                    return {"packets":[]}
                return {"packets":session.drain(actor)}
            if session is None:
                raise PermissionError("handshake_pending")
            if action=="peer_offer" and set(payload)=={"action"}:
                return {"offer":session.peer_offer(actor)}
            if action=="push" and set(payload)=={"action","sequence","ciphertext"}:
                session.push(actor,payload["sequence"],payload["ciphertext"])
                return {"queued":True}
            if action=="drain" and set(payload)=={"action"}:
                return {"packets":session.drain(actor)}
            raise ValueError("invalid_audio_action")

    def close(self):
        with self.lock:
            for ident in list(self.calls):
                self._drop(ident)
