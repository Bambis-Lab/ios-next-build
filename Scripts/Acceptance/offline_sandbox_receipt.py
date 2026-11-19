"""Disposable OFFLINE role proof; not a live relay or release authorization."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import uuid

from native_role_handoff import read_private

POLICY = "sr22-disposable-offline-v1"
ROLE_FILE = "iosnext-v64-test-role.json"
MARKER = "SR22_NATIVE_RECEIPT"

def require(ok, reason):
    if not ok:
        raise ValueError(reason)

def canonical_uuid(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F-]{36}", value), "invalid_container")
    try:
        result = str(uuid.UUID(value))
    except ValueError:
        raise ValueError("invalid_container") from None
    require(result == value.lower(), "invalid_container")
    return result

def sandbox_id(path):
    return canonical_uuid(Path(path).name)

def message(item, raw, cid):
    return ("iosnext-sr22-offline-v1|" + item["callID"] + "|" + item["role"] +
            "|30|" + canonical_uuid(cid) + "|" + hashlib.sha256(raw).hexdigest()).encode("ascii")

def verify_receipt(log, raw, original, current, policy):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.exceptions import InvalidSignature
    item = json.loads(raw)
    require(item["baseURL"] == "https://fixture.invalid/" and item["duration"] == 30, "invalid_offline_fixture")
    original, current = Path(original), Path(current)
    require(original.parent == current.parent, "sandbox_changed")
    before, after = sandbox_id(original), sandbox_id(current)
    require(before == after or policy == POLICY, "sandbox_changed")
    matches = re.findall(r"SR22_NATIVE_RECEIPT container=([0-9a-f-]{36}) signature=([A-Za-z0-9+/]{86}==)(?:\s|$)", log)
    require(log.count(MARKER) == 1 and len(matches) == 1, "native_receipt_missing")
    cid, encoded = matches[0]
    require(cid in {before, after}, "sandbox_changed")
    try:
        signature = base64.b64decode(encoded, validate=True)
        key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(item["signingSeed"], validate=True)).public_key()
        key.verify(signature, message(item, raw, cid))
    except (ValueError, InvalidSignature):
        raise ValueError("native_receipt_invalid") from None
    return {"receipt_verified": True, "sandbox_lifecycle": "UNCHANGED" if before == after else "VERIFIED_OFFLINE_ROTATION",
            "native_container_observed": "INITIAL" if cid == before else "CURRENT"}

def role_path(container):
    # Only owned, non-symlink directories of the disposable simulator.
    p = Path(container)
    for d in (p, p / "Library", p / "Library" / "Application Support"):
        try:
            info = d.lstat()
        except FileNotFoundError:
            return None
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid(), "unsafe_container_directory")
    return p / "Library" / "Application Support" / ROLE_FILE

def cleanup_role_copies(original, current, raw):
    """Remove only byte-identical, owned transient credentials; never foreign files."""
    original, current = Path(original), Path(current)
    root = original.parent
    require(current.parent == root, "sandbox_changed")
    require(root.is_dir() and not root.is_symlink(), "invalid_container")
    expected = {sandbox_id(original), sandbox_id(current)}
    # This is one disposable simulator's Application directory, not a global search.
    children = list(root.iterdir())
    require(len(children) <= 512, "cleanup_failed")
    conflict = False
    removed = 0
    for child in children:
        try:
            cid = sandbox_id(child)
        except ValueError:
            continue
        # Do not follow unrelated symlink directories.
        if child.is_symlink() or not child.is_dir():
            if cid in expected:
                conflict = True
            continue
        try:
            target = role_path(child)
            if target is None or not os.path.lexists(target):
                continue
            if read_private(target) != raw:
                conflict = True
                continue
            # A matching file in a third container is unauthorized, even if
            # cleanup succeeds. Leave the overall handoff failed.
            conflict |= cid not in expected
            target.unlink()
            require(not os.path.lexists(target), "cleanup_failed")
            removed += 1
        except (OSError, ValueError):
            conflict = True
    require(not conflict, "cleanup_failed")
    return removed
