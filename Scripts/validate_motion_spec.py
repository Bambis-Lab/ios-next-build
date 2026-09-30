#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = json.loads((ROOT / "MotionSpecs/IOSNextMotionV2.json").read_text())
swift = (ROOT / "Sources/Design/IOSNextMotionSystem.swift").read_text()

assert spec["schema_version"] == 2
assert spec["master_fps"] == 120
assert "masterFramesPerSecond = 120.0" in swift

expected = {
    "startup": (87, 86, 42),
    "control-center-unlock": (109, 108, 50),
    "control-center-lock": (27, 26, 26),
}

for name, (count, last, visible_end) in expected.items():
    seq = spec["sequences"][name]
    assert seq["frame_count"] == count and seq["last_frame"] == last
    assert seq["visible_end_frame"] == visible_end
    covered = set()
    for phase in seq["phases"]:
        assert 0 <= phase["start"] <= phase["end"] <= last
        covered.update(range(phase["start"], phase["end"] + 1))
    assert covered == set(range(last + 1)), (name, sorted(set(range(last + 1)) - covered))
    assert 0 <= seq["interactive_frame"] <= last
    for cue in seq.get("haptics", []) + seq.get("sounds", []):
        assert 0 <= cue["frame"] <= visible_end

assert "case .startup: 87" in swift
assert "case .controlCenterUnlock: 109" in swift
assert "case .controlCenterLock: 27" in swift
assert "IOSNextControlCenterLockHost" in swift
assert "IOSNextControlCenterLockedSurface" in swift

print("Motion V2 spec valid: 120 Hz, 223 deterministic frames, 3 sequences")
