import Foundation

enum CommanderRuntimeState: String, Codable, Equatable, Sendable {
    case active
    case idle
    case degraded
    case offline
    case unknown
}

enum CommanderActivityState: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case uncertain
}

enum CommanderLiveConnectionState: String, Equatable, Sendable {
    case unconfigured
    case disconnected
    case connecting
    case syncing
    case live
    case reconnecting
    case degraded
}

struct CommanderActivity: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var tool: String
    var startedAt: Date
    var state: CommanderActivityState
    var durationMS: Int?
    var completedAt: Date?
    var uncertain: Bool

    enum CodingKeys: String, CodingKey {
        case id, tool, state, uncertain
        case startedAt = "started_at"
        case durationMS = "duration_ms"
        case completedAt = "completed_at"
    }
}

struct CommanderWorkContext: Codable, Equatable, Sendable {
    var repository: String?
    var branch: String?
    var workflow: String?
    var job: String?
    var phase: String?
    var step: String?
    var runner: String?
    var lastEvent: String?
    var nextExpectedEvent: String?
    var elapsedSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case repository, branch, workflow, job, phase, step, runner
        case lastEvent = "last_event"
        case nextExpectedEvent = "next_expected_event"
        case elapsedSeconds = "elapsed_seconds"
    }
}

struct CommanderSnapshot: Codable, Equatable, Sendable {
    var state: CommanderRuntimeState
    var online: Bool?
    var version: String?
    var uptimeSeconds: Double?
    var cpuPercent: Double?
    var memoryPercent: Double?
    var activeSessions: Int?
    var activeSearches: Int?
    var activeCount: Int
    var lastActivity: Date?
    var activities: [CommanderActivity]
    var statusConfidence: String
    var workContext: CommanderWorkContext?

    enum CodingKeys: String, CodingKey {
        case state, online, version, activities
        case uptimeSeconds = "uptime_seconds"
        case cpuPercent = "cpu_percent"
        case memoryPercent = "memory_percent"
        case activeSessions = "active_sessions"
        case activeSearches = "active_searches"
        case activeCount = "active_count"
        case lastActivity = "last_activity"
        case statusConfidence = "status_confidence"
        case workContext = "work_context"
    }

    init(
        state: CommanderRuntimeState = .unknown,
        online: Bool? = nil,
        version: String? = nil,
        uptimeSeconds: Double? = nil,
        cpuPercent: Double? = nil,
        memoryPercent: Double? = nil,
        activeSessions: Int? = nil,
        activeSearches: Int? = nil,
        activeCount: Int = 0,
        lastActivity: Date? = nil,
        activities: [CommanderActivity] = [],
        statusConfidence: String = "unknown",
        workContext: CommanderWorkContext? = nil
    ) {
        self.state = state
        self.online = online
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.activeSessions = activeSessions.map { max(0, $0) }
        self.activeSearches = activeSearches.map { max(0, $0) }
        self.activeCount = max(0, activeCount)
        self.lastActivity = lastActivity
        self.activities = activities
        self.statusConfidence = statusConfidence
        self.workContext = workContext
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        state = try values.decodeIfPresent(CommanderRuntimeState.self, forKey: .state) ?? .unknown
        online = try values.decodeIfPresent(Bool.self, forKey: .online)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        uptimeSeconds = try values.decodeIfPresent(Double.self, forKey: .uptimeSeconds)
        cpuPercent = try values.decodeIfPresent(Double.self, forKey: .cpuPercent)
        memoryPercent = try values.decodeIfPresent(Double.self, forKey: .memoryPercent)
        activeSessions = try values.decodeIfPresent(Int.self, forKey: .activeSessions).map { max(0, $0) }
        activeSearches = try values.decodeIfPresent(Int.self, forKey: .activeSearches).map { max(0, $0) }
        activeCount = max(0, try values.decodeIfPresent(Int.self, forKey: .activeCount) ?? 0)
        lastActivity = try values.decodeIfPresent(Date.self, forKey: .lastActivity)
        activities = try values.decodeIfPresent([CommanderActivity].self, forKey: .activities) ?? []
        statusConfidence = try values.decodeIfPresent(String.self, forKey: .statusConfidence) ?? "unknown"
        workContext = try values.decodeIfPresent(CommanderWorkContext.self, forKey: .workContext)
    }
}

struct CommanderLivePayload: Codable, Equatable, Sendable {
    let snapshot: CommanderSnapshot?
    let activity: CommanderActivity?
    let activeSessions: Int?
    let activeSearches: Int?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case snapshot, activity, reason
        case activeSessions = "active_sessions"
        case activeSearches = "active_searches"
    }
}

struct RunnerLiveEnvelope: Codable, Equatable, Sendable {
    let schema: Int
    let seq: Int64
    let type: String
    let timestamp: Date
    let payload: CommanderLivePayload
}

enum CommanderLiveApplyResult: Equatable, Sendable {
    case applied
    case duplicate
    case unsupported
    case resyncRequired
}

struct CommanderLiveViewState: Equatable, Sendable {
    static let supportedSchema = 1

    var snapshot: CommanderSnapshot?
    var activities: [String: CommanderActivity] = [:]
    var lastSequence: Int64?
    var connection: CommanderLiveConnectionState = .disconnected
    var needsFullResync = false
    var lastEventAt: Date?

    var effectiveSnapshot: CommanderSnapshot? {
        guard var value = snapshot else { return nil }
        value.activities = activities.values.sorted { lhs, rhs in
            if lhs.startedAt == rhs.startedAt { return lhs.id < rhs.id }
            return lhs.startedAt < rhs.startedAt
        }
        value.activeCount = value.activities.count
        if value.online == false {
            value.state = .offline
        } else if !value.activities.isEmpty {
            value.state = .active
        } else if value.state == .active {
            value.state = .idle
        }
        return value
    }

    mutating func seedSnapshot(_ value: CommanderSnapshot) {
        snapshot = value
        activities = Dictionary(uniqueKeysWithValues: value.activities.map { ($0.id, $0) })
    }

    mutating func resetForConfigurationRemoval() {
        snapshot = nil
        activities.removeAll()
        lastSequence = nil
        connection = .disconnected
        needsFullResync = false
        lastEventAt = nil
    }

    mutating func apply(_ event: RunnerLiveEnvelope) -> CommanderLiveApplyResult {
        guard event.schema == Self.supportedSchema else {
            connection = .degraded
            needsFullResync = true
            return .resyncRequired
        }

        if event.type == "commander.snapshot" {
            guard let incoming = event.payload.snapshot else {
                connection = .degraded
                needsFullResync = true
                return .resyncRequired
            }
            seedSnapshot(incoming)
            lastSequence = event.seq
            lastEventAt = event.timestamp
            needsFullResync = false
            connection = .live
            return .applied
        }

        if let previous = lastSequence {
            if event.seq <= previous { return .duplicate }
            guard event.seq == previous + 1 else {
                connection = .degraded
                needsFullResync = true
                return .resyncRequired
            }
        } else if event.seq != 1 {
            connection = .degraded
            needsFullResync = true
            return .resyncRequired
        }

        lastSequence = event.seq
        lastEventAt = event.timestamp

        switch event.type {
        case "commander.activity.started":
            guard let activity = event.payload.activity else { return markMalformed() }
            activities[activity.id] = activity
            ensureSnapshot()
            snapshot?.online = true
            snapshot?.state = .active
            snapshot?.lastActivity = activity.startedAt
            updateActivityProjection()
            return .applied

        case "commander.activity.completed", "commander.activity.failed":
            guard let activity = event.payload.activity else { return markMalformed() }
            activities.removeValue(forKey: activity.id)
            ensureSnapshot()
            snapshot?.lastActivity = activity.completedAt ?? event.timestamp
            if activity.uncertain || activity.state == .uncertain {
                snapshot?.statusConfidence = "degraded"
            }
            updateActivityProjection()
            return .applied

        case "commander.status":
            guard let incoming = event.payload.snapshot else { return markMalformed() }
            seedSnapshot(incoming)
            return .applied

        case "commander.sessions.changed":
            guard let count = event.payload.activeSessions, count >= 0 else { return markMalformed() }
            ensureSnapshot()
            snapshot?.activeSessions = count
            return .applied

        case "commander.searches.changed":
            guard let count = event.payload.activeSearches, count >= 0 else { return markMalformed() }
            ensureSnapshot()
            snapshot?.activeSearches = count
            return .applied

        case "commander.resync.required":
            connection = .degraded
            needsFullResync = true
            return .resyncRequired

        case "heartbeat":
            return .applied

        default:
            return .unsupported
        }
    }

    private mutating func ensureSnapshot() {
        if snapshot == nil { snapshot = CommanderSnapshot() }
    }

    private mutating func updateActivityProjection() {
        guard snapshot != nil else { return }
        snapshot?.activities = activities.values.sorted { $0.startedAt < $1.startedAt }
        snapshot?.activeCount = activities.count
        if snapshot?.online == false {
            snapshot?.state = .offline
        } else {
            snapshot?.state = activities.isEmpty ? .idle : .active
        }
    }

    private mutating func markMalformed() -> CommanderLiveApplyResult {
        connection = .degraded
        needsFullResync = true
        return .resyncRequired
    }
}

enum CommanderLiveCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        return decoder
    }
}
