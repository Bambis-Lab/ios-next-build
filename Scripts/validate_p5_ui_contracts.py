from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"P5_UI_CONTRACT=FAIL missing {label}: {needle}")


def reject(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise SystemExit(f"P5_UI_CONTRACT=FAIL stale {label}: {needle}")


media = read("Sources/Features/MediaView.swift")
ui_tests = read("UITests/IOSNextUITests.swift")
preview = read("Sources/Core/PreviewData.swift")
home = read("Sources/Features/HomeView.swift")
system = read("Sources/Features/SystemView.swift")
live_operations = read("Sources/Features/LiveOperationsView.swift")

# Media summary must stay dynamic in production while UI tests bind to a stable identifier.
require(media, 'Text("\\(activePlayerCount) Player sind aktiv")', "dynamic media summary")
require(media, '.accessibilityIdentifier("media-active-summary")', "media summary identifier")
require(ui_tests, '.matching(identifier: "media-active-summary")', "media UI test identifier")
reject(ui_tests, '"2 Player sind aktiv"', "hard-coded active-player count")

# Product acceptance must deterministically provide the approved fourth Home shortcut.
require(preview, 'HomeAssistantFloor(id: "preview-ground-floor", name: "Erdgeschoss", level: 0)', "preview ground floor fallback")
require(home, 'id: "ground-floor"', "ground-floor shortcut model")
require(ui_tests, '"home-shortcut-ground-floor"', "ground-floor UI assertion")

# Live Operations must remain reachable from System and expose a fail-closed unconfigured state.
require(system, 'LiveOperationsView()', "Live Operations destination")
require(system, '.accessibilityIdentifier("system-live-operations")', "Live Operations navigation identifier")
require(live_operations, 'Live Operations nicht eingerichtet', "Live Operations safe state")
require(ui_tests, 'func testLiveOperationsSafeEntryState()', "Live Operations UI test")
require(ui_tests, '"system-live-operations"', "Live Operations UI selector")
require(ui_tests, '"Live Operations nicht eingerichtet"', "Live Operations safe-state assertion")

print("P5_UI_CONTRACT=PASS")
