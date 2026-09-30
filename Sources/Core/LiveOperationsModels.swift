import Foundation

enum LiveOperationSourceKind: String, Codable, CaseIterable, Sendable {
    case mcp
    case sentinelX = "sentinelx"

    var title: String {
        switch self {
        case .mcp: "MCP"
        case .sentinelX: "SentinelX"
        }
    }
}

enum LiveOperationState: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
    case uncertain
}

enum LiveOperationsConnectionState: String, Equatable, Sendable {
    case unconfigured
    case connecting
    case syncing
    case live
    case reconnecting
    case degraded
    case offline
}

struct LiveOperation: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let source: LiveOperationSourceKind
    let kind: String
    let title: String
    let state: LiveOperationState
    let startedAt: Date
    let updatedAt: Date
    let subtitle: String?
    let host: String?
    let repository: String?
    let workspace: String?
    let completedAt: Date?
    let durationMS: Int?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, source, kind, title, state, subtitle, host, repository, workspace, metadata
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case durationMS = "duration_ms"
    }
}

struct LiveOperationsSnapshot: Codable, Equatable, Sendable {
    let source: LiveOperationSourceKind
    let online: Bool
    let lastSeq: Int64
    let activeOperations: [LiveOperation]
    let recentOperations: [LiveOperation]
    let metrics: [String: LiveMetricValue]
    let sourceMetadata: [String: LiveMetricValue]

    enum CodingKeys: String, CodingKey {
        case source, online, metrics
        case lastSeq = "last_seq"
        case activeOperations = "active_operations"
        case recentOperations = "recent_operations"
        case sourceMetadata = "source_metadata"
    }
}

enum LiveMetricValue: Codable, Equatable, Sendable {
    case string(String)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }

    var displayText: String {
        switch self {
        case let .string(value): value
        case let .double(value): String(format: "%.1f", value)
        case let .bool(value): value ? "Ja" : "Nein"
        }
    }
}

struct LiveOperationsEventPayload: Codable, Equatable, Sendable {
    let operation: LiveOperation?
    let snapshot: LiveOperationsSnapshot?
    let online: Bool?
    let metrics: [String: LiveMetricValue]?
    let sourceMetadata: [String: LiveMetricValue]?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case operation, snapshot, online, metrics, reason
        case sourceMetadata = "source_metadata"
    }
}

struct LiveOperationsEnvelope: Codable, Equatable, Sendable {
    let schema: Int
    let source: LiveOperationSourceKind
    let seq: Int64
    let type: String
    let timestamp: Date
    let payload: LiveOperationsEventPayload
}

enum LiveOperationsApplyResult: Equatable, Sendable {
    case applied
    case duplicate
    case unsupported
    case resyncRequired
}

struct LiveOperationsSourceState: Equatable, Sendable {
    static let supportedSchema = 1

    let source: LiveOperationSourceKind
    var online = false
    var lastSequence: Int64?
    var activeOperations: [String: LiveOperation] = [:]
    var recentOperations: [LiveOperation] = []
    var metrics: [String: LiveMetricValue] = [:]
    var sourceMetadata: [String: LiveMetricValue] = [:]
    var lastEventAt: Date?
    var needsFullResync = false

    mutating func seed(_ snapshot: LiveOperationsSnapshot) {
        online = snapshot.online
        lastSequence = snapshot.lastSeq
        activeOperations = Dictionary(uniqueKeysWithValues: snapshot.activeOperations.map { ($0.id, $0) })
        recentOperations = Array(snapshot.recentOperations.prefix(50))
        metrics = snapshot.metrics
        sourceMetadata = snapshot.sourceMetadata
        needsFullResync = false
    }

    mutating func apply(_ event: LiveOperationsEnvelope) -> LiveOperationsApplyResult {
        guard event.schema == Self.supportedSchema, event.source == source else {
            needsFullResync = true
            return .resyncRequired
        }

        switch event.type {
        case "source.snapshot":
            guard let snapshot = event.payload.snapshot, snapshot.source == source else {
                needsFullResync = true
                return .resyncRequired
            }
            seed(snapshot)
            lastEventAt = event.timestamp
            return .applied
        default:
            break
        }

        if let previous = lastSequence {
            if event.seq <= previous { return .duplicate }
            guard event.seq == previous + 1 else {
                needsFullResync = true
                return .resyncRequired
            }
        } else if event.seq != 1 {
            needsFullResync = true
            return .resyncRequired
        }

        lastSequence = event.seq
        lastEventAt = event.timestamp

        switch event.type {
        case "source.status":
            if let online = event.payload.online { self.online = online }
            return .applied
        case "metrics.updated":
            online = true
            if let incoming = event.payload.metrics {
                for (key, value) in incoming { metrics[key] = value }
            }
            if let incoming = event.payload.sourceMetadata {
                for (key, value) in incoming { sourceMetadata[key] = value }
            }
            return .applied
        case "operation.started", "operation.updated":
            online = true
            guard let operation = event.payload.operation else { return malformed() }
            activeOperations[operation.id] = operation
            return .applied
        case "operation.completed", "operation.failed":
            online = true
            guard let operation = event.payload.operation else { return malformed() }
            activeOperations.removeValue(forKey: operation.id)
            recentOperations.insert(operation, at: 0)
            if recentOperations.count > 50 { recentOperations.removeLast(recentOperations.count - 50) }
            return .applied
        case "service.changed", "heartbeat":
            online = true
            return .applied
        case "resync.required":
            needsFullResync = true
            return .resyncRequired
        default:
            return .unsupported
        }
    }

    private mutating func malformed() -> LiveOperationsApplyResult {
        needsFullResync = true
        return .resyncRequired
    }
}

enum LiveOperationsCoding {
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
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }
}
