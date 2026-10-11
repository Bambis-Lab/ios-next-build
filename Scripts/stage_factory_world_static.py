#!/usr/bin/env python3
"""Fetch immutable S01 real-Blender day/night assets into Xcode build workspace.

Called ONLY from the isolated iOS branch CI. SHA-256 and geometry provenance are
verified before staging anything. No live Factory access or tracked file changes.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
from urllib.request import Request, urlopen

SOURCE_HASH = "1c1e131692a3572a44de8c52dc1af3dd25644ef7304ad39636947d742f6123de"
ASSET_FOLDER = "mobile-assets/FactoryWorld"
BASE = "https://raw.githubusercontent.com/Bambis-Lab/factory-ui/"
MAX_BYTES = 24 * 1024 * 1024

def download(commit: str, name: str) -> bytes:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected immutable 40-digit Git commit")
    if name not in ("manifest.json", "FactoryWorld_day.png", "FactoryWorld_night.png"):
        raise ValueError("Untrusted filename")
    url = f"{BASE}{commit}/{ASSET_FOLDER}/{name}"
    with urlopen(Request(url, headers={"User-Agent": "ios-next-factory-world-static-pin/1"}),
                 timeout=45) as response:
        content = response.read(MAX_BYTES + 1)
    if not content or len(content) > MAX_BYTES:
        raise RuntimeError("Asset missing or exceeds approved byte limit")
    return content

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--commit", required=True)
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    if not (root / "project.yml").is_file() or not (root / "Assets.xcassets").is_dir():
        raise RuntimeError("Not the iOS Next project root")
    manifest_bytes = download(args.commit, "manifest.json")
    manifest = json.loads(manifest_bytes)
    if manifest.get("schema") != "factory.world.static.v1":
        raise RuntimeError("Unexpected asset schema")
    if manifest.get("scope") != "OFFLINE_STATIC_ENTIRE_DISTRICT":
        raise RuntimeError("Not a static scene")
    if manifest.get("original_source_sha256") != SOURCE_HASH:
        raise RuntimeError("Source provenance mismatch")
    if manifest.get("source_unchanged") is not True:
        raise RuntimeError("Frozen architecture changed")
    if manifest.get("live_updates") is not False or manifest.get("animations") is not False:
        raise RuntimeError("The static source must not imply live events")
    if set(manifest.get("buildings", {})) != {f"HB-{i:02d}" for i in range(1,16)}:
        raise RuntimeError("Expected exactly 15 measured buildings")
    if manifest.get("camera", {}).get("projection") != "ORTHO":
        raise RuntimeError("Expected a shared fixed orthographic camera")
    size = manifest.get("camera", {}).get("resolution_px")
    if size not in ([1536, 1728], [4096, 4608]):
        raise RuntimeError("Unapproved camera resolution")
    if set(manifest.get("renders", {})) != {"day", "night"}:
        raise RuntimeError("Day/night references missing")

    staged: dict[str, bytes] = {}
    for theme in ("day", "night"):
        filename = f"FactoryWorld_{theme}.png"
        meta = manifest["renders"][theme]
        data = download(args.commit, filename)
        if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != tuple(size):
            raise RuntimeError("PNG dimensions do not match shared camera")
        if hashlib.sha256(data).hexdigest() != meta.get("sha256"):
            raise RuntimeError("Image SHA-256 mismatch: " + theme)
        if len(data) != meta.get("bytes"):
            raise RuntimeError("Image size mismatch: " + theme)
        staged[theme] = data

    # The JSON file is a Swift-decoded bundled resource (no private API endpoint).
    (root / "Sources/Resources/FactoryWorldStaticManifest.json").write_bytes(manifest_bytes)
    for theme, name in (("day", "FactoryWorldDay"), ("night", "FactoryWorldNight")):
        folder = root / "Assets.xcassets" / (name + ".imageset")
        folder.mkdir(parents=True, exist_ok=True)
        filename = f"FactoryWorld_{theme}.png"
        (folder / filename).write_bytes(staged[theme])
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": filename, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1}
        }, indent=2) + "\n")
    print("S01_ASSETS_STAGED_SHA256_VERIFIED",
          json.dumps({"commit": args.commit, "buildings": 15,
                      "resolution_px": size, "themes": sorted(staged)}, sort_keys=True))

if __name__ == "__main__":
    main()
