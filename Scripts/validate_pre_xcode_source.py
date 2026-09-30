#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

EXPECTED_OWNER_FILES = [
    "Sources/Features/Owner/OwnerModels.swift",
    "Sources/Features/Owner/OwnerControlView.swift",
    "Sources/Features/Owner/OwnerOverviewView.swift",
    "Sources/Features/Owner/Shared/OwnerComponents.swift",
    "Sources/Features/Owner/Shared/OwnerAppearance.swift",
    "Sources/Features/Owner/Systems/OwnerSystemsView.swift",
    "Sources/Features/Owner/Operations/OwnerOperationsView.swift",
    "Sources/Features/Owner/Projects/OwnerProjectsView.swift",
    "Sources/Features/Owner/Security/OwnerSecurityView.swift",
    "Sources/Features/Owner/Communication/OwnerCommunicationView.swift",
    "Sources/Features/Owner/Releases/OwnerReleasesView.swift",
    "Sources/Features/Owner/Notifications/OwnerNotificationsView.swift",
]


def fail(message: str) -> None:
    errors.append(message)


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        fail(f"missing required file: {rel}")
        return ""
    return path.read_text(encoding="utf-8")


for rel in EXPECTED_OWNER_FILES:
    read(rel)

for rel in (
    "Sources/Core/AdminControlV2Models.swift",
    "Sources/Core/OwnerDeviceBinding.swift",
    "Backend/admin_service/v2.py",
    "HAAddons/iosnext-owner-admin/config.yaml",
    "HAAddons/iosnext-owner-admin/Dockerfile",
    "HAAddons/iosnext-owner-admin/run.sh",
):
    read(rel)

project = read("project.yml")
if not re.search(r"(?m)^\s*-\s+Sources\s*$", project):
    fail("project.yml no longer includes the complete Sources tree")

owner_root = ROOT / "Sources/Features/Owner"
owner_text = "\n".join(p.read_text(encoding="utf-8") for p in owner_root.rglob("*.swift"))
for marker in ("TODO", "FIXME", "HACK", "demo token", "fake token"):
    if marker.lower() in owner_text.lower():
        fail(f"Owner source contains unfinished marker: {marker}")
for forbidden in ("URLSession", "URLRequest", "/v1/admin/"):
    if forbidden in owner_text:
        fail(f"Owner UI bypasses backend adapter/client boundary: {forbidden}")
for secret_prefix in ("sk-", "ghp_", "github_pat_", "Bearer eyJ"):
    if secret_prefix in owner_text:
        fail(f"Owner source appears to contain a secret literal: {secret_prefix}")

home = read("Sources/Features/HomeView.swift")
if "compactGroundFloor" in home:
    fail("legacy compactGroundFloor hierarchy is still present")
for required in (
    'home-shortcut-timo',
    'home-shortcut-huette',
    'home-shortcut-outdoors',
    'home-shortcut-ground-floor',
):
    # dynamic identifier source only contains prefix; exact IDs are asserted by UI tests.
    if required.startswith("home-shortcut-") and 'accessibilityIdentifier("home-shortcut-\\(item.id)")' not in home:
        fail("Home shortcut accessibility contract missing")
        break

outdoor = read("Sources/Features/OutdoorAreaView.swift")
for identifier in ("outdoor-resource-pool", "outdoor-resource-lawn", "outdoor-resource-mower"):
    if identifier not in outdoor:
        fail(f"Outdoor resource identifier missing: {identifier}")

rooms = read("Sources/Features/RoomsView.swift")
if "if !isPoolRoom && !isRasenRoom" not in rooms:
    fail("specialized Pool/Rasen details still duplicate the generic room header")

if 'media_player.juli_zimmer_fire_tv_192_168_178_75' in rooms:
    fail("Juli room still binds directly to legacy AndroidTV/ADB player")
if 'appModel.fireTVCompanion(inArea: "juli_zimmer")' not in rooms:
    fail("Juli room does not require a room-scoped Fire TV Companion")

entity = read("Sources/Core/HomeAssistantEntity.swift")
for raw, label in (
    ('"mode_ready"', '"Bereit"'),
    ('"docked"', '"In Ladestation"'),
    ('"returning_home"', '"Fährt zur Ladestation"'),
):
    if raw not in entity or label not in entity:
        fail(f"state presentation mapping missing: {raw} -> {label}")

metrics = read("Sources/Core/PresentationMetrics.swift")
for required in ("deviceCount", "activeDeviceCount", "entityCount", "activeEntityCount", "unavailableEntityCount"):
    if required not in metrics:
        fail(f"metric semantic missing: {required}")

media_cards = read("Sources/Design/IOS27DashboardCards.swift")
if "if player.companionSupportsVolumeControl, player.supportsVolumeSet" in media_cards:
    fail("normal Denon/media slider is still incorrectly gated by Fire TV capability")
if "if player.supportsVolumeSet, let volume = player.volumeLevel" not in media_cards:
    fail("standard media-player volume slider contract missing")

scenes = read("Sources/Features/ScenesView.swift")
if ".disabled(!entity.isAvailable)" not in scenes:
    fail("unavailable scenes/scripts are not fail-closed")

uitests = read("UITests/IOSNextUITests.swift")
if 'staticTexts["Häufig genutzt"]' not in uitests:
    fail("Home accessibility UI test does not target current 'Häufig genutzt' section")
if 'staticTexts["Favoriten"]' in uitests:
    fail("stale Home accessibility label 'Favoriten' remains in UI tests")


commander_models = read("Sources/Core/CommanderLiveModels.swift")
commander_client = read("Sources/Core/RunnerLiveClient.swift")
commander_view = read("Sources/Features/CommanderLiveDetailView.swift")
runner_client = read("Sources/Core/RunnerControlClient.swift")
commander_tests = read("Tests/CommanderLiveTests.swift")
for required in (
    "CommanderLiveViewState",
    "needsFullResync",
    'event.type == "commander.snapshot"',
    'case "commander.activity.started"',
    'case "commander.activity.completed"',
):
    if required not in commander_models:
        fail(f"Commander live reducer contract missing: {required}")
for forbidden in (
    "arguments:", "output:", "command:", "filename:", "prompt:",
    "accessToken:", "refreshToken:", "fileContent:", "privateKey:",
):
    if forbidden in commander_models:
        fail(f"Commander public payload exposes forbidden field: {forbidden}")
if r'Bearer \(liveToken)' not in commander_client:
    fail("Commander live client does not authenticate with the dedicated live token")
if r'Bearer \(configuration.token)' in commander_client:
    fail("Commander live client falls back to the control token")
for required in ("runnerLiveToken", "liveToken", "status.commander", "startCommanderLiveIfNeeded"):
    if required not in runner_client:
        fail(f"Runner commander capability gate missing: {required}")
for required in ("MasterRuntimeSnapshot", "Master Runtime", "Befehle, Argumente, Tokens und Dateiinhalte werden nicht übertragen"):
    if required not in commander_view:
        fail(f"Commander live UI contract missing: {required}")
if "testReducerRequiresResyncOnSequenceGap" not in commander_tests:
    fail("Commander live sequence-gap unit test missing")
if "testCommanderLiveFixtureStatusAndWebSocketUseSeparatedCredentials" not in commander_tests:
    fail("Commander live real WebSocket fixture integration test missing")
workflow = read("migration/legacy-workflows/ios.yml")
for required in (
    "Start fake Runner Commander test server",
    "FAKE_RUNNER_CONTROL_TOKEN",
    "FAKE_RUNNER_LIVE_TOKEN",
    "fake-commander.pid",
):
    if required not in workflow:
        fail(f"Commander Xcode fixture gate missing: {required}")

admin_client = read("Sources/Core/AdminControlClient.swift")
for required in (
    'func capabilitiesV2',
    'func ensureDeviceSession',
    'func openBreakGlass',
    'OwnerDeviceBindingStore',
    'X-Owner-Device-Session',
    'X-Break-Glass-Session',
):
    if required not in admin_client:
        fail(f"Owner v2 client contract missing: {required}")

admin_area = read("Sources/Features/AdminAreaView.swift")
if "model.ownerCapabilityRegistry" not in admin_area:
    fail("AdminAreaView does not use discovered Owner capabilities with v1 fallback")
if "Geräte-Kopplungscode" not in admin_area:
    fail("Owner first-device enrollment UI is missing")

# Lightweight delimiter check catches truncated or malformed edits without pretending to compile Swift.
def balanced_swift(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    stack: list[tuple[str, int]] = []
    pairs = {"}": "{", ")": "(", "]": "["}
    opens = set(pairs.values())
    i = 0
    line = 1
    state = "code"
    block_depth = 0
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if c == "\n":
            line += 1
        if state == "line_comment":
            if c == "\n": state = "code"
            i += 1; continue
        if state == "block_comment":
            if c == "/" and n == "*": block_depth += 1; i += 2; continue
            if c == "*" and n == "/":
                block_depth -= 1; i += 2
                if block_depth == 0: state = "code"
                continue
            i += 1; continue
        if state == "string":
            if c == "\\": i += 2; continue
            if c == '"': state = "code"
            i += 1; continue
        if c == "/" and n == "/": state = "line_comment"; i += 2; continue
        if c == "/" and n == "*": state = "block_comment"; block_depth = 1; i += 2; continue
        if c == '"': state = "string"; i += 1; continue
        if c in opens:
            stack.append((c, line))
        elif c in pairs:
            if not stack or stack[-1][0] != pairs[c]:
                fail(f"delimiter mismatch in {path.relative_to(ROOT)} line {line}: {c}")
                return
            stack.pop()
        i += 1
    if state == "block_comment": fail(f"unterminated block comment in {path.relative_to(ROOT)}")
    if state == "string": fail(f"unterminated string in {path.relative_to(ROOT)}")
    if stack:
        opener, opened_line = stack[-1]
        fail(f"unclosed delimiter {opener} in {path.relative_to(ROOT)} from line {opened_line}")

for path in sorted((ROOT / "Sources").rglob("*.swift")):
    text = path.read_text(encoding="utf-8")
    if "\\\\." in text:
        fail(f"double-escaped Swift key path in {path.relative_to(ROOT)}")
    balanced_swift(path)
for path in sorted((ROOT / "Tests").rglob("*.swift")):
    balanced_swift(path)
for path in sorted((ROOT / "UITests").rglob("*.swift")):
    balanced_swift(path)

if errors:
    print("Pre-Xcode source validation FAILED:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(f"Pre-Xcode source validation passed ({len(EXPECTED_OWNER_FILES)} Owner files; Swift delimiter scan complete).")
