#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(path: str, *needles: str) -> None:
    body = read(path)
    missing = [needle for needle in needles if needle not in body]
    if missing:
        raise SystemExit(f"{path}: missing 1.0.10 contract(s): {missing}")


def forbid(path: str, *needles: str) -> None:
    body = read(path)
    found = [needle for needle in needles if needle in body]
    if found:
        raise SystemExit(f"{path}: forbidden 1.0.10 contract(s) present: {found}")


# Primary navigation and locked Start/Nico product hierarchy remain untouched.
require(
    "Sources/App/AppShellView.swift",
    "case home",
    "case rooms",
    "case chat",
    "case media",
    "case system",
    "HomeView(appModel: appModel)",
    "RoomsView(appModel: appModel)",
    "ChatView(appModel: appModel, chatModel: chatModel)",
    "MediaView(appModel: appModel)",
    "SystemView(appModel: appModel)",
)
require(
    "Sources/Features/HomeView.swift",
    'Text("Nico-Zimmer")',
    'if let nicoArea { heroCard(for: nicoArea) }',
)
require(
    "Sources/Features/RoomsView.swift",
    '"media_player.nico_zimmer_untergeschoss_apple_tv"',
    '"media_player.denon_avr_x1300w"',
    '"media_player.playstation_5"',
)

# Repository truth is centralized. Known projects with no canonical repository stay unconfigured.
require(
    "Sources/Core/ProjectRegistry.swift",
    'repository: "Bambis-Lab/ios-next"',
    '"Bambis-Lab/ios-next"',
    'repository: "Bambis-Lab/firetv-companion"',
    'repository: "Bambis-Lab/ha-config"',
    'repository: "Bambis-Lab/ha-intelligence"',
    'repository: "Bambis-Lab/mcp-file-bridge"',
    'id: "global-project-health"',
    'title: "Global Project Health"',
    '"global-health"',
    "repository: nil",
    "defaultBranch: nil",
    "if let descriptor = descriptor(projectID: projectID, title: title, reportedRepository: reportedRepository)",
    "return descriptor.repository",
)
forbid(
    "Sources/Core/ProjectRegistry.swift",
    "Bambis-Lab/master-orchestration",
    '"ha-grok-bridge"',
)
require(
    "Backend/admin_service/core.py",
    '"global-health": {',
    '"title": "Global Project Health"',
    '"repository": None',
)
require(
    "Sources/Features/Owner/Projects/OwnerProjectsView.swift",
    "ProjectRegistry.canonicalRepository(for: route)",
    "Legacy-Mapping korrigiert",
)

# Motion V2 must include deterministic lock and preserve stability-hold frames for frame-by-frame QA.
require(
    "Sources/Design/IOSNextMotionSystem.swift",
    'case controlCenterLock = "control-center-lock"',
    "case .startup: 87",
    "case .controlCenterUnlock: 109",
    "case .controlCenterLock: 27",
    "IOSNextControlCenterLockHost",
    "IOSNextControlCenterLockedSurface",
    "Task.sleep(for: .milliseconds(355))",
    "Task.sleep(for: .milliseconds(340))",
    "Task.sleep(for: .milliseconds(225))",
)
forbid(
    "Sources/Design/IOSNextMotionSystem.swift",
    'Image(systemName: "lock.open.fill")',
)
require(
    "MotionSpecs/IOSNextMotionV2.json",
    '"schema_version": 2',
    '"control-center-lock"',
    '"stability_hold"',
)

# Control Center background is anchored below the NavigationStack so pushed pages do not slide their own gradient.
require(
    "Sources/Features/AdminAreaView.swift",
    "ZStack {",
    "OwnerBackground()",
    "NavigationStack {",
)
require(
    "Sources/Features/Owner/Shared/OwnerAppearance.swift",
    ".background(Color.clear)",
)

# Reconnect UI stays silent for transient sub-second reconnects.
require(
    "Sources/App/ReconnectStatusOverlay.swift",
    "Task.sleep(for: .seconds(1))",
    'Label("Verbindung wird wiederhergestellt …"',
)

# Jarvis wake processing is local-only, foreground-scoped, and never inherits Owner authorization.
require(
    "Sources/Core/JarvisEngine.swift",
    'let wakeWord = "Jarvis"',
    "requiresOnDeviceRecognition = true",
    "supportsOnDeviceRecognition",
    "wakeEvidenceCount >= 2",
    "JarvisIntentRouter.route",
)
forbid(
    "Sources/Core/JarvisEngine.swift",
    "URLSession",
    "AdminControlClient",
    "OwnerDeviceBindingStore",
    "ownerToken",
)
require(
    "Sources/App/AppRootView.swift",
    "JarvisEngine.shared.stopWakeListening()",
)
require(
    "Info.plist",
    "NSSpeechRecognitionUsageDescription",
    "NSMicrophoneUsageDescription",
)
require(
    "Sources/Features/JarvisView.swift",
    "Wake Listening starten",
    "Wake Word ersetzt keine Owner-Authentifizierung",
    "führt erkannte Intents noch nicht automatisch aus",
    'Text("Jarvis")',
    'Text("Empfindlichkeit")',
)

# Xcode 27 rejects the shorthand titled Section initializer when a footer closure is also attached.
forbid(
    "Sources/Features/JarvisView.swift",
    'Section("Jarvis") {',
    'Section("Empfindlichkeit") {',
)
require(
    "Sources/Features/PermissionsCenterView.swift",
    'Text("Sicherheit & System")',
)
forbid(
    "Sources/Features/PermissionsCenterView.swift",
    'Section("Sicherheit & System") {',
)

# Global additions are additive and live under System rather than replacing Start/Nico navigation.
require(
    "Sources/Features/SystemView.swift",
    "GlobalSearchView(appModel: appModel)",
    "PermissionsCenterView(appModel: appModel)",
    "JarvisView(engine: JarvisEngine.shared)",
    'Label("Control Center", systemImage: "slider.horizontal.3")',
)
require(
    "Sources/Features/GlobalSearchView.swift",
    "RoomDetailView(area: area, appModel: appModel)",
    "FloorDetailView(floor: floor, appModel: appModel)",
    "EntityDetailView(entityID: entity.entityID, appModel: appModel)",
)
require(
    "Sources/Features/PermissionsCenterView.swift",
    "SFSpeechRecognizer.authorizationStatus()",
    "AVCaptureDevice.authorizationStatus(for: .video)",
    "UNUserNotificationCenter.current().notificationSettings()",
    "canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics",
)

# Control Center keeps all existing functional drill-down routes while removing landing-page duplication.
require(
    "Sources/Features/Owner/OwnerControlView.swift",
    "RunnerDashboardView(model: runnerModel)",
    "CommanderLiveDetailView(model: runnerModel)",
    "OwnerProjectsView(model: ownerModel, capabilities: capabilities)",
    "OwnerOperationsView(model: ownerModel, capabilities: capabilities)",
    "OwnerSystemsView(model: ownerModel, capabilities: capabilities, appModel: appModel)",
    "OwnerSecurityView(model: ownerModel, capabilities: capabilities)",
    "OwnerCommunicationView(model: ownerModel, capabilities: capabilities)",
    "OwnerReleasesView(model: ownerModel, capabilities: capabilities)",
    "OwnerTicketInboxView(model: ownerModel)",
)
require(
    "Sources/Features/Owner/Notifications/OwnerNotificationsView.swift",
    "Dictionary(grouping: recent, by: \\.type)",
    "Ereignisse",
)

print("iOS Next 1.0.10 migration contracts passed.")
