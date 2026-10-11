import Foundation

/// App-side contract registry only. Advertising a tool never grants permission.
/// Read calls require both this explicit allowlist and MCP tools/list discovery.
enum FactoryWorkspaceToolCatalog {
    static let legacyRead: [String] = [
        "factory_status", "factory_discover", "capabilities_get",
        "control_plane_status", "control_plane_registry_summary",
        "runner_status", "runner_system", "runner_memory", "runner_mounts",
        "runtime_status", "audit_status"
    ]

    static let workspaceRead: [String] = [
        "workspace_bootstrap_get", "workspace_overview_get", "source_health_list",
        "control_plane_registry_list", "repositories_list",
        "ci_runs_list", "ci_run_get", "ci_jobs_list", "ci_artifacts_list",
        "workflows_list", "runner_instances_list", "runner_jobs_list",
        "runner_job_get", "runner_job_logs_get",
        "runtime_operations_list", "runtime_operation_get", "events_history_list",
        "owner_session_get", "owner_projects_list", "owner_dispatch_jobs_list",
        "owner_tickets_list", "owner_ticket_get", "owner_backups_list",
        "owner_diagnostics_get", "owner_logs_list", "owner_systems_list",
        "owner_addons_list", "owner_releases_list", "owner_security_get",
        "owner_principals_list", "owner_audit_events_list",
        "owner_notifications_list", "chat_relay_health_get", "chat_relay_devices_list"
    ]

    // Future protocols only: no executable write routing is registered.
    static let proposedActions: [String] = [
        "actions_catalog_list", "operation_plan", "operation_precheck",
        "operation_approval_challenge", "operation_execute",
        "operation_receipt_get", "operation_verify", "operation_rollback"
    ]

    static let permittedReadNames = Set(legacyRead + workspaceRead)

    static func isPermittedRead(_ name: String) -> Bool {
        permittedReadNames.contains(name)
    }

    /// Never trust a capability list alone to authorize a mutation.
    static func mayExecute(_ name: String) -> Bool { false }
}

enum FactoryWorkspaceContractError: Error, LocalizedError, Equatable {
    case malformed
    case unsupportedSchema
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .malformed: "Die Factory hat kein gültiges JSON-Dokument geliefert."
        case .unsupportedSchema: "Die Factory-Schnittstellenversion wird noch nicht unterstützt."
        case .invalidEnvelope: "Die Factory-Antwort hat keine überprüfbare Herkunft oder Statusangabe."
        }
    }
}

/// Strictly typed metadata; arbitrary server fields are not directly rendered.
/// Individual details remain accessible from their domain's authorized adapter.
struct FactoryWorkspaceEnvelope: Equatable {
    let schemaVersion: String
    let source: String
    let status: String
    let observedAt: Date?
    let revision: String?
    let stale: Bool
    let capabilityNames: [String: Bool]

    static func decode(_ text: String) throws -> Self {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let root = object as? [String: Any] else {
            throw FactoryWorkspaceContractError.malformed
        }
        guard let version = root["schema_version"] as? String else {
            throw FactoryWorkspaceContractError.invalidEnvelope
        }
        guard version == "factory.workspace.v1" else {
            throw FactoryWorkspaceContractError.unsupportedSchema
        }
        guard let source = root["source"] as? String, !source.isEmpty,
              let status = root["status"] as? String, !status.isEmpty else {
            throw FactoryWorkspaceContractError.invalidEnvelope
        }
        let freshness = root["freshness"] as? [String: Any]
        let date = (root["observed_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let capabilities = (root["capabilities"] as? [String: Any] ?? [:]).compactMapValues { $0 as? Bool }
        return Self(
            schemaVersion: version,
            source: source,
            status: status,
            observedAt: date,
            revision: root["revision"] as? String,
            stale: freshness?["stale"] as? Bool ?? true,
            capabilityNames: capabilities
        )
    }
}

struct FactoryWorkspaceSourceState: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let source: String
    let observedAt: Date?
    let isStale: Bool
}
