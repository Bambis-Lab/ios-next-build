#!/usr/bin/env python3
"""Strict G99 iPhone-only test contract; never silently omit family or a11y cases."""
from __future__ import annotations

from pathlib import Path
import re
import sys

MANIFEST = Path("Scripts/Acceptance/g99_iphone_manifest.txt")
UITESTS = Path("UITests/IOSNextUITests.swift")
EXPECTED_PREFIX = "IOSNextUITests/IOSNextUITests/"
EXPECTED_A11Y = [
    EXPECTED_PREFIX + "testDynamicTypeAccessibilityState",
    EXPECTED_PREFIX + "testIncreaseContrastAccessibilityState",
]
EXPECTED_FAMILY = EXPECTED_PREFIX + "testUnverifiedFamilyHomeDoesNotExposePersonalizedShortcuts"

def main() -> int:
    raw = MANIFEST.read_text(encoding="utf-8").splitlines()
    if len(raw) != 12 or any(not row or row.strip() != row for row in raw):
        raise ValueError(f"expected exactly 12 nonblank selectors, got {len(raw)}")
    if len(set(raw)) != 12 or any(not row.startswith(EXPECTED_PREFIX) for row in raw):
        raise ValueError("duplicate or unexpected test selector")
    if raw[10:] != EXPECTED_A11Y:
        raise ValueError("the two required accessibility selectors must remain last")
    if EXPECTED_FAMILY not in raw[:10]:
        raise ValueError("unverified family Home safety regression is mandatory")
    swift = UITESTS.read_text(encoding="utf-8")
    for selector in raw:
        method = selector.removeprefix(EXPECTED_PREFIX)
        if not re.search(r"\bfunc\s+" + re.escape(method) + r"\s*\(", swift):
            raise ValueError(f"selector has no matching XCTest implementation: {method}")
    print("G99_MANIFEST_CONTRACT=PASS regular=10 accessibility=2")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as exc:
        print(f"G99_MANIFEST_CONTRACT=FAIL {exc}", file=sys.stderr)
        raise SystemExit(1)
