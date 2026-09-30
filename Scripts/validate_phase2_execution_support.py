#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATRIX = json.loads((ROOT / "UITests/VisualAcceptanceMatrix.json").read_text())
UITESTS = (ROOT / "UITests/IOSNextUITests.swift").read_text()
RUNNER = (ROOT / "Scripts/run_phase2_visual_acceptance.sh").read_text()

scenarios = MATRIX["scenarios"]
assert len(scenarios) == 38
variant_count = sum(
    len(item.get("variants", {}).get("appearance", ["light"]))
    * len(item.get("variants", {}).get("devices", ["iphone-18-pro-max"]))
    for item in scenarios
)
assert variant_count == 176, variant_count
assert "func testPhase2Scenario()" in UITESTS

literal_ids = {
    "CLD-001", "SETUP-001", "SHELL-001", "SHELL-002", "SHELL-003",
    "SHELL-004", "SHELL-005", "DETAIL-001", "DETAIL-002", "OWNER-001",
    "WG-001", "RUNNER-001", "CHAT-INT-001", "LIGHT-INT-001", "ORIENT-001",
}
for scenario_id in literal_ids:
    assert scenario_id in UITESTS, f"missing dispatcher mapping: {scenario_id}"

range_markers = {
    "NAV-": 'case "NAV-001"..."NAV-007"',
    "A11Y-": 'case "A11Y-001"..."A11Y-004"',
    "CARD-": 'case "CARD-001"..."CARD-003"',
    "ANIM-": 'case "ANIM-001"..."ANIM-009"',
}
for prefix, marker in range_markers.items():
    assert marker in UITESTS, f"missing range dispatcher: {prefix}"

for item in scenarios:
    sid = item["id"]
    if sid in literal_ids:
        continue
    assert any(sid.startswith(prefix) for prefix in range_markers), sid

assert 'MATRIX_JSON_SHA256="0fad724ea19da47266a46405db951cfa7a715f0c237fb0cf50852e98665a097c"' in RUNNER
assert 'MATRIX_DOC_SHA256="acad10e9c85fb9eb65fc7c5fbf9681f65daf6dd84aa6db598c7af17d1eccb17e"' in RUNNER
assert 'Phase-1 matrix JSON hash drift' in RUNNER
assert 'Phase-1 matrix documentation hash drift' in RUNNER
assert 'phase2-plan.tsv' in RUNNER
assert 'phase2_results.py' in RUNNER
assert 'testPhase2Scenario' in RUNNER
assert 'recordVideo' in RUNNER
assert 'validate_visual_video.swift' in RUNNER

print(f"Phase2 execution support valid: {len(scenarios)} scenarios, {variant_count} variants")
