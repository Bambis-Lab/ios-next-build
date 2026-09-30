#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
script = (ROOT / "Scripts" / "run_motion_frame_acceptance.sh").read_text(encoding="utf-8")

required = [
    "xcodebuild build-for-testing",
    "xcrun simctl create",
    "xcrun simctl install",
    "xcrun simctl get_app_container",
    "--motion-acceptance-sequence=$sequence",
    "--motion-frame=$frame",
    "--visual-ready-nonce=$nonce",
    "iosnext-motion-ready-${sequence}-${frame}-${nonce}",
    "xcrun simctl io \"$SIMULATOR_UDID\" screenshot",
    "capture_sequence startup 87",
    "capture_sequence control-center-unlock 109",
    "capture_sequence control-center-lock 27",
    "capture_strategy=host-simctl-fresh-simulator-ready-marker",
]

missing = [needle for needle in required if needle not in script]
if missing:
    raise SystemExit(f"motion capture contract missing: {missing}")

forbidden = [
    "IOSNEXT_RUN_MOTION_MASTER_FRAMES",
    "IOSNEXT_MOTION_OUTPUT_DIR",
    "-only-testing:IOSNextUITests/IOSNextUITests/testDeterministicMotionMasterFrames",
    "-only-testing:IOSNextUITests/MotionV2LockUITests/testDeterministicControlCenterLockFrames",
]

found = [needle for needle in forbidden if needle in script]
if found:
    raise SystemExit(f"motion capture regressed to test-process environment transport: {found}")

print("Motion capture contract valid: host-driven simctl capture, 223 deterministic frames.")
