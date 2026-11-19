"""Test-only per-run relay, bound to loopback; no provisioning or external listener.

The authorized transport (if one exists) is external to this process. Unlike
the deterministic local fixture this service accepts only fresh role-specific
bearers, and holds only bearer digests and public device signing keys.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time
from types import SimpleNamespace
from audio_network_fixture import A, B, verify
from audio_fixture.audio_websocket import ManagedAudioListener
from audio_fixture.call_signalling import CallSignalling

HEX64 = re.compile(r"[0-9a-f]{64}")
HEX32 = re.compile(r"[0-9a-f]{32}")
ROLES = {"A": A, "B": B}

def require(condition, reason):
    if not condition:
        raise ValueError(reason)

class RelayContract:
    def __init__(self, config, *, wall=time.time, steady=time.monotonic):
        self.wall, self.steady = wall, steady
        now = wall()
        require(isinstance(config, dict) and set(config)=={"version","run","call_id","duration","expires_at","roles"}, "invalid_contract")
        require(type(config["version"]) is int and config["version"]==1, "invalid_version")
        require(isinstance(config["run"], str) and re.fullmatch(r"[0-9]{1,24}:[0-9]{1,10}",config["run"]), "invalid_run")
        require(isinstance(config["call_id"], str) and HEX32.fullmatch(config["call_id"]), "invalid_call")
        require(type(config["duration"]) is int and config["duration"] in (30,120,300), "invalid_duration")
        expiry=config["expires_at"]
        require(type(expiry) is int and now+config["duration"]<expiry<=now+1200, "invalid_session_expiry")
        require(isinstance(config["roles"],dict) and set(config["roles"])==set(ROLES), "invalid_roles")
        self.session_expiry=expiry
        self.deadline=steady()+(expiry-now)
        self.run=config["run"]
        self.call_id=config["call_id"]
        self.duration=config["duration"]
        self.keys={}
        self.grants={}
        public_keys=set()
        for role, actor in ROLES.items():
            spec=config["roles"][role]
            require(isinstance(spec,dict) and set(spec)=={"signing_public_key","grants"}, "invalid_role")
            key=spec["signing_public_key"]
            require(isinstance(key,str) and len(key)==44,"invalid_key")
            raw=base64.b64decode(key,validate=True)
            require(len(raw)==32 and base64.b64encode(raw).decode("ascii")==key and raw not in public_keys,"invalid_or_shared_key")
            public_keys.add(raw)
            self.keys[actor[0]]=[{"device_id":actor[1],"signing_public_key":key}]
            grants=spec["grants"]
            require(isinstance(grants,list) and len(grants)==3,"invalid_grant_count")
            previous=now
            for grant in grants:
                require(isinstance(grant,dict) and set(grant)=={"sha256","expires_at"},"invalid_grant")
                digest,until=grant["sha256"],grant["expires_at"]
                require(isinstance(digest,str) and HEX64.fullmatch(digest) and digest not in self.grants,"invalid_or_shared_bearer")
                require(type(until) is int and previous<until<=expiry,"invalid_grant_expiry")
                self.grants[digest]=(actor,until,steady()+(until-now))
                previous=until
        self.calls=CallSignalling(clock=steady)
        self.revoked=set()
        self.calls.calls[self.call_id]={"id":self.call_id,"caller":A,"callee":B,
            "state":"accepted","expires":self.deadline}

    def active(self, user, device):
        with self.calls.lock:
            return ((user,device) in ROLES.values() and (user,device) not in self.revoked
                    and self.wall()<self.session_expiry and self.steady()<self.deadline)

    def revoke(self, role):
        """Local test harness only; no network administrative endpoint."""
        require(role in ROLES,"invalid_role")
        with self.calls.lock:
            actor=ROLES[role]
            self.revoked.add(actor)
            self.calls.revoke(actor)

    def authenticate(self, token):
        if not isinstance(token,str) or not HEX64.fullmatch(token):
            return None
        grant=self.grants.get(hashlib.sha256(token.encode("ascii")).hexdigest())
        if grant is None:
            return None
        actor, expiry, deadline=grant
        if not self.active(*actor) or self.wall()>=expiry or self.steady()>=deadline:
            return None
        return SimpleNamespace(user_id=actor[0],device_id=actor[1],family_device=True,expires_at=expiry)

    def broker(self):
        return SimpleNamespace(family_registry=SimpleNamespace(is_active=self.active),
            bootstrap_issuer=SimpleNamespace(verify=self.authenticate),
            store=SimpleNamespace(chat_identities=lambda u:self.keys.get(u,[])),calls=self.calls)

def load_config(path):
    # Local operator-created configuration; public key and digest data is
    # still restricted. No symlinks or world/group-readable configuration.
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
    with os.fdopen(fd,"rb") as stream:
        info=os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and not info.st_mode&0o077 and info.st_size<=16384,"unsafe_config")
        raw=stream.read(16385)
        require(len(raw)<=16384,"oversized_config")
    return json.loads(raw)

def main():
    if len(sys.argv)!=2:
        raise SystemExit("usage: distributed_audio_relay.py PRIVATE_CONFIG")
    try:
        verify()
        contract=RelayContract(load_config(Path(sys.argv[1])))
        os.environ["IOSNEXT_EXPERIMENTAL_AUDIO"]="true"
        listener=ManagedAudioListener(contract.broker(),18766)
        print("V64_ISOLATED_LOOPBACK_RELAY_READY",flush=True)
        try:
            while contract.wall()<contract.session_expiry and contract.steady()<contract.deadline:
                time.sleep(.5)
        finally:
            listener.close()
    except Exception:
        # Do not echo configuration, credentials, headers or payloads.
        print("V64_ISOLATED_RELAY_FAILED",file=sys.stderr)
        return 1
    return 0

if __name__=="__main__":
    raise SystemExit(main())
