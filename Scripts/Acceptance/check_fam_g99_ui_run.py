#!/usr/bin/env python3
"""Fail-closed G99 log classifier: retry only a single Xcode app-launch timeout.

No functional XCTAssert failures, missing selectors or partial runs count as PASS.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

MANIFEST = Path("Scripts/Acceptance/g99_iphone_manifest.txt")
SUITE = "IOSNextUITests.IOSNextUITests"
LAUNCH_ERROR = re.compile(
    r"error: -\\[" + re.escape(SUITE) +
    r" (test\\w+)\\] : Failed to launch .* via Xcode: "
    r"Timed out while launching application via Xcode\\."
)
FAILED = re.compile(
    r"Test Case '-\\[" + re.escape(SUITE) + r" (test\\w+)\\]' failed \\("
)
PASSED = re.compile(
    r"Test Case '-\\[" + re.escape(SUITE) + r" (test\\w+)\\]' passed \\("
)


def mandatory_names() -> list[str]:
    selectors = MANIFEST.read_text(encoding="utf-8").splitlines()
    if len(selectors) != 12 or len(set(selectors)) != 12:
        raise ValueError("Mandatory G99 manifest mismatch")
    prefix = "IOSNextUITests/IOSNextUITests/"
    if any(not s.startswith(prefix) for s in selectors):
        raise ValueError("Unexpected G99 selector")
    return [s.removeprefix(prefix) for s in selectors[:10]]


def is_infrastructure_only(log: str) -> bool:
    """One failed selected test, exactly one launch-timeout error, no assertions."""
    failing = FAILED.findall(log)
    launch_errors = LAUNCH_ERROR.findall(log)
    if len(failing) != 1 or launch_errors != failing:
        return False
    if failing[0] not in mandatory_names():
        return False
    if re.search(r"XCTAssert\\w* failed|Assertion Failure|XCTFail", log):
        return False
    # Every test-level Xcode error must be this exact launch timeout.
    for line in log.splitlines():
        if "error: -[" in line and not LAUNCH_ERROR.search(line):
            return False
    if "TEST EXECUTE FAILED" not in log:
        return False
    return True


def is_full_pass(log: str) -> bool:
    expected = mandatory_names()
    passed = PASSED.findall(log)
    return (
        len(passed) == len(expected)
        and sorted(passed) == sorted(expected)
        and not FAILED.search(log)
        and "Executed 10 tests, with 0 failures" in log
        and "Test Suite 'Selected tests' passed" in log
        and "** TEST EXECUTE SUCCEEDED **" in log
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["classify", "verify"])
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    log = args.log.read_text(encoding="utf-8", errors="replace")
    valid = is_infrastructure_only(log) if args.mode == "classify" else is_full_pass(log)
    print(f"G99_UI_{args.mode.upper()}={'PASS' if valid else 'FAIL'}")
    return 0 if valid else 65


if __name__ == "__main__":
    raise SystemExit(main())
