import SwiftUI

struct OwnerOperationsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                IOSNextSectionHeader(
                    title: "Betrieb",
                    subtitle: "Wartung mit klarer Trennung zwischen Status und Aktion",
                    symbol: "wrench.and.screwdriver.fill"
                )
                operationLink("Backups", detail: backupDetail, symbol: "externaldrive.fill") {
                    OwnerBackupView(model: model, capabilities: capabilities)
                }
                operationLink("Diagnose", detail: diagnosticsDetail, symbol: "stethoscope") {
                    OwnerDiagnosticsView(model: model, capabilities: capabilities)
                }
                operationLink("Logs", detail: logsDetail, symbol: "doc.text.fill") {
                    OwnerLogsView(model: model, capabilities: capabilities)
                }
                operationLink("Workflows", detail: workflowDetail, symbol: "point.3.connected.trianglepath.dotted") {
                    OwnerWorkflowView(model: model, capabilities: capabilities)
                }
                operationLink("Erweiterte Wartung", detail: "Sensitive Aktionen bewusst tiefer eingeordnet", symbol: "ellipsis.circle.fill") {
                    OwnerMaintenanceActionsView(model: model)
                }
                OwnerOperationProgressView(model: model)
            }
        }
        .navigationTitle("Betrieb")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshStatusV2() }
    }

    private var backupDetail: String {
        if let first = model.backupsV2.first {
            return first.verified ? "Letztes Backup verifiziert" : "Letztes Backup wartet auf Verifikation"
        }
        return model.backendStatus?.lastBackup == nil ? "Letztes Backup unbekannt" : "Backend meldet ein vorhandenes Backup"
    }

    private var diagnosticsDetail: String {
        guard let diagnostics = model.diagnosticsV2 else { return "Health und Datenbankstatus" }
        let ok = diagnostics.checks.filter(\.ok).count
        return "\(ok)/\(diagnostics.checks.count) Checks OK"
    }

    private var logsDetail: String {
        model.logsV2.isEmpty ? "Audit-basierte Logs und Rotation" : "\(model.logsV2.count) bereinigte Einträge geladen"
    }

    private var workflowDetail: String {
        let available = model.workflowsV2.filter(\.available).count
        return available == 0 ? "Keine aktiven Workflows" : "\(available) Workflow(s) verfügbar"
    }

    private func operationLink<Destination: View>(
        _ title: String,
        detail: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            OwnerStatusRow(title: title, detail: detail, symbol: symbol, tint: .indigo)
        }
        .buttonStyle(.plain)
    }
}

struct OwnerBackupView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    @State private var pendingAction: AdminAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                if !model.backupsV2.isEmpty {
                    IOSNextSectionHeader(title: "Wiederherstellungspunkte", subtitle: "SHA-256 und SQLite-Verify vom Owner Backend", symbol: "externaldrive.fill")
                    ForEach(Array(model.backupsV2.prefix(8))) { backup in
                        VStack(alignment: .leading, spacing: 8) {
                            OwnerStatusRow(
                                title: backup.createdAt.formatted(date: .abbreviated, time: .shortened),
                                detail: ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file),
                                symbol: backup.verified ? "checkmark.seal.fill" : "externaldrive.fill",
                                value: backup.verified ? "Verifiziert" : "Ungeprüft",
                                tint: backup.verified ? .green : .orange
                            )
                            if !backup.verified, model.canVerifyBackups {
                                Button("Integrität prüfen", systemImage: "checkmark.shield.fill") {
                                    Task { await model.verifyBackupV2(backup.id) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isLoading)
                            }
                        }
                    }
                } else if let date = model.backendStatus?.lastBackup {
                    OwnerStatusRow(
                        title: "Letztes Backup",
                        detail: "Vom Owner Backend gemeldeter Zeitpunkt",
                        symbol: "externaldrive.fill",
                        value: date.formatted(date: .abbreviated, time: .shortened),
                        tint: .green
                    )
                } else {
                    OwnerAlertBanner(
                        title: "Backup-Status unbekannt",
                        message: "Das Backend liefert aktuell keinen Wiederherstellungspunkt.",
                        symbol: "questionmark.circle"
                    )
                }

                if capabilities.supports(.backups), model.isActionAvailable(.createBackup) {
                    Button("Backup vorbereiten", systemImage: "externaldrive.fill.badge.plus") {
                        pendingAction = .createBackup
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "Backup erstellen",
                        detail: model.v2Capabilities == nil ? "Das verbundene Backend bietet keine Backup-Aktion." : "Im Observe-Modus ist das Erstellen von Backups gesperrt."
                    )
                }
                OwnerOperationProgressView(model: model)
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerActionSheet(action: action, isExecuting: model.isLoading) {
                Task { await model.perform(action) }
            }
        }
    }
}

struct OwnerDiagnosticsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    @State private var pendingAction: AdminAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                if let diagnostics = model.diagnosticsV2 {
                    OwnerStatusRow(
                        title: "Gesamtzustand",
                        detail: diagnostics.generatedAt.formatted(date: .omitted, time: .shortened),
                        symbol: diagnostics.healthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        value: diagnostics.healthy ? "OK" : "Prüfen",
                        tint: diagnostics.healthy ? .green : .orange
                    )
                    ForEach(diagnostics.checks) { check in
                        OwnerStatusRow(
                            title: check.title,
                            detail: check.detail,
                            symbol: check.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                            value: check.ok ? "OK" : "Fehler",
                            tint: check.ok ? .green : (check.severity == "error" ? .red : .orange)
                        )
                    }
                } else if let status = model.backendStatus {
                    OwnerStatusRow(title: "Backend", detail: "Gesamtzustand", symbol: "server.rack", value: status.healthy ? "Online" : "Gestört", tint: status.healthy ? .green : .orange)
                    OwnerStatusRow(title: "Datenbank", detail: "Serverseitiger Health-Status", symbol: "externaldrive.fill", value: status.databaseHealthy ? "OK" : "Gestört", tint: status.databaseHealthy ? .green : .red)
                    OwnerStatusRow(title: "Queue", detail: "Aktuelle Warteschlange", symbol: "list.bullet.rectangle", value: "\(status.queueDepth)")
                }
                if capabilities.supports(.diagnostics) {
                    Button("Health Check vorbereiten", systemImage: "stethoscope") {
                        pendingAction = .healthCheck
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                } else {
                    OwnerCapabilityUnavailableView(title: "Health Check")
                }
            }
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerActionSheet(action: action, isExecuting: model.isLoading) {
                Task { await model.perform(action) }
            }
        }
    }
}

struct OwnerLogsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    @State private var pendingAction: AdminAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                if model.logsV2.isEmpty {
                    OwnerCapabilityUnavailableView(
                        title: "Logviewer",
                        detail: model.v2Capabilities == nil ? "Owner API v2 ist nicht verbunden." : "Aktuell liegen keine bereinigten Logeinträge vor."
                    )
                } else {
                    IOSNextSectionHeader(title: "Bereinigte Logs", subtitle: "Secret-Redaction erfolgt vor der Übertragung", symbol: "doc.text.fill")
                    ForEach(Array(model.logsV2.prefix(100))) { entry in
                        OwnerStatusRow(
                            title: entry.source.localizedCapitalized,
                            detail: entry.message,
                            symbol: entry.level == "warning" ? "exclamationmark.triangle.fill" : "doc.text.fill",
                            value: entry.timestamp.formatted(date: .omitted, time: .shortened),
                            tint: entry.level == "warning" ? .orange : .indigo
                        )
                    }
                }
                if capabilities.supports(.logs), model.isActionAvailable(.rotateLogs) {
                    Button("Log-Rotation vorbereiten", systemImage: "doc.text.fill") {
                        pendingAction = .rotateLogs
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
                } else if capabilities.supports(.logs), model.v2Capabilities != nil {
                    OwnerCapabilityUnavailableView(title: "Log-Rotation", detail: "Im Observe-Modus gesperrt.")
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerActionSheet(action: action, isExecuting: model.isLoading) {
                Task { await model.perform(action) }
            }
        }
    }
}

struct OwnerWorkflowView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    @State private var pendingWorkflow: AdminWorkflowSummaryV2?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                if capabilities.supports(.workflows), !model.workflowsV2.isEmpty {
                    ForEach(model.workflowsV2) { workflow in
                        Button {
                            if workflow.available { pendingWorkflow = workflow }
                        } label: {
                            OwnerStatusRow(
                                title: workflow.title,
                                detail: workflow.steps.joined(separator: " → "),
                                symbol: "point.3.connected.trianglepath.dotted",
                                value: workflow.available ? workflow.risk.localizedCapitalized : "Nicht verfügbar",
                                tint: workflow.available ? .indigo : .secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!workflow.available || model.isLoading)
                    }
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "Workflows",
                        detail: "Das verbundene Owner Backend bietet noch keine Workflow-Capability."
                    )
                }
                if let receipt = model.lastWorkflowV2 {
                    OwnerStatusRow(
                        title: "Letzter Workflow",
                        detail: receipt.workflowID,
                        symbol: "checkmark.circle.fill",
                        value: receipt.state.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                        tint: receipt.state == "completed" ? .green : .orange
                    )
                }
            }
        }
        .navigationTitle("Workflows")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingWorkflow) { workflow in
            OwnerWorkflowConfirmationSheet(workflow: workflow, isExecuting: model.isLoading) {
                Task { await model.runWorkflowV2(workflow) }
            }
        }
    }
}

private struct OwnerWorkflowConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workflow: AdminWorkflowSummaryV2
    let isExecuting: Bool
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Schritte") {
                    ForEach(workflow.steps, id: \.self) { step in
                        Label(step, systemImage: "circle")
                    }
                }
                Section("Risiko") {
                    Text(workflow.risk.localizedCapitalized)
                }
                Section {
                    Button("Workflow starten") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(isExecuting || !workflow.available)
                }
            }
            .navigationTitle(workflow.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

struct OwnerMaintenanceActionsView: View {
    let model: AdminControlModel
    @State private var pendingAction: AdminAction?
    @State private var pendingRemoteAction: AdminRemoteAction?

    private var actions: [AdminAction] {
        [
            model.backendStatus?.maintenanceMode == true ? .disableMaintenance : .enableMaintenance,
            .reconnectSessions,
            .clearCache
        ]
    }

    private var remoteActions: [AdminRemoteAction] {
        let legacyIDs = Set(AdminAction.allCases.map(\.rawValue))
        return (model.v2Capabilities?.actions ?? []).filter { action in
            action.available && !legacyIDs.contains(action.id) && action.risk != "safe"
        }
    }

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerAlertBanner(
                    title: "Sensitive Aktionen",
                    message: "Diese Aktionen liegen bewusst nicht auf der Owner-Startseite und verlangen erneut Authentifizierung.",
                    symbol: "exclamationmark.shield.fill"
                )
                ForEach(actions) { action in
                    Button {
                        pendingAction = action
                    } label: {
                        OwnerStatusRow(
                            title: action.title,
                            detail: action.ownerImpactText,
                            symbol: action.symbol,
                            value: action.ownerRiskLevel.title,
                            tint: action.ownerRiskLevel.tint
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoading || !model.isActionAvailable(action))
                    if !model.isActionAvailable(action) {
                        Text("Im Observe-Modus nicht verfügbar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(remoteActions) { action in
                    Button {
                        pendingRemoteAction = action
                    } label: {
                        OwnerStatusRow(
                            title: action.title,
                            detail: action.ownerImpactText,
                            symbol: action.requiresBreakGlass ? "exclamationmark.octagon.fill" : "gearshape.2.fill",
                            value: action.ownerRiskLevel.title,
                            tint: action.ownerRiskLevel.tint
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoading)
                }
            }
        }
        .navigationTitle("Erweiterte Wartung")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerActionSheet(action: action, isExecuting: model.isLoading) {
                Task { await model.perform(action) }
            }
        }
        .sheet(item: $pendingRemoteAction) { action in
            OwnerRemoteActionSheet(action: action, isExecuting: model.isLoading) { parameters in
                Task { await model.performRemoteActionV2(action, parameters: parameters) }
            }
        }
    }
}
