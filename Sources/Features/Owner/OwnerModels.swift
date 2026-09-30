import Foundation
import SwiftUI

enum OwnerSectionRoute: String, CaseIterable, Identifiable {
    case systems
    case operations
    case projects
    case security
    case communication
    case releases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systems: "Systeme"
        case .operations: "Betrieb"
        case .projects: "Projekte"
        case .security: "Sicherheit"
        case .communication: "Kommunikation"
        case .releases: "Releases"
        }
    }

    var subtitle: String {
        switch self {
        case .systems: "Dienste und Infrastruktur"
        case .operations: "Backups, Diagnose und Wartung"
        case .projects: "Tickets, Projekte und Dispatch"
        case .security: "Audit und künftige Sicherheitsfunktionen"
        case .communication: "Relay- und Queue-Telemetrie"
        case .releases: "Installierte Versionen und Update-Bereitschaft"
        }
    }

    var symbol: String {
        switch self {
        case .systems: "server.rack"
        case .operations: "wrench.and.screwdriver.fill"
        case .projects: "folder.fill"
        case .security: "lock.shield.fill"
        case .communication: "bubble.left.and.bubble.right.fill"
        case .releases: "shippingbox.fill"
        }
    }
}

enum OwnerCapability: String, CaseIterable, Hashable {
    case backendStatus
    case backups
    case logs
    case diagnostics
    case workflows
    case projects
    case tickets
    case dispatch
    case audit
    case credentials
    case users
    case devices
    case chatRelay
    case releaseInventory
    case notifications
}

struct OwnerCapabilityRegistry: Equatable {
    let supported: Set<OwnerCapability>

    func supports(_ capability: OwnerCapability) -> Bool {
        supported.contains(capability)
    }

    static let currentAdminAPI = OwnerCapabilityRegistry(supported: [
        .backendStatus,
        .backups,
        .logs,
        .diagnostics,
        .projects,
        .tickets,
        .dispatch,
        .audit,
        .chatRelay
    ])

    static func discovered(from response: AdminCapabilitiesResponse) -> OwnerCapabilityRegistry {
        let capabilities = Set(response.capabilities)
        var values: Set<OwnerCapability> = []
        if capabilities.contains("backend.status.read") { values.insert(.backendStatus) }
        if capabilities.contains("backups.read") { values.insert(.backups) }
        if capabilities.contains("logs.read") { values.insert(.logs) }
        if capabilities.contains("diagnostics.read") { values.insert(.diagnostics) }
        if capabilities.contains("workflows.read") { values.insert(.workflows) }
        if capabilities.contains("projects.read") { values.insert(.projects) }
        if capabilities.contains("tickets.read") { values.insert(.tickets) }
        if capabilities.contains("dispatch.read") { values.insert(.dispatch) }
        if capabilities.contains("audit.read") { values.insert(.audit) }
        if capabilities.contains("credentials.metadata.read") { values.insert(.credentials) }
        if capabilities.contains("users.read") { values.insert(.users) }
        if capabilities.contains("devices.read") || capabilities.contains("sessions.read") { values.insert(.devices) }
        if capabilities.contains("chat.relay.read") { values.insert(.chatRelay) }
        if capabilities.contains("releases.read") { values.insert(.releaseInventory) }
        if capabilities.contains("events.read") { values.insert(.notifications) }
        return OwnerCapabilityRegistry(supported: values)
    }
}


enum OwnerConnectionPhase: Equatable {
    case notConfigured
    case locked
    case connecting
    case live
    case degraded
    case offline

    var title: String {
        switch self {
        case .notConfigured: "Nicht eingerichtet"
        case .locked: "Gesperrt"
        case .connecting: "Verbindung wird hergestellt …"
        case .live: "Live"
        case .degraded: "Gestört"
        case .offline: "Owner Backend nicht erreichbar"
        }
    }

    var symbol: String {
        switch self {
        case .notConfigured: "gearshape"
        case .locked: "lock.fill"
        case .connecting: "circle.dotted"
        case .live: "circle.fill"
        case .degraded: "exclamationmark.circle.fill"
        case .offline: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .live: .green
        case .degraded: .orange
        case .offline: .red
        case .connecting, .locked, .notConfigured: .secondary
        }
    }
}

enum OwnerRiskLevel: String, CaseIterable {
    case safe
    case operational
    case sensitive
    case critical

    var title: String {
        switch self {
        case .safe: "Safe"
        case .operational: "Operational"
        case .sensitive: "Sensitive"
        case .critical: "Critical"
        }
    }

    var tint: Color {
        switch self {
        case .safe: .green
        case .operational: .blue
        case .sensitive: .orange
        case .critical: .red
        }
    }
}

extension AdminAction {
    var ownerRiskLevel: OwnerRiskLevel {
        switch self {
        case .healthCheck: .safe
        case .createBackup, .rotateLogs: .operational
        case .reconnectSessions, .enableMaintenance, .disableMaintenance, .clearCache: .sensitive
        }
    }

    var ownerImpactText: String {
        switch self {
        case .healthCheck: "Prüft den Backend-Zustand ohne beabsichtigte Laufzeitänderung."
        case .createBackup: "Erstellt einen neuen Wiederherstellungspunkt im Owner-Backend."
        case .rotateLogs: "Schließt aktuelle Logsegmente und startet neue Segmente."
        case .reconnectSessions: "Aktive Backend-Verbindungen können kurz neu aufgebaut werden."
        case .enableMaintenance: "Versetzt das Owner-Backend in den Wartungsmodus."
        case .disableMaintenance: "Beendet den Wartungsmodus und gibt den normalen Betrieb wieder frei."
        case .clearCache: "Verwirft wiederaufbaubare Cache-Daten des Owner-Backends."
        }
    }

    var ownerPreconditions: [String] {
        var values = ["Owner-Sitzung aktiv", "Backend erreichbar"]
        if requiresFreshBiometrics {
            values.append("Frische Face-ID-Bestätigung")
        }
        return values
    }
}

extension SupportTicket {
    var ownerIsOpen: Bool { status != "resolved" }

    var ownerStatusTitle: String {
        switch status {
        case "open": "Neu"
        case "in_progress": "In Arbeit"
        case "approved": "Freigegeben"
        case "resolved": "Erledigt"
        default: status.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }
}

extension AdminBackendStatus {
    var ownerUptimeText: String {
        let total = max(0, Int(uptimeSeconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        if days > 0 { return "\(days) T \(hours) Std" }
        return "\(hours) Std"
    }
}

extension AdminControlModel {
    var ownerConnectionPhase: OwnerConnectionPhase {
        switch state {
        case .notConfigured:
            return .notConfigured
        case .locked:
            return .locked
        case .unlocking:
            return .connecting
        case .failed:
            return .offline
        case .unlocked:
            if lastError != nil { return .offline }
            guard let backendStatus else { return .connecting }
            return backendStatus.healthy ? .live : .degraded
        }
    }

    var ownerOpenTicketCount: Int {
        supportTickets.filter(\.ownerIsOpen).count
    }

    var ownerAttentionCount: Int {
        var count = 0
        if lastError != nil { count += 1 }
        if backendStatus?.databaseHealthy == false { count += 1 }
        if backendStatus?.maintenanceMode == true { count += 1 }
        if let queueDepth = backendStatus?.queueDepth, queueDepth > 20 { count += 1 }
        if diagnosticsV2?.healthy == false { count += 1 }
        if (securityV2?.activeBreakGlassSessions ?? 0) > 0 { count += 1 }
        return count
    }
}

extension AdminSystemStatusV2 {
    var ownerStateTitle: String {
        if !configured || state == "not_configured" { return "Nicht eingerichtet" }
        if state == "permission_denied" { return "Berechtigung fehlt" }
        if state == "unavailable" { return "Nicht erreichbar" }
        if state == "degraded" { return "Eingeschränkt" }
        if healthy { return state.replacingOccurrences(of: "_", with: " ").localizedCapitalized }
        return state.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    var ownerStateTint: Color {
        if !configured || state == "not_configured" { return .secondary }
        if state == "permission_denied" { return .orange }
        return healthy ? .green : .orange
    }
}

extension AdminControlModel {
    var ownerCapabilityRegistry: OwnerCapabilityRegistry {
        guard let v2Capabilities else { return .currentAdminAPI }
        return .discovered(from: v2Capabilities)
    }
}

extension AdminRemoteAction {
    var ownerRiskLevel: OwnerRiskLevel {
        OwnerRiskLevel(rawValue: risk) ?? .sensitive
    }

    var ownerImpactText: String {
        switch id {
        case "ha.config.check": "Prüft die Home-Assistant-Konfiguration ohne beabsichtigten Neustart."
        case "ha.core.restart": "Startet Home Assistant kontrolliert neu; Automationen und Verbindungen sind kurz nicht verfügbar."
        case "tailscale.restart": "Startet den privaten Tailscale-Dienst neu; Owner-Zugriff kann kurz unterbrochen werden."
        case "chat-relay.restart": "Startet den Chat Relay neu; flüchtige In-Memory-Queues können dabei verloren gehen."
        case "host.recovery": "Führt eine privilegierte Host-Recovery aus. Break-Glass ist zwingend erforderlich."
        case "hypervisor.snapshot.rollback": "Rollt eine VM auf einen ausgewählten Snapshot zurück. Break-Glass ist zwingend erforderlich."
        default: "Führt die serverseitig allowlistete Aktion \(title) aus."
        }
    }
}
