#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "UITests" / "VisualAcceptanceMatrix.json"
REQUIRED = {
    "id", "category", "surface", "entry", "preconditions", "action",
    "expected_stable_state", "evidence_type", "variants", "retry_policy",
    "failure_classification", "dependencies", "notes",
}

manifest = json.loads(MATRIX.read_text())
scenarios = manifest["scenarios"]
assert manifest["phase"] == "phase1-definition-only"
assert manifest["source_of_truth"].startswith("current product code")
assert len(scenarios) >= 30
ids = [item["id"] for item in scenarios]
assert len(ids) == len(set(ids)), "scenario IDs must be unique"
assert all(REQUIRED <= set(item) for item in scenarios)
assert all(item["preconditions"] and item["action"] for item in scenarios)
assert all(item["expected_stable_state"] and item["evidence_type"] for item in scenarios)
assert all(item["retry_policy"]["max_attempts"] >= 1 for item in scenarios)
assert all(item["retry_policy"]["retryable"] for item in scenarios)
app_shell = (ROOT / "Sources/App/AppShellView.swift").read_text().split("var id")[0]
for tab in ("home", "rooms", "chat", "media", "system"):
    assert f"case {tab}" in app_shell, f"missing current app tab {tab}"

product_root = (ROOT / "Sources/Features/ProductAcceptanceRootView.swift").read_text()
for screen in ("home", "rooms", "chat", "media", "system", "light", "mediaDetail", "owner", "wireguard"):
    assert f"case {screen}" in product_root, f"missing acceptance surface {screen}"

card_source = (ROOT / "Sources/Features/LiveHACardTestModeView.swift").read_text()
card_enum = card_source.split("struct LiveHACardTestModeView")[0]
card_values = []
for line in card_enum.splitlines():
    line = line.strip()
    if line.startswith("case ") and ' = "' in line:
        card_values.append(line.split(' = "', 1)[1].split('"', 1)[0])
manifest_cards = []
for item in scenarios:
    if item["id"].startswith("CARD-"):
        manifest_cards.extend(item["dependencies"])
assert len(card_values) == 12
assert len(manifest_cards) == 12
assert set(card_values) == set(manifest_cards), "card catalog drift"
animation_source = (ROOT / "Sources/Features/AnimationAcceptanceView.swift").read_text().split("var id")[0]
assert "case appStart, navigation, lightToggle, conditional, media, slider, chat, owner" in animation_source
assert len([item for item in scenarios if item["category"] == "animation-stage"]) == 8

accessibility_surfaces = {item["surface"] for item in scenarios if item["category"] == "accessibility"}
assert accessibility_surfaces == {
    "dynamic-type-xxxl", "reduce-motion", "reduce-transparency", "increase-contrast"
}
assert "CLD-001" in ids
assert "ORIENT-001" in ids
assert len(manifest["legacy_classification"]) >= 11
assert any(
    item["legacy"] == "run 35295372707" and item["classification"] == "reference-evidence-only"
    for item in manifest["legacy_classification"]
)

exclusion_text = " ".join(
    item["scope"] + " " + item["reason"] for item in manifest["explicit_exclusions"]
).lower()
for word in ("authentication", "network", "owner", "wireguard", "runner", "final simulator", "library"):
    assert word in exclusion_text, f"missing safety exclusion: {word}"

print(f"Visual acceptance matrix valid: {len(scenarios)} scenarios, {len(manifest_cards)} card types")
