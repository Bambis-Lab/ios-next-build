import Foundation

/// BKI-02B mobile projection of the Factory BKI-02A capability contract.
/// This is UI state, not an authorization token. Live Factory must re-check
/// operation-scoped approvals independently for every mutating job.
struct MobileFactoryCapability: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let tool: String
    let backend: String
    let capability: String
    let available: Bool
    let enabled: Bool
    let authorized: Bool
    let requiresApproval: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id, tool, backend, capability, available, enabled, authorized, reason
        case requiresApproval = "requires_approval"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tool, forKey: .tool)
        try container.encode(backend, forKey: .backend)
        try container.encode(capability, forKey: .capability)
        try container.encode(available, forKey: .available)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(authorized, forKey: .authorized)
        try container.encode(requiresApproval, forKey: .requiresApproval)
        if let reason {
            try container.encode(reason, forKey: .reason)
        } else {
            try container.encodeNil(forKey: .reason)
        }
    }
}

struct MobileFactoryBackend: Codable, Equatable, Sendable {
    let id: String
    let online: Bool
}

struct MobileFactoryCapabilityManifest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let source: String
    let snapshotComplete: Bool
    let backend: MobileFactoryBackend
    let capabilities: [MobileFactoryCapability]

    enum CodingKeys: String, CodingKey {
        case source, backend, capabilities
        case schemaVersion = "schema_version"
        case snapshotComplete = "snapshot_complete"
    }

    /// The UI must not display an action as usable solely from a policy flag.
    func allowsDisplay(_ id: String) -> Bool {
        guard schemaVersion == "1.0", snapshotComplete, backend.online else { return false }
        return capabilities.first(where: { $0.id == id })?.authorized == true
    }
}

enum MobileFactoryCapabilityProjector {
    static let version = "1.0"
    static let catalog: [(tool: String, id: String, domain: String, approval: Bool)] = [
        ("factory_status", "factory.status", "READ_ONLY", false),
        ("factory_discover", "factory.discover", "READ_ONLY", false),
        ("factory_master_runner_v1_registration", "runner.registration", "READ_ONLY", false),
        ("factory_master_runner_v1_host_control_status", "runner.host_control_status", "READ_ONLY", false),
        ("factory_master_runner_v1_request_approval", "runner.request_approval", "HOST_CONTROL", true),
        ("factory_master_runner_v1_job_submit", "runner.job_submit", "HOST_CONTROL", true),
        ("factory_master_runner_v1_job_status", "runner.job_status", "HOST_CONTROL", true),
        ("factory_master_runner_v1_job_result", "runner.job_result", "HOST_CONTROL", true),
        ("factory_master_runner_v1_job_cancel", "runner.job_cancel", "HOST_CONTROL", true)
    ]

    /// Fail closed if the authenticated MCP session, status or tool list is missing.
    static func project(
        status: [String: Any]?,
        registeredTools: Set<String>,
        backendOnline: Bool,
        // Approval proof is not stored in app; only server-verifiable scopes
        // may be passed here by a future vetted operation flow.
        operationAuthorization: [String: Bool] = [:]
    ) -> MobileFactoryCapabilityManifest {
        let healthy = backendOnline && (status?["status"] as? String) == "ok"
        let flags = status?["capabilities"] as? [String: Any] ?? [:]
        let rows = catalog.map { row -> MobileFactoryCapability in
            let available = healthy && registeredTools.contains(row.tool)
            let policyEnabled = (flags[row.domain] as? Bool) == true
            let enabled = available && policyEnabled
            let authorized = enabled && (!row.approval || operationAuthorization[row.tool] == true)
            let reason: String?
            if !healthy {
                reason = "backend_offline"
            } else if !registeredTools.contains(row.tool) {
                reason = "tool_missing"
            } else if !policyEnabled {
                reason = "capability_disabled"
            } else if row.approval && !authorized {
                reason = "approval_required"
            } else {
                reason = nil
            }
            return .init(id: row.id, tool: row.tool, backend: "factory",
                         capability: row.domain, available: available,
                         enabled: enabled, authorized: authorized,
                         requiresApproval: row.approval, reason: reason)
        }
        return .init(schemaVersion: version,
                     source: "factory-mcp-observation",
                     snapshotComplete: healthy,
                     backend: .init(id: "factory", online: healthy),
                     capabilities: rows)
    }
}
