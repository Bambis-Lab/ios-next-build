"""Test-only private role handoff for already approved, isolated simulator runs.

No relay is provisioned and no network approval is inferred from a file.
Never run on a production simulator, real device, or existing user profile.
Only a disposable, authorized execution environment may invoke this entrypoint.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import time
from urllib.parse import urlsplit

ROLE_KEYS={"version","role","callID","baseURL","duration","expiresAt","signingSeed",
           "peerSigningKey","peerAgreementKey","tokens","grantExpiries"}
HEX32=re.compile(r"[0-9a-f]{32}")
HEX64=re.compile(r"[0-9a-f]{64}")

def require(condition,reason):
    if not condition: raise ValueError(reason)

def read_private(path):
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
    with os.fdopen(fd,"rb") as stream:
        info=os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and
                not info.st_mode&0o077 and 0<info.st_size<=16384,"unsafe_role_file")
        raw=stream.read(16385)
        require(len(raw)==info.st_size and len(raw)<=16384,"invalid_role_size")
        return raw

def validate(raw,role,duration,*,now=None):
    now=int(time.time()) if now is None else now
    require(role in ("A","B") and type(duration) is int and duration in (30,120,300),"invalid_stage")
    require(type(raw) is bytes and len(raw)<=16384,"invalid_role_size")
    try: item=json.loads(raw)
    except (ValueError,UnicodeError): raise ValueError("invalid_role_json") from None
    require(isinstance(item,dict) and set(item)==ROLE_KEYS,"invalid_role_schema")
    require(type(item["version"]) is int and item["version"]==1 and item["role"]==role and
            type(item["duration"]) is int and item["duration"]==duration,"role_or_stage_mismatch")
    require(isinstance(item["callID"],str) and HEX32.fullmatch(item["callID"]),"invalid_call")
    expiry=item["expiresAt"]
    require(type(expiry) is int and now+duration<expiry<=now+1200,"invalid_expiry")
    tokens=item["tokens"]; grants=item["grantExpiries"]
    require(isinstance(tokens,list) and len(tokens)==3 and all(isinstance(t,str) and HEX64.fullmatch(t) for t in tokens)
            and len(set(tokens))==3,"invalid_grants")
    require(isinstance(grants,list) and len(grants)==3 and all(type(t) is int for t in grants)
            and now<grants[0]<grants[1]<grants[2]<=expiry and grants[2]>now+duration,"invalid_grant_expiry")
    url=item["baseURL"]
    require(isinstance(url,str) and url.isascii() and len(url)<=512 and not any(c.isspace() for c in url),"invalid_origin")
    try:
        u=urlsplit(url)
        require(u.scheme=="https" and bool(u.hostname) and u.username is None and u.password is None
                and "@" not in u.netloc and "?" not in url and "#" not in url and chr(92) not in url
                and u.path in ("","/") and (u.port is None or 1<=u.port<=65535),"invalid_origin")
        for field in ("signingSeed","peerSigningKey","peerAgreementKey"):
            v=item[field]
            require(isinstance(v,str) and len(v)==44,"invalid_key")
            key=base64.b64decode(v,validate=True)
            require(len(key)==32 and base64.b64encode(key).decode("ascii")==v,"invalid_key")
    except (ValueError,TypeError): raise ValueError("invalid_role_origin_or_key") from None
    # Swift independently verifies peer key binding before connection.
    return item

def install_role(raw,container,role,duration,*,now=None):
    """Exclusive local copy; returns exact path for the caller's scoped cleanup."""
    validate(raw,role,duration,now=now)
    container=Path(container)
    require(container.is_dir() and not container.is_symlink(),"invalid_container")
    library=container/"Library"
    support=library/"Application Support"
    for directory in (library,support):
        directory.mkdir(mode=0o700,exist_ok=True)
        require(directory.is_dir() and not directory.is_symlink() and
                directory.stat().st_uid==os.getuid(),"unsafe_container_directory")
    require(support.resolve().is_relative_to(container.resolve()),"container_escape")
    path=support/"iosnext-v64-test-role.json"
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        with os.fdopen(fd,"wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return path

def relay_fingerprint(item):
    return hashlib.sha256(item["callID"].encode("ascii")).hexdigest()
