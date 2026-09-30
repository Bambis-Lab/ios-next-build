import Foundation

enum MasterRuntimeAvailability: Equatable, Sendable {
    case unavailable
    case ready
    case degraded
}

enum MasterRuntimeSource: Equatable, Sendable {
    case native
    case compatibilityAdapter
}

struct MasterRuntimeSnapshot: Equatable, Sendable {
    let availability: MasterRuntimeAvailability
    let version: String?
    let uptimeSeconds: Int
    let cpuPercent: Double
    let memoryPercent: Double
    let activeOperations: Int
    let updatedAt: Date?
    let source: MasterRuntimeSource

    init(status: RunnerStatus?, liveState: CommanderLiveViewState) {
        let legacySnapshot = liveState.effectiveSnapshot ?? status?.commander
        let hasSnapshot = legacySnapshot != nil

        switch liveState.connection {
        case .degraded, .reconnecting:
            availability = hasSnapshot ? .degraded : .unavailable
        case .live, .syncing, .connecting, .disconnected, .unconfigured:
            availability = hasSnapshot ? .ready : .unavailable
        }

        // A Commander version is an implementation detail of the compatibility adapter,
        // not the version of the Master Runtime itself.
        version = nil
        uptimeSeconds = max(0, Int((legacySnapshot?.uptimeSeconds ?? 0).rounded(.down)))
        cpuPercent = min(max(legacySnapshot?.cpuPercent ?? 0, 0), 100)
        memoryPercent = min(max(legacySnapshot?.memoryPercent ?? 0, 0), 100)
        activeOperations = max(0, legacySnapshot?.activeCount ?? 0)
        updatedAt = liveState.lastEventAt ?? legacySnapshot?.lastActivity
        source = .compatibilityAdapter
    }
}

@MainActor
extension RunnerControlModel {
    var masterRuntimeSnapshot: MasterRuntimeSnapshot {
        let status: RunnerStatus?

        switch state {
        case let .ready(value):
            status = value
        case .notConfigured, .loading, .failed:
            status = nil
        }

        return MasterRuntimeSnapshot(
            status: status,
            liveState: commanderLiveState
        )
    }
}
