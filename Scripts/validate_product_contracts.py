#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(path: str, *needles: str) -> None:
    body = text(path)
    missing = [needle for needle in needles if needle not in body]
    if missing:
        raise SystemExit(f"{path}: missing product contract(s): {missing}")


def forbid(path: str, *needles: str) -> None:
    body = text(path)
    found = [needle for needle in needles if needle in body]
    if found:
        raise SystemExit(f"{path}: forbidden product contract(s) present: {found}")


# Root-tab semantics: selecting any primary tab replaces that tab's navigation root.
require(
    "Sources/App/AppShellView.swift",
    "@State private var navigationPaths: [AppTab: NavigationPath]",
    "NavigationStack(path: navigationPathBinding(for: tab))",
    "navigationPaths[tab] = NavigationPath()",
)

# Home keeps the Nico hero and uses the approved symmetric shortcut hierarchy.
require(
    "Sources/Features/HomeView.swift",
    'private var nicoArea: HomeAssistantArea? { area(named: "Nico Zimmer") }',
    'if let nicoArea { heroCard(for: nicoArea) }',
    'private var groundFloor: HomeAssistantFloor?',
    'title: "Erdgeschoss"',
    'title: "Außenbereich"',
    'destination: .outdoors',
    'Text("Nico-Zimmer")',
    'HomeMetricTile(title: "Nicht erreichbar"',
)
forbid(
    "Sources/Features/HomeView.swift",
    'compactGroundFloor',
    'sectionTitle("Etagen")',
    'ForEach(homeFloors)',
)
require(
    "Sources/Features/OutdoorAreaView.swift",
    'title: "Pool"',
    'title: "Rasen"',
    'title: "Mähroboter"',
    'struct MowerResourceView: View',
)
require(
    "Sources/Core/PresentationMetrics.swift",
    "struct ResourceMetrics",
    "activeDeviceCount",
    "activeEntityCount",
    "unavailableEntityCount",
)
require(
    "Sources/Core/HomeAssistantClient.swift",
    'optionalRegistryCommand(type: "config/floor_registry/list")',
    'optionalRegistryCommand(type: "config/area_registry/list")',
)
require(
    "Sources/Core/HomeAssistantRegistry.swift",
    "struct HomeAssistantFloor",
    "let floorID: String?",
    'object["floor_id"]?.stringValue',
)

# Home Assistant onboarding supports only narrowly-scoped cleartext overlays.
require(
    "Sources/Core/HomeAssistantOAuthService.swift",
    'isAllowedInsecureHost(host)',
    'value.hasSuffix(".ts.net")',
    'return octets[0] == 100 && (64 ... 127).contains(octets[1])',
    'authorizationSessionFailed(error.localizedDescription)',
    'tokenTransportFailed(error.localizedDescription)',
    '"OAuth-Rückruf fehlgeschlagen:',
    '"Token-Austausch mit Home Assistant fehlgeschlagen',
)
require(
    "Sources/Core/AppModel.swift",
    'failurePrefix: "WebSocket-Verbindung nach OAuth fehlgeschlagen"',
)
require(
    "Info.plist",
    '<key>100.64.0.0/10</key>',
    '<key>ts.net</key>',
    '<key>NSExceptionAllowsInsecureHTTPLoads</key>',
    '<key>NSIncludesSubdomains</key>',
)

# Connection status is a neutral material badge; status color belongs only to the dot.
require(
    "Sources/Design/IOS27HomeComponents.swift",
    "struct HomeConnectionPill",
    ".background(.thinMaterial, in: Capsule())",
    ".fill(tint)",
    ".font(.caption.weight(.medium))",
)
forbid(
    "Sources/Design/IOS27HomeComponents.swift",
    ".ios27Surface(radius: 18, tint: tint)",
)

# Ambient v2 must be visibly color-led rather than a near-black micro-glow.
require(
    "Sources/Design/IOS27HomeComponents.swift",
    "Color.black",
    "0.44 * intensity",
    "0.32 * intensity",
    "0.26 * intensity",
    "endRadius: 620",
)

# Nico media remains coupled: Apple TV is playback, Denon is output, PS5 stays separate.
require(
    "Sources/Features/RoomsView.swift",
    '"media_player.nico_zimmer_untergeschoss_apple_tv"',
    '"media_player.denon_avr_x1300w"',
    '"media_player.playstation_5"',
    'coupledPlaybackPlayerID: "media_player.nico_zimmer_untergeschoss_apple_tv"',
    'coupledOutputPlayerID: "media_player.denon_avr_x1300w"',
)
require(
    "Sources/Design/MediaControlSheet.swift",
    ".presentationDetents([.medium, .large])",
    "seekRelative(-10",
    "seekRelative(10",
    "volumeControls(outputPlayer)",
    'sourceControls(outputPlayer, title: "Eingang")',
)

# Media sheets share one visual component language and keep secondary actions restrained.
require(
    "Sources/Design/MediaControlSheet.swift",
    "private struct MediaSheetHeader",
    "private struct MediaNowPlayingSurface",
    "private struct MediaChoiceChip",
    "private struct MediaTransportButton",
    "private struct MediaVolumeControl",
    "mediaBackgroundStyle(for: player)",
    "sourceButton(source, for: player)",
)

# Fire TV controls must remain capability-gated.
require(
    "Sources/Design/MediaControlSheet.swift",
    "companionSupportsPlayerControl",
    "companionSupportsVolumeControl",
    "companionSupportsMuteControl",
    "companionSupportsGlobalNavigation",
    "companionSupportsLaunchApps",
    "companionSupportsWakeControl",
    "companionSupportsStandbyControl",
    '(size ?? 1) > 0',
    'private func launchableApps',
    'DisclosureGroup(apps.isEmpty ? "App manuell öffnen" : "Weitere Optionen")',
)
forbid(
    "Sources/Design/MediaControlSheet.swift",
    'TextField("Android-Paketname"',
)

# Juli TV backlight is visibly coupled and cannot be turned on from the app while TV is off.
require(
    "Sources/Features/RoomsView.swift",
    'light.battletron_gaming_monitor_strip_2024_fernseher_hintergrund',
    'private var tvAllowsLight: Bool { tv?.isOn == true }',
    'private var canToggle: Bool { light.isOn || tvAllowsLight }',
    'canTurnOn: tvAllowsLight',
    'turnOnBlockedReason: "Nur bei eingeschaltetem Juli TV"',
)
require(
    "Sources/Design/LightControlSheet.swift",
    "var canTurnOn: Bool = true",
    "guard !value || canTurnOn else { return }",
)

# Shared ambient engine must be room-aware and accessibility-safe.
require(
    "Sources/Design/IOS27HomeComponents.swift",
    "enum IOS27AmbientBackgroundStyle",
    "case nico(mediaActive: Bool)",
    "case juli(lightAccent: Color?)",
    "@Environment(\\.accessibilityReduceTransparency)",
    "let accessibilityFactor = reduceTransparency ? 0.72 : 1.0",
)
require(
    "Sources/Features/RoomsView.swift",
    'let nicoMediaActive = entity("binary_sensor.nico_medien_aktiv")?.isOn == true',
    "juliAccent: juliAccent",
    ".background(IOS27HomeBackground(style: roomBackgroundStyle))",
)

# Runner Control stays fixed-endpoint, HTTPS-only in release, and biometric for critical actions.
require(
    "Sources/Core/RunnerControlClient.swift",
    'case .healthCheck: "v1/health-check"',
    'case .pause: "v1/runners/pause"',
    'case .resume: "v1/runners/resume"',
    'case .gracefulRestart: "v1/runners/restart-gracefully"',
    'case .shutdown: "v1/vm/shutdown"',
    'return scheme == "https"',
    "self == .gracefulRestart || self == .shutdown",
    "case bridge, orchestrator, commander, services, backup",
    'case recentAudit = "recent_audit"',
)
forbid(
    "Sources/Core/RunnerControlClient.swift",
    "shellCommand",
    "arbitraryCommand",
    "Process()",
)
require(
    "RUNNER_CONTROL_API.md",
    "The app never accepts arbitrary shell commands.",
    "optional extension fields",
)


# Owner Control is hierarchical, capability-driven, and keeps risky actions off the overview.
require(
    "Sources/Features/Owner/OwnerOverviewView.swift",
    'IOSNextSectionHeader(title: "Aufmerksamkeit"',
    'IOSNextSectionHeader(title: "Schnellaktionen"',
    'ownerLink(.systems)',
    'ownerLink(.operations)',
    'ownerLink(.projects)',
    'ownerLink(.security)',
    'ownerLink(.communication)',
    'ownerLink(.releases)',
)
forbid(
    "Sources/Features/Owner/OwnerOverviewView.swift",
    '.enableMaintenance',
    '.disableMaintenance',
    '.clearCache',
    '.reconnectSessions',
)
require(
    "Sources/Features/Owner/OwnerModels.swift",
    "struct OwnerCapabilityRegistry",
    "static let currentAdminAPI",
    "enum OwnerConnectionPhase",
    "enum OwnerRiskLevel",
    "var ownerRiskLevel: OwnerRiskLevel",
)
require(
    "Sources/Features/Owner/Shared/OwnerComponents.swift",
    "struct OwnerActionSheet",
    "struct OwnerConnectionIndicator",
    "Owner Backend:",
)
require(
    "Sources/Features/Owner/Shared/OwnerAppearance.swift",
    "struct OwnerBackground",
    "struct OwnerPage",
    "Color.indigo",
)
require(
    "Sources/Features/AdminAreaView.swift",
    'navigationTitle("Control Center")',
    "runnerModel: runtime.runnerModel",
    "OwnerNotificationsView(model: model)",
    "Geräte-Kopplungscode",
)
require(
    "Sources/Features/SystemView.swift",
    'Label("Control Center", systemImage: "slider.horizontal.3")',
    "AdminAreaView(appModel: appModel)",
)
require(
    "Sources/Features/Owner/OwnerControlView.swift",
    "ControlCenterView(",
    "RunnerDashboardView(model: runnerModel)",
    "CommanderLiveDetailView(model: runnerModel)",
    "OwnerProjectsView(model: ownerModel, capabilities: capabilities)",
    "OwnerOperationsView(model: ownerModel, capabilities: capabilities)",
)
forbid(
    "Sources/Features/ChatView.swift",
    'Button("Owner Control"',
    "isPresentingOwnerControl",
    "AdminAreaView(appModel: appModel)",
)
require(
    "Sources/Features/RunnerDashboardView.swift",
    "RunnerDashboardView: View",
)
require(
    "Sources/Core/RunnerControlClient.swift",
    "catch is CancellationError",
    "catch let error as URLError where error.code == .cancelled",
)
forbid(
    "Sources/Features/RunnerDashboardView.swift",
    ".onDisappear { model.stopCommanderLive() }",
)
require(
    "Sources/Design/IOSNextMotionSystem.swift",
    "masterFramesPerSecond = 120.0",
    "case .startup: 87",
    "case .controlCenterUnlock: 109",
    "IOSNextStartupRevealHost",
    "IOSNextControlCenterUnlockHost",
)
require(
    "Sources/Features/MotionAcceptanceView.swift",
    "motion-acceptance-root",
    "motion-next-frame",
)
require(
    "Sources/Design/IOSNextFeedback.swift",
    "controlCenterUnlock",
    "iosnext.feedback.haptics.enabled",
    "iosnext.feedback.sounds.enabled",
)
require(
    "Sources/Core/AdminControlClient.swift",
    'func capabilitiesV2',
    'func systemsV2',
    'func openBreakGlass',
    'func ensureDeviceSession',
    'X-Owner-Device-Session',
    'X-Break-Glass-Session',
)
require(
    "Sources/Core/OwnerDeviceBinding.swift",
    "P256.Signing.PrivateKey",
    "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
)
forbid(
    "Sources/Core/AdminControlClient.swift",
    "shellCommand",
    "arbitraryCommand",
    "Process()",
)
require(
    "Sources/Features/Owner/Security/OwnerSecurityView.swift",
    'title: "Break-Glass"',
    'title: "Freie Shell"',
    'value: "Nicht verfügbar"',
)

# State presentation and device/entity metrics must be normalized centrally.
require(
    "Sources/Core/HomeAssistantEntity.swift",
    'case "idle", "ready", "mode_ready": "Bereit"',
    'case "docked", "parked": "In Ladestation"',
    'case "returning", "returning_home": "Fährt zur Ladestation"',
)
require(
    "Sources/Core/PresentationMetrics.swift",
    "activeDeviceCount",
    "activeEntityCount",
)

# Unavailable media/actions fail closed and scenes keep action semantics.
require(
    "Sources/Design/MediaControlSheet.swift",
    "if player.isAvailable {",
    'detail: "Steueraktionen sind deaktiviert."',
    'detail: "Wake-, Wiedergabe- und Navigationsaktionen sind deaktiviert."',
)
require(
    "Sources/Features/ScenesView.swift",
    'entity.isAvailable ? "Bereit zum Aktivieren" : "Nicht verfügbar"',
    ".disabled(!entity.isAvailable)",
)

# Nico/Denon volume is a real media-player slider, not Fire-TV capability-gated.
require(
    "Sources/Design/IOS27DashboardCards.swift",
    "if player.supportsVolumeSet, let volume = player.volumeLevel",
    'Image(systemName: "speaker.wave.3.fill")',
)
forbid(
    "Sources/Design/IOS27DashboardCards.swift",
    "if player.companionSupportsVolumeControl, player.supportsVolumeSet, let volume = player.volumeLevel",
)

# Light details use the iOS Next visual language rather than a standalone Form surface.
require(
    "Sources/Design/LightControlSheet.swift",
    "IOS27HomeBackground(style: .neutral)",
    ".ios27ContentSurface(radius: 24)",
    ".ios27ScrollBottomClearance()",
)
forbid(
    "Sources/Design/LightControlSheet.swift",
    "Form {",
)

print("Product contract validation passed.")

# Shared room components reference these views across source files.
require(
    "Sources/Features/RoomsView.swift",
    "struct DeviceDetailView: View",
    "struct DeviceRow: View",
)
forbid(
    "Sources/Features/RoomsView.swift",
    "private struct DeviceDetailView: View",
    "private struct DeviceRow: View",
)
