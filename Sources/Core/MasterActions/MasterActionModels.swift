import Foundation

enum MasterActionRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

enum MasterPrecheckState: String, Codable, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case block = "BLOCK"
}

enum MasterActionPhase: String, Codable, CaseIterable, Sendable {
    case intent
    case plan
    case precheck
    case approval
    case executing
    case verifying
    case rollback
    case completed
    case failed
}

struct MasterActionIntent: Codable, Equatable, Sendable {
    let actionID: String
    let targetID: String
    let capability: MasterCapability
    let parameters: [String: String]

    enum CodingKeys: String, CodingKey {
        case parameters
        case actionID = "action_id"
        case targetID = "target_id"
        case capability
    }
}

struct MasterActionPlanStep: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: String
}

struct MasterRollbackDescriptor: Codable, Equatable, Sendable {
    let supported: Bool
    let title: String?
    let reference: String?
}

struct MasterActionPlan: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let actionID: String
    let targetID: String
    let capability: MasterCapability
    let risk: MasterActionRisk
    let createdAt: Date
    let expiresAt: Date
    let nonce: String
    let planHash: String
    let authority: String
    let steps: [MasterActionPlanStep]
    let rollback: MasterRollbackDescriptor

    enum CodingKeys: String, CodingKey {
        case id, capability, risk, nonce, authority, steps, rollback
        case actionID = "action_id"
        case targetID = "target_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case planHash = "plan_hash"
    }

    func isExpired(now: Date = Date()) -> Bool { now >= expiresAt }
}

struct MasterPrecheckItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let state: MasterPrecheckState
    let detail: String
}

struct MasterActionPrecheck: Codable, Equatable, Sendable {
    let planID: String
    let state: MasterPrecheckState
    let checkedAt: Date
    let items: [MasterPrecheckItem]

    enum CodingKeys: String, CodingKey {
        case state, items
        case planID = "plan_id"
        case checkedAt = "checked_at"
    }

    var blocksExecution: Bool {
        state == .block || items.contains(where: { $0.state == .block })
    }
}

struct MasterActionApproval: Codable, Equatable, Sendable {
    let planID: String
    let approvedAt: Date
    let biometricConfirmed: Bool
    let confirmationText: String?

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case approvedAt = "approved_at"
        case biometricConfirmed = "biometric_confirmed"
        case confirmationText = "confirmation_text"
    }
}

struct MasterActionExecutionRequest: Codable, Equatable, Sendable {
    let planID: String
    let planHash: String
    let nonce: String
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case nonce
        case planID = "plan_id"
        case planHash = "plan_hash"
        case idempotencyKey = "idempotency_key"
    }
}

struct MasterActionReceipt: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let planID: String
    let operationID: String
    let phase: MasterActionPhase
    let startedAt: Date?
    let updatedAt: Date
    let detail: String?
    let rollback: MasterRollbackDescriptor?

    enum CodingKeys: String, CodingKey {
        case id, phase, detail, rollback
        case planID = "plan_id"
        case operationID = "operation_id"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

struct MasterActionVerification: Codable, Equatable, Sendable {
    let operationID: String
    let passed: Bool
    let verifiedAt: Date
    let detail: String

    enum CodingKeys: String, CodingKey {
        case passed, detail
        case operationID = "operation_id"
        case verifiedAt = "verified_at"
    }
}

struct MasterActionAuditRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let operationID: String
    let planID: String
    let actor: String
    let capability: MasterCapability
    let target: String
    let action: String
    let risk: MasterActionRisk
    let createdAt: Date
    let approvedAt: Date?
    let executedAt: Date?
    let verifiedAt: Date?
    let result: String
    let rollbackReference: String?
    let authority: String

    enum CodingKeys: String, CodingKey {
        case id, actor, capability, target, action, risk, result, authority
        case operationID = "operation_id"
        case planID = "plan_id"
        case createdAt = "created_at"
        case approvedAt = "approved_at"
        case executedAt = "executed_at"
        case verifiedAt = "verified_at"
        case rollbackReference = "rollback_reference"
    }
}

enum MasterActionPolicyDecision: Equatable, Sendable {
    case allow
    case deny(String)
}

enum MasterActionPolicy {
    static let implementedCapabilities: Set<MasterCapability> = [.sourceWrite, .runnerWrite, .runtimeWrite]
    static let alwaysLockedCapabilities: Set<MasterCapability> = [.simulatorWrite, .integrationWrite, .liveWrite, .hostControl]

    static func canApprove(
        plan: MasterActionPlan,
        precheck: MasterActionPrecheck,
        capabilityActive: Bool,
        authorityFresh: Bool,
        connected: Bool,
        now: Date = Date()
    ) -> MasterActionPolicyDecision {
        guard connected else { return .deny("Offline-Mutationen sind gesperrt") }
        guard implementedCapabilities.contains(plan.capability) else { return .deny("Capability wird von iOS Next nicht ausgeführt") }
        guard !alwaysLockedCapabilities.contains(plan.capability) else { return .deny("Capability bleibt gesperrt") }
        guard capabilityActive else { return .deny("Server hat die Capability nicht freigegeben") }
        guard authorityFresh else { return .deny("Authority ist nicht frisch verifiziert") }
        guard !plan.isExpired(now: now) else { return .deny("Plan ist abgelaufen") }
        guard precheck.planID == plan.id else { return .deny("Precheck gehört nicht zu diesem Plan") }
        guard !precheck.blocksExecution else { return .deny("Precheck blockiert die Ausführung") }
        return .allow
    }

    static func requiresBiometrics(for risk: MasterActionRisk) -> Bool {
        risk == .medium || risk == .high || risk == .critical
    }

    static func requiresTypedConfirmation(for risk: MasterActionRisk) -> Bool {
        risk == .high || risk == .critical
    }
}
