import SwiftUI

struct OwnerOverviewView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    let appModel: AppModel?
    @State private var pendingAction: AdminAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                overviewHeader
                attentionSection
                metrics
                quickActions
                systemNavigation
                managementNavigation
                OwnerOperationProgressView(model: model)
            }
        }
        .sheet(item: $pendingAction) { action in
            OwnerActionSheet(action: action, isExecuting: model.isLoading) {
                Task { await model.perform(action) }
            }
        }
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.backendStatus?.healthy == true ? "Owner Backend online" : "Owner Control")
                        .font(.title2.bold())
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                OwnerConnectionIndicator(model: model)
            }
        }
        .padding(18)
        .iosNextSurface()
    }

    @ViewBuilder
    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Aufmerksamkeit", subtitle: "Nur Zustände mit Handlungsbedarf", symbol: "bell.badge")
            if let error = model.lastError {
                OwnerAlertBanner(title: "Backend-Verbindung", message: error, symbol: "exclamationmark.triangle.fill", tint: .red)
            }
            if model.backendStatus?.databaseHealthy == false {
                OwnerAlertBanner(title: "Datenbank", message: "Das Owner Backend meldet die Datenbank als gestört.", symbol: "externaldrive.badge.exclamationmark", tint: .red)
            }
            if model.backendStatus?.maintenanceMode == true {
                OwnerAlertBanner(title: "Wartungsmodus", message: "Das Owner Backend befindet sich im Wartungsmodus.", symbol: "wrench.and.screwdriver.fill")
            }
            if let depth = model.backendStatus?.queueDepth, depth > 20 {
                OwnerAlertBanner(title: "Warteschlange", message: "\(depth) Einträge warten auf Verarbeitung.", symbol: "list.bullet.rectangle")
            }
            if model.ownerAttentionCount == 0 {
                OwnerStatusRow(title: "Keine kritischen Meldungen", detail: "Derzeit ist kein Owner-Eingriff erforderlich.", symbol: "checkmark.shield.fill", value: "OK", tint: .green)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            OwnerMetricView(title: "Owner Backend", value: backendMetric, symbol: "server.rack", tint: model.backendStatus?.healthy == true ? .green : .orange)
            OwnerMetricView(title: "Backup", value: backupMetric, symbol: "externaldrive.fill", tint: model.backendStatus?.lastBackup == nil ? .secondary : .green)
            OwnerMetricView(title: "Offene Tickets", value: "\(model.ownerOpenTicketCount)", symbol: "ticket.fill", tint: model.ownerOpenTicketCount > 0 ? .orange : .green)
            OwnerMetricView(title: "Queue", value: model.backendStatus.map { "\($0.queueDepth)" } ?? "—", symbol: "list.bullet.rectangle", tint: (model.backendStatus?.queueDepth ?? 0) > 20 ? .orange : .indigo)
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Schnellaktionen", subtitle: "Nur sichere oder vorbereitete Aktionen", symbol: "bolt.fill")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { quickActionButtons }
                VStack(spacing: 10) { quickActionButtons }
            }
        }
    }

    private var systemNavigation: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "System", subtitle: nil, symbol: "server.rack")
            ownerLink(.systems) { OwnerSystemsView(model: model, capabilities: capabilities, appModel: appModel) }
            ownerLink(.operations) { OwnerOperationsView(model: model, capabilities: capabilities) }
            ownerLink(.projects) { OwnerProjectsView(model: model, capabilities: capabilities) }
        }
    }

    private var managementNavigation: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Verwaltung", subtitle: nil, symbol: "gearshape.fill")
            ownerLink(.security) { OwnerSecurityView(model: model, capabilities: capabilities) }
            ownerLink(.communication) { OwnerCommunicationView(model: model, capabilities: capabilities) }
            ownerLink(.releases) { OwnerReleasesView(model: model, capabilities: capabilities) }
        }
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        if capabilities.supports(.diagnostics) {
            quickAction("Health Check", symbol: "stethoscope", action: .healthCheck)
        }
        if capabilities.supports(.backups), model.isActionAvailable(.createBackup) {
            quickAction("Backup", symbol: "externaldrive.fill.badge.plus", action: .createBackup)
        }
        if capabilities.supports(.tickets) {
            NavigationLink {
                OwnerTicketInboxView(model: model)
            } label: {
                Label("Tickets", systemImage: "ticket.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func quickAction(_ title: String, symbol: String, action: AdminAction) -> some View {
        Button {
            pendingAction = action
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isLoading)
    }

    private func ownerLink<Destination: View>(_ route: OwnerSectionRoute, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: route.symbol)
                    .foregroundStyle(.indigo)
                    .frame(width: 36, height: 36)
                    .background(Color.indigo.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.title).font(.headline)
                    Text(route.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
            }
            .padding(15)
            .iosNextSurface()
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        if model.lastError != nil { return "Owner Backend nicht erreichbar" }
        guard let status = model.backendStatus else { return "Status wird geladen …" }
        if !status.healthy { return "Backend meldet eine Störung" }
        if status.maintenanceMode { return "Wartungsmodus aktiv" }
        return "Keine kritischen Backend-Probleme erkannt"
    }

    private var backendMetric: String {
        guard let status = model.backendStatus else { return "—" }
        return status.healthy ? "Online" : "Gestört"
    }

    private var backupMetric: String {
        model.backendStatus?.lastBackup == nil ? "Unbekannt" : "Gemeldet"
    }
}
