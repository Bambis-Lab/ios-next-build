"""Opt-in loopback WebSocket sharing the live broker's in-process authorization.

No HTTP per frame, no query credentials, no public listener.
"""
import base64
import json
import os
import socket
import threading
import time
from cryptography.exceptions import InvalidSignature
from websockets.sync.server import serve
from websockets.exceptions import ConnectionClosed

def audio_websocket(broker, *, port=0, control=None, idle_timeout=15.0):
    if not 0.25 <= idle_timeout <= 60:
        raise ValueError("invalid_idle_timeout")
    slots=threading.BoundedSemaphore(16)
    bound=set()
    binding_lock=threading.Lock()
    def authenticate(token):
        if control is not None and control.stopping.is_set():
            raise PermissionError("listener_stopping")
        registry=broker.family_registry
        issuer=broker.bootstrap_issuer
        if os.environ.get("IOSNEXT_EXPERIMENTAL_AUDIO")!="true" or registry is None or issuer is None:
            raise PermissionError("disabled")
        claims=issuer.verify(token)
        if claims is None or not claims.family_device:
            raise PermissionError("unauthorized")
        return claims

    def invoke(token,cid,payload):
        claims=authenticate(token)
        actor=(claims.user_id,claims.device_id)
        registry=broker.family_registry
        def key(user,device):
            for identity in broker.store.chat_identities(user):
                if identity["device_id"]==device:
                    return base64.b64decode(identity["signing_public_key"],validate=True)
            raise PermissionError("identity_missing")
        return broker.calls.audio_action(actor,cid,registry.is_active,key,payload)

    def handle(ws):
        if not slots.acquire(blocking=False):
            ws.close(1013,"capacity")
            return
        binding=None
        try:
            headers=ws.request.headers.get_all("Authorization")
            if len(headers)!=1:
                raise PermissionError("unauthorized")
            token=headers[0]
            if ws.request.path!="/v1/audio" or not token.startswith("Bearer ") or len(token)>4096:
                raise PermissionError("unauthorized")
            token=token[7:]
            first=json.loads(ws.recv(timeout=3))
            if not isinstance(first,dict) or set(first) not in ({"call_id"},{"call_id","mode"}):
                raise ValueError("invalid_binding")
            cid=first["call_id"]
            if not isinstance(cid,str) or len(cid)!=32 or any(c not in "0123456789abcdef" for c in cid):
                raise ValueError("invalid_binding")
            mode=first.get("mode","request")
            if mode not in ("request","stream"):
                raise ValueError("invalid_mode")
            invoke(token,cid,{"action":"heartbeat"})
            claims=authenticate(token)
            candidate=(cid,(claims.user_id,claims.device_id))
            with binding_lock:
                if candidate in bound:
                    raise PermissionError("duplicate_connection")
                bound.add(candidate)
                binding=candidate
            ws.send(json.dumps({"bound":True} if mode=="request" else {"bound":True,"mode":"stream"}))
            budget=100.0
            last=time.monotonic()
            last_valid=last

            def deliver():
                result=invoke(token,cid,{"action":"stream_drain"})
                if result["packets"]:
                    ws.send(json.dumps({"event":"audio","packets":result["packets"]}))

            while True:
                remaining=idle_timeout-(time.monotonic()-last_valid)
                if remaining<=0:
                    ws.close(1008,"idle_timeout")
                    return
                try:
                    raw=ws.recv(timeout=min(remaining,0.02 if mode=="stream" else 0.5))
                except TimeoutError:
                    if mode=="stream":
                        deliver()
                    else:
                        invoke(token,cid,{"action":"heartbeat"})
                    continue
                now=time.monotonic()
                budget=min(100.0,budget+(now-last)*100.0)
                last=now
                if budget<1:
                    ws.close(1008,"rate_limit")
                    return
                budget-=1
                if not isinstance(raw,str):
                    raise ValueError("invalid_message")
                payload=json.loads(raw)
                if not isinstance(payload,dict) or "call_id" in payload or payload.get("action") not in ("push","drain","peer_offer","offer","heartbeat","refresh"):
                    raise ValueError("invalid_message")
                if mode=="stream" and payload["action"]=="drain":
                    raise ValueError("stream_uses_automatic_delivery")
                if payload["action"]=="refresh":
                    replacement=payload.get("token")
                    if set(payload)!={"action","token"} or not isinstance(replacement,str) or not 1<=len(replacement)<=4096:
                        raise ValueError("invalid_refresh")
                    current=authenticate(token)
                    renewed=authenticate(replacement)
                    if ((renewed.user_id,renewed.device_id)!=binding[1]
                        or renewed.expires_at<=current.expires_at):
                        raise PermissionError("invalid_refresh")
                    invoke(replacement,cid,{"action":"heartbeat"})
                    token=replacement
                    result={"refreshed":True,"expires_at":renewed.expires_at}
                else:
                    result=invoke(token,cid,payload)
                last_valid=time.monotonic()
                ws.send(json.dumps({"status":200,"result":result}))
                if mode=="stream":
                    deliver()
        except ConnectionClosed:
            return
        except (ValueError,TypeError,TimeoutError,OSError,InvalidSignature):
            ws.close(1008,"transport_closed")
        finally:
            if binding is not None:
                with binding_lock:
                    bound.discard(binding)
            slots.release()
    def guarded_handle(ws):
        if control is None:
            return handle(ws)
        with control.condition:
            admitted=not control.stopping.is_set()
            if admitted:
                control.active.add(ws)
        if not admitted:
            ws.close(1001,"listener_stopping")
            return
        try:
            handle(ws)
        finally:
            with control.condition:
                control.active.discard(ws)
                control.condition.notify_all()
    return serve(guarded_handle,"127.0.0.1",port,max_size=16384,max_queue=4,
                 compression=None,open_timeout=3,close_timeout=1)


class ManagedAudioListener:
    """Explicitly enabled loopback service with broker-owned shutdown.

    Never advertises a public or native-client endpoint. The accept loop and
    every admitted session are stopped before the broker closes its registry.
    """
    def __init__(self, broker, port):
        self.condition=threading.Condition()
        self.stopping=threading.Event()
        self.active=set()
        self.server=audio_websocket(broker,port=port,control=self)
        self.port=self.server.socket.getsockname()[1]
        self.thread=threading.Thread(target=self.server.serve_forever,
                                     name="iosnext-audio-loopback",daemon=True)
        try:
            self.thread.start()
        except BaseException:
            self.server.socket.close()
            raise

    def close(self):
        with self.condition:
            self.stopping.set()
            # Unblock active reads and writes without waiting for peers.
            for ws in tuple(self.active):
                try:
                    ws.socket.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        self.server.shutdown()
        self.thread.join(timeout=5)
        with self.condition:
            drained=self.condition.wait_for(lambda: not self.active,timeout=5)
        if self.thread.is_alive() or not drained:
            raise RuntimeError("audio_listener_shutdown_incomplete")
