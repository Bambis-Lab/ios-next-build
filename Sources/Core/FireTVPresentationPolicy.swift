import Foundation

enum FireTVPresentationState: Equatable, Sendable {
    case unavailable
    case off
    case standby
    case idle
    case playing
    case paused

    static func resolve(entity: HomeAssistantEntity) -> FireTVPresentationState {
        guard entity.isAvailable else { return .unavailable }
        switch entity.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off": return .off
        case "standby": return .standby
        case "playing": return .playing
        case "paused": return .paused
        default: return .idle
        }
    }
}

enum FireTVPresentationPolicy {
    private static let blockedTokens = [
        "buellerdeviceservice",
        "com.amazon.device",
        "com.amazon.tv.launcher",
        "com.amazon.firelauncher",
        "com.amazon.settings",
        "com.android.settings",
        "com.android.systemui",
        "device.service",
        "deviceservice",
        "systemui",
        "packageinstaller",
        "ota"
    ]

    static func isSystemIdentity(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return blockedTokens.contains { normalized.contains($0) }
    }

    static func visibleForegroundApp(for entity: HomeAssistantEntity) -> String? {
        let state = FireTVPresentationState.resolve(entity: entity)
        guard state != .off, state != .standby, state != .unavailable else { return nil }

        let label = entity.attributes["foreground_app"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let package = entity.attributes["foreground_package"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let label, !label.isEmpty, !isSystemIdentity(label), !isSystemIdentity(package) {
            return label
        }
        if let package, !package.isEmpty, !isSystemIdentity(package) {
            return prettyPackageName(package)
        }
        return nil
    }

    static func shouldShowNowPlaying(for entity: HomeAssistantEntity) -> Bool {
        let state = FireTVPresentationState.resolve(entity: entity)
        guard state == .playing || state == .paused || state == .idle else { return false }
        let hasMedia = [entity.mediaTitle, entity.mediaArtist, entity.source]
            .contains { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !value.isEmpty && !isSystemIdentity(value)
            }
        return hasMedia || state == .playing || state == .paused
    }

    static func shouldShowTransport(for entity: HomeAssistantEntity) -> Bool {
        let state = FireTVPresentationState.resolve(entity: entity)
        return entity.companionSupportsPlayerControl && state != .off && state != .standby && state != .unavailable
    }

    static func isLaunchableUserApp(name: String, package: String) -> Bool {
        !isSystemIdentity(name) && !isSystemIdentity(package)
    }

    static func prettyPackageName(_ package: String) -> String {
        let tail = package.split(separator: ".").last.map(String.init) ?? package
        return tail.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }
}
