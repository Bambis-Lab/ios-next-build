#!/usr/bin/env python3
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Full-file Git blob locks. HomeView retains the 1.0.9 Build 11 baseline; RoomsView uses the approved Greenfield Juli-Companion baseline after proving the only source delta is JuliRoomDashboardContent.
EXPECTED_GIT_BLOBS = {
    "Sources/Features/HomeView.swift": "655ab474508faca0036ff072cc89b84f4e58172a",
    "Sources/Features/RoomsView.swift": "2a505274216f2f6a237709287f4c96b5120c82c6",
}


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


for relative, expected_blob in EXPECTED_GIT_BLOBS.items():
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"Layout lock missing file: {relative}")
    actual = git_blob_sha1(path.read_bytes())
    if actual != expected_blob:
        raise SystemExit(
            f"Layout lock violation: {relative} changed "
            f"(expected baseline blob {expected_blob}, got {actual})"
        )

print("Layout lock valid: HomeView matches 1.0.9 and RoomsView matches approved Greenfield Juli-Companion baseline exactly.")
