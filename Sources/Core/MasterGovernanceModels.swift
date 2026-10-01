import Foundation

enum MasterCapability: String, CaseIterable, Codable, Sendable, Identifiable {
    case readOnly = "READ_ONLY"
    case sourceWrite = "SOURCE_WRITE"
    case runnerWrite = "RUNNER_WRITE"
    case simulatorWrite = "SIMULATOR_WRITE"
    case integrationWrite = "INTEGRATION_WRITE"
    case runtimeWrite = "RUNTIME_WRITE"
    case liveWrite = "LIVE_WRITE"
    case hostControl = "HOST_CONTROL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly: "Lesen"
        case .sourceWrite: "Source schreiben"
        case .runnerWrite: "Runner schreiben"
        case .simulatorWrite: "Simulator schreiben"
        case .integrationWrite: "Integrationen schreiben"
        case .runtimeWrite: "Runtime schreiben"
        case .liveWrite: "Live-System schreiben"
        case .hostControl: "Host-Steuerung"
        }
    }
}

enum MasterCapabilityAvailability: String, Equatable, Sendable {
    case active
    case locked
    case unavailable

    var title: String {
        switch self {
        case .active: "Aktiv"
        case .locked: "Gesperrt"
        case .unavailable: "Nicht verfügbar"
        }
    }
}

struct MasterCapabilityStatus: Identifiable, Equatable, Sendable {
    let capability: MasterCapability
    let availability: MasterCapabilityAvailability
    let detail: String

    var id: String { capability.id }
}

/// iOS Next 1.2 intentionally consumes Master data read-only. Higher-risk capabilities
/// are represented in the UI so future plan/precheck/verify flows can be added without
/// changing navigation, but they remain locked in this release.
struct MasterGovernanceSnapshot: Equatable, Sendable {
    let authority: String
    let observedAt: Date?
    let capabilities: [MasterCapabilityStatus]
    let precheckSupported: Bool
    let verifySupported: Bool
    let rollbackSupported: Bool

    static func sourceOnly(observedAt: Date? = nil, authority: String = "Bambis Master") -> Self {
        let statuses = MasterCapability.allCases.map { capability in
            if capability == .readOnly {
                return MasterCapabilityStatus(
                    capability: capability,
                    availability: .active,
                    detail: "Diagnose, Runtime, CI und sanitisierte Telemetrie"
                )
            }
            return MasterCapabilityStatus(
                capability: capability,
                availability: .locked,
                detail: "In iOS Next 1.2 nicht ausführbar"
            )
        }
        return Self(
            authority: authority,
            observedAt: observedAt,
            capabilities: statuses,
            precheckSupported: false,
            verifySupported: false,
            rollbackSupported: false
        )
    }

    var readOnlyStatus: MasterCapabilityStatus {
        capabilities.first { $0.capability == .readOnly }
            ?? MasterCapabilityStatus(capability: .readOnly, availability: .unavailable, detail: "Unbekannt")
    }
}
