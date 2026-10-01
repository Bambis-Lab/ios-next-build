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
    let diskPercent: Double?
    let activeOperations: Int
    let registeredRunners: Int
    let idleRunners: Int
    let busyRunners: Int
    let activeJobs: [RunnerJobStatus]
    let updatedAt: Date?
    let source: MasterRuntimeSource

    init(status: RunnerStatus?, liveState: CommanderLiveViewState) {
        let legacySnapshot = liveState.effectiveSnapshot ?? status?.commander
        let hasSnapshot = legacySnapshot != nil || status != nil

        switch liveState.connection {
        case .degraded, .reconnecting:
            availability = hasSnapshot ? .degraded : .unavailable
        case .disconnected:
            availability = hasSnapshot ? .degraded : .unavailable
        case .live, .syncing, .connecting, .unconfigured:
            availability = hasSnapshot ? .ready : .unavailable
        }

        version = nil
        uptimeSeconds = max(0, Int((legacySnapshot?.uptimeSeconds ?? status?.uptimeSeconds ?? 0).rounded(.down)))
        cpuPercent = min(max(legacySnapshot?.cpuPercent ?? status?.cpuPercent ?? 0, 0), 100)
        memoryPercent = min(max(legacySnapshot?.memoryPercent ?? status?.memoryPercent ?? 0, 0), 100)
        if let disk = status?.diskPercent {
            diskPercent = min(max(disk, 0), 100)
        } else {
            diskPercent = nil
        }
        activeOperations = max(0, legacySnapshot?.activeCount ?? status?.activeJobs?.count ?? 0)
        registeredRunners = max(0, status?.registeredRunners ?? 0)
        idleRunners = max(0, status?.idleRunners ?? 0)
        busyRunners = max(0, status?.busyRunners ?? 0)
        activeJobs = status?.activeJobs ?? []
        updatedAt = liveState.lastEventAt ?? status?.lastHealthCheck ?? legacySnapshot?.lastActivity
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
