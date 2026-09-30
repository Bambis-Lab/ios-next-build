import Foundation

struct AdminCapabilitiesResponse: Codable, Equatable, Sendable {
    let apiVersion: Int
    let modules: [String]
    let capabilities: [String]
    let actions: [AdminRemoteAction]

    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case modules
        case capabilities
        case actions
    }
}

struct AdminRemoteAction: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let category: String
    let risk: String
    let available: Bool
    let requiresBiometrics: Bool
    let requiresConfirmation: Bool
    let requiresBreakGlass: Bool
    let parameters: [AdminActionParameterV2]?

    enum CodingKeys: String, CodingKey {
        case id, title, category, risk, available
        case requiresBiometrics = "requires_biometrics"
        case requiresConfirmation = "requires_confirmation"
        case requiresBreakGlass = "requires_break_glass"
        case parameters
    }
}

struct AdminActionParameterV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let required: Bool
}

enum AdminMetricValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        throw DecodingError.typeMismatch(
            AdminMetricValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported metric value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayValue: String {
        switch self {
        case let .string(value): value
        case let .integer(value): String(value)
        case let .double(value): value.formatted(.number.precision(.fractionLength(0...1)))
        case let .boolean(value): value ? "Ja" : "Nein"
        case .null: "—"
        }
    }
}

struct AdminSystemStatusV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: String
    let configured: Bool
    let healthy: Bool
    let state: String
    let version: String?
    let detail: String?
    let metrics: [String: AdminMetricValue]
    let dependencies: [String]
}

struct AdminAddonInventoryStatusV2: Codable, Equatable, Sendable {
    let state: String
    let detail: String?
}

struct AdminBackupRecordV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let sizeBytes: Int64
    let sha256: String
    let kind: String
    let verified: Bool
    let restoreCapable: Bool
    let verifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, sha256, kind, verified
        case createdAt = "created_at"
        case sizeBytes = "size_bytes"
        case restoreCapable = "restore_capable"
        case verifiedAt = "verified_at"
    }
}

struct AdminDiagnosticResponseV2: Codable, Equatable, Sendable {
    let healthy: Bool
    let checks: [AdminDiagnosticCheckV2]
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case healthy, checks
        case generatedAt = "generated_at"
    }
}

struct AdminDiagnosticCheckV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let ok: Bool
    let detail: String
    let severity: String
}

struct AdminLogEntryV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let level: String
    let source: String
    let message: String
}

struct AdminWorkflowSummaryV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let risk: String
    let available: Bool
    let steps: [String]
}

struct AdminWorkflowReceiptV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let workflowID: String
    let state: String
    let steps: [AdminWorkflowStepV2]
    let rollbackAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id, state, steps
        case workflowID = "workflow_id"
        case rollbackAvailable = "rollback_available"
    }
}

struct AdminWorkflowStepV2: Codable, Equatable, Sendable {
    let step: String
    let state: String
    let resource: String?
    let result: Bool?
}

struct AdminSecuritySummaryV2: Codable, Equatable, Sendable {
    let deviceBindingAvailable: Bool
    let deviceEnrollmentOpen: Bool
    let trustedDevices: Int
    let activeSessions: Int
    let activeBreakGlassSessions: Int
    let controlEnabled: Bool
    let supervisorMutationsEnabled: Bool
    let freeShellAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case deviceBindingAvailable = "device_binding_available"
        case deviceEnrollmentOpen = "device_enrollment_open"
        case trustedDevices = "trusted_devices"
        case activeSessions = "active_sessions"
        case activeBreakGlassSessions = "active_break_glass_sessions"
        case controlEnabled = "control_enabled"
        case supervisorMutationsEnabled = "supervisor_mutations_enabled"
        case freeShellAvailable = "free_shell_available"
    }
}

struct AdminCredentialMetadataV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let purpose: String
    let scope: String
    let configured: Bool
    let lastRotatedAt: Date?
    let risk: String

    enum CodingKeys: String, CodingKey {
        case id, name, purpose, scope, configured, risk
        case lastRotatedAt = "last_rotated_at"
    }
}

struct AdminUserSummaryV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id, role
        case displayName = "display_name"
    }
}

struct AdminDeviceSummaryV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let publicKeyFingerprint: String
    let createdAt: Date
    let lastSeen: Date
    let trusted: Bool

    enum CodingKeys: String, CodingKey {
        case id, trusted
        case publicKeyFingerprint = "public_key_fingerprint"
        case createdAt = "created_at"
        case lastSeen = "last_seen"
    }
}

struct AdminSessionSummaryV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let deviceID: String
    let createdAt: Date
    let expiresAt: Date
    let lastSeen: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case lastSeen = "last_seen"
    }
}

struct AdminReleaseItemV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let installedVersion: String
    let availableVersion: String?
    let updateAvailable: Bool
    let testsPassing: Bool?
    let rollbackAvailable: Bool
    let changelog: String?

    enum CodingKeys: String, CodingKey {
        case id, title, changelog
        case installedVersion = "installed_version"
        case availableVersion = "available_version"
        case updateAvailable = "update_available"
        case testsPassing = "tests_passing"
        case rollbackAvailable = "rollback_available"
    }
}

struct AdminEventFeedV2: Codable, Equatable, Sendable {
    let events: [AdminEventV2]
    let lastSequence: Int

    enum CodingKeys: String, CodingKey {
        case events
        case lastSequence = "last_sequence"
    }
}

struct AdminEventV2: Codable, Equatable, Identifiable, Sendable {
    var id: Int { sequence }
    let sequence: Int
    let timestamp: Date
    let type: String
    let resource: String
}

struct AdminDeviceChallengeV2: Codable, Equatable, Sendable {
    let challengeID: String
    let challenge: String
    let purpose: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case challenge, purpose
        case challengeID = "challenge_id"
        case expiresAt = "expires_at"
    }
}

struct AdminDeviceSessionV2: Codable, Equatable, Sendable {
    let sessionID: String
    let deviceSession: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case deviceSession = "device_session"
        case expiresAt = "expires_at"
    }
}

struct AdminBreakGlassSessionV2: Codable, Equatable, Sendable {
    let breakGlassSessionID: String
    let breakGlassSession: String
    let expiresAt: Date
    let allowedActions: [String]

    enum CodingKeys: String, CodingKey {
        case breakGlassSessionID = "break_glass_session_id"
        case breakGlassSession = "break_glass_session"
        case expiresAt = "expires_at"
        case allowedActions = "allowed_actions"
    }
}

struct AdminDeviceEnrollRequestV2: Encodable {
    let deviceID: String
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case publicKey = "public_key"
    }
}

struct AdminDeviceChallengeRequestV2: Encodable {
    let deviceID: String
    let purpose: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case purpose
    }
}

struct AdminDeviceVerifyRequestV2: Encodable {
    let deviceID: String
    let challengeID: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case signature
        case deviceID = "device_id"
        case challengeID = "challenge_id"
    }
}

struct AdminBreakGlassRequestV2: Encodable {
    let deviceID: String
    let challengeID: String
    let signature: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reason, signature
        case deviceID = "device_id"
        case challengeID = "challenge_id"
    }
}

struct AdminDeviceEnrollmentV2: Codable, Equatable, Sendable {
    let id: String
    let publicKeyFingerprint: String
    let trusted: Bool

    enum CodingKeys: String, CodingKey {
        case id, trusted
        case publicKeyFingerprint = "public_key_fingerprint"
    }
}

struct AdminChatStatusV2: Codable, Equatable, Sendable {
    let chatQueuedChunks: Int
    let chatQueuedBytes: Int
    let chatDeviceQueues: Int
    let registeredPrincipals: Int
    let ownerRateLimitPerMinute: Int
    let chatRateLimitPerMinute: Int
    let ephemeralTTLSeconds: Int
    let messageContentVisibleToOwner: Bool

    enum CodingKeys: String, CodingKey {
        case chatQueuedChunks = "chat_queued_chunks"
        case chatQueuedBytes = "chat_queued_bytes"
        case chatDeviceQueues = "chat_device_queues"
        case registeredPrincipals = "registered_principals"
        case ownerRateLimitPerMinute = "owner_rate_limit_per_minute"
        case chatRateLimitPerMinute = "chat_rate_limit_per_minute"
        case ephemeralTTLSeconds = "ephemeral_ttl_seconds"
        case messageContentVisibleToOwner = "message_content_visible_to_owner"
    }
}

struct AdminChatDeviceV2: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(userID)-\(deviceID)" }
    let userID: String
    let deviceID: String
    let agreementKeyFingerprint: String
    let signingKeyFingerprint: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case agreementKeyFingerprint = "agreement_key_fingerprint"
        case signingKeyFingerprint = "signing_key_fingerprint"
        case updatedAt = "updated_at"
    }
}

struct AdminCIStatusV2: Codable, Equatable, Sendable {
    let status: String?
    let conclusion: String?
    let headSHA: String?
    let workflow: String?
    let updatedAt: Date?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, conclusion, workflow, error
        case headSHA = "head_sha"
        case updatedAt = "updated_at"
    }
}

struct AdminProjectStatusV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let repository: String?
    let dispatchCount: Int
    let activeJobs: Int
    let latestDispatchState: String?
    let ci: AdminCIStatusV2?

    enum CodingKeys: String, CodingKey {
        case id, title, repository, ci
        case dispatchCount = "dispatch_count"
        case activeJobs = "active_jobs"
        case latestDispatchState = "latest_dispatch_state"
    }
}

struct AdminJobStatusV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let ticketID: String
    let projectID: String
    let state: String
    let approvedBy: String
    let approvedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, state
        case ticketID = "ticket_id"
        case projectID = "project_id"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
    }
}

struct AdminAddonStatusV2: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: String
    let version: String?
    let versionLatest: String?
    let updateAvailable: Bool
    let healthy: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, state, version, healthy
        case versionLatest = "version_latest"
        case updateAvailable = "update_available"
    }
}
