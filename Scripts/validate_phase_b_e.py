from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from Backend.commander_live.runner_context import read_runner_work_context
from Backend.commander_live.protocol import CommanderSnapshot

def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

entity = text("Sources/Core/HomeAssistantEntity.swift")
media = text("Sources/Design/MediaControlSheet.swift")
model = text("Sources/Core/AppModel.swift")
plist = text("Info.plist")
commander = text("Sources/Core/CommanderLiveModels.swift")

# B
assert "companionSupportsDirectionalNavigation" in entity
for service in ["navigate_up", "navigate_down", "navigate_left", "navigate_right", "navigate_select", "navigate_back", "navigate_home", "navigate_menu"]:
    assert service in media, service
assert 'callFireTVCompanionService(service, for: player)' in media
assert 'if player.companionSupportsDirectionalNavigation' in media
assert 'if player.companionSupportsGlobalNavigation' in media

# C
assert 'func resolvedAreaID(for entityID: String) -> String?' in model
assert 'if let areaID = registry.areaID, !areaID.isEmpty { return areaID }' in model
assert 'return devices.first(where: { $0.id == deviceID })?.areaID' in model
assert 'entities.filter { resolvedAreaID(for: $0.entityID) == areaID }' in model
assert 'ids.insert(deviceID)' in model

# D
assert 'enum EntityValueFormatter' in entity
assert '["unavailable", "unknown", "none", "null", ""]' in entity
assert '<key>UIUserInterfaceStyle</key>' in plist and '<string>Dark</string>' in plist
assert 'ios27ScrollBottomClearance()' in text("Sources/Features/RoomsView.swift")

# E
assert 'struct CommanderWorkContext' in commander
ctx = read_runner_work_context({
    "GITHUB_REPOSITORY": "Bambis-Lab/ios-next",
    "GITHUB_REF_NAME": "phase-b-e-finalize",
    "GITHUB_WORKFLOW": "validate-ios-next-source",
    "GITHUB_JOB": "validate",
    "RUNNER_NAME": "runner-general-01",
    "IOSNEXT_PHASE": "E",
    "IOSNEXT_ELAPSED_SECONDS": "42.5",
    "TOKEN": "must-not-leak",
})
assert ctx is not None
assert ctx["repository"] == "Bambis-Lab/ios-next"
assert ctx["elapsed_seconds"] == 42.5
assert "TOKEN" not in ctx and "progress" not in ctx and "percent" not in ctx
assert read_runner_work_context({"GITHUB_REPOSITORY": "unsafe\\nsecret"}) is None
payload = CommanderSnapshot(work_context=ctx).public_dict()
assert payload["work_context"]["job"] == "validate"
print("PHASE_B_E_PORTABLE=PASS")
