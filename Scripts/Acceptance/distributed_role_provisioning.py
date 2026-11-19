"""Offline, test-only provisioning. No network, deployment, or credential output.

Run only in an isolated, operator-authorized temporary directory. Never upload
the generated role files. Their delivery requires a separately approved route.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import time
from urllib.parse import urlsplit
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from distributed_audio_relay import RelayContract, require

def generate(run, duration, origin, *, now=None):
    now=int(time.time()) if now is None else now
    require(type(now) is int and type(duration) is int and duration in (30,120,300),"invalid_duration")
    require(isinstance(run,str) and re.fullmatch(r"[0-9]{1,24}:[0-9]{1,10}",run),"invalid_run")
    require(isinstance(origin,str) and len(origin)<=512 and origin.isascii() and not any(c.isspace() for c in origin),"invalid_origin")
    u=urlsplit(origin)
    require(u.scheme=="https" and bool(u.hostname) and not u.username and u.password is None
            and "@" not in u.netloc and not u.query and not u.fragment and u.path in ("","/") and
            (u.port is None or 1<=u.port<=65535),"invalid_origin")
    require("?" not in origin and "#" not in origin and chr(92) not in origin,"invalid_origin")
    # Allow a bounded rendezvous (180 s) before the timed media stage.
    # Overlapping grants remain valid for scheduled renewal and reconnect.
    expiry=now+duration+360
    grants=[now+240+duration//3,now+270+2*duration//3,expiry]
    def b64(raw): return base64.b64encode(raw).decode("ascii")
    roles=("A","B")
    signing={r:Ed25519PrivateKey.generate() for r in roles}
    agreements={r:X25519PrivateKey.generate() for r in roles}
    tokens={r:[secrets.token_hex(32) for _ in range(3)] for r in roles}
    call=secrets.token_hex(16)
    relay={"version":1,"run":run,"call_id":call,"duration":duration,"expires_at":expiry,"roles":{}}
    clients={}
    for role,peer in (("A","B"),("B","A")):
        relay["roles"][role]={"signing_public_key":b64(signing[role].public_key().public_bytes_raw()),
          "grants":[{"sha256":hashlib.sha256(t.encode("ascii")).hexdigest(),"expires_at":until}
                    for t,until in zip(tokens[role],grants)]}
        clients[role]={"version":1,"role":role,"callID":call,"baseURL":origin,
           "duration":duration,"expiresAt":expiry,"signingSeed":b64(signing[role].private_bytes_raw()),
           "peerSigningKey":b64(signing[peer].public_key().public_bytes_raw()),
           "peerAgreementKey":b64(agreements[peer].public_key().public_bytes_raw()),
           "tokens":tokens[role],"grantExpiries":grants}
    RelayContract(relay,wall=lambda:now)
    return relay,clients

def write_private_bundle(directory, relay, clients):
    # Exclusive creation, owner-only directory and files; never overwrite.
    directory=Path(directory)
    directory.mkdir(mode=0o700,exist_ok=False)
    written=[]
    try:
        for name,value in (("relay.json",relay),("role-A.json",clients["A"]),("role-B.json",clients["B"])):
            target=directory/name
            fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            written.append(target)
            with os.fdopen(fd,"w",encoding="ascii") as stream:
                json.dump(value,stream,separators=(",",":"))
                stream.flush()
                os.fsync(stream.fileno())
        return directory
    except BaseException:
        for target in written:
            target.unlink(missing_ok=True)
        directory.rmdir()
        raise
