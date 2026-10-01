import SwiftUI

struct OwnerControlView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    let appModel: AppModel?
    let runnerModel: RunnerControlModel

    var body: some View {
        ControlCenterView(
            ownerModel: model,
            capabilities: capabilities,
            appModel: appModel,
            runnerModel: runnerModel
        )
    }
}

private struct ControlCenterView: View {
    let ownerModel: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    let appModel: AppModel?
    let runnerModel: RunnerControlModel
    @State private var runtime = IOSNextRuntime.shared

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                systemStatusCard.controlCenterModuleReveal(index: 0)
                runnerSection.controlCenterModuleReveal(index: 1)
                activitySection.controlCenterModuleReveal(index: 2)
                ownerSection.controlCenterModuleReveal(index: 3)
                OwnerOperationProgressView(model: ownerModel).controlCenterModuleReveal(index: 4)
            }
        }
        .refreshable {
            await ownerModel.refreshStatusV2()
            await runnerModel.refresh()
        }
    }

    private var systemStatusCard: some View {
        let chat = CommunicationHealthSnapshot(
            chatModel: runtime.chatModel,
            adminStatus: ownerModel.chatStatusV2,
            devices: ownerModel.chatDevicesV2
        )

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controlCenterReady ? "System bereit" : "Control Center")
                        .font(.title.bold())
                    Text("Owner · Runner · Master Runtime · Home Assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: controlCenterReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(controlCenterReady ? .green : .orange)
                    .accessibilityHidden(true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                statusBadge(title: "Owner", value: ownerHealthy ? "Online" : "Prüfen", symbol: "person.badge.key.fill", tint: ownerHealthy ? .green : .orange)
                statusBadge(title: "Runner", value: runnerHealthy ? "Online" : runnerSummaryValue, symbol: "server.rack", tint: runnerHealthy ? .green : .orange)
                statusBadge(title: "Runtime", value: runtimeSummaryValue, symbol: "terminal.fill", tint: runtimeIsLive ? .green : .secondary)
                statusBadge(title: "HA", value: homeAssistantConnected ? "Verbunden" : "Prüfen", symbol: "house.fill", tint: homeAssistantConnected ? .green : .secondary)
                statusBadge(title: "Chat", value: chat.clientTitle, symbol: "message.fill", tint: chat.isClientOnline ? .green : .orange)
            }
        }
        .padding(18)
        .iosNextSurface()
    }

    private func statusBadge(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var runnerSection: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Runner", subtitle: "Runner, Ressourcen und Master Runtime", symbol: "server.rack")
            switch runnerModel.state {
            case let .ready(status):
                NavigationLink {
                    RunnerDashboardView(model: runnerModel)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(status.serviceActive && status.vmOnline ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.serviceActive ? "Runner bereit" : "Runner gestoppt")
                                    .font(.headline)
                                Text(status.vmOnline ? "Ubuntu-VM erreichbar" : "Ubuntu-VM offline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 8) {
                            runnerCount("Online", status.registeredRunners, tint: .blue)
                            runnerCount("Frei", status.idleRunners, tint: .green)
                            runnerCount("Beschäftigt", status.busyRunners, tint: .orange)
                        }
                    }
                    .padding(16)
                    .iosNextSurface()
                }
                .buttonStyle(.plain)

                if status.commander != nil || runnerModel.commanderLiveState.effectiveSnapshot != nil {
                    NavigationLink {
                        CommanderLiveDetailView(model: runnerModel)
                    } label: {
                        CommanderLiveSummaryCard(state: runnerModel.commanderLiveState)
                    }
                    .buttonStyle(.plain)
                }
            case .notConfigured:
                NavigationLink {
                    RunnerDashboardView(model: runnerModel)
                } label: {
                    OwnerStatusRow(title: "Runner einrichten", detail: "Service-Zugang ist noch nicht konfiguriert.", symbol: "server.rack", value: "Öffnen", tint: .orange)
                }
                .buttonStyle(.plain)
            case .loading:
                OwnerStatusRow(title: "Runner", detail: "Status wird geladen …", symbol: "server.rack", value: "Lädt", tint: .blue)
            case let .failed(message):
                NavigationLink {
                    RunnerDashboardView(model: runnerModel)
                } label: {
                    OwnerStatusRow(title: "Runner nicht erreichbar", detail: message, symbol: "exclamationmark.triangle.fill", value: "Prüfen", tint: .orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runnerCount(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Aktivität", subtitle: "Nur Dinge, die gerade Aufmerksamkeit brauchen", symbol: "waveform.path.ecg")

            if ownerActiveJobs == 0 && runnerBusyJobs == 0 && ownerModel.ownerOpenTicketCount == 0 && ownerModel.ownerAttentionCount == 0 {
                OwnerStatusRow(
                    title: "Keine offene Aktivität",
                    detail: "Keine aktiven Jobs, Tickets oder Owner-Warnungen.",
                    symbol: "checkmark.circle.fill",
                    value: "Bereit",
                    tint: .green
                )
            } else {
                if hasActiveJobs {
                    OwnerStatusRow(
                        title: "Aktive Jobs",
                        detail: "Owner \(ownerActiveJobs) · Runner \(runnerBusyJobs)",
                        symbol: "gearshape.2.fill",
                        value: "\(ownerActiveJobs + runnerBusyJobs)",
                        tint: .blue
                    )
                }
                if ownerModel.ownerOpenTicketCount > 0 {
                    NavigationLink {
                        OwnerTicketInboxView(model: ownerModel)
                    } label: {
                        OwnerStatusRow(
                            title: "Offene Tickets",
                            detail: "Anfragen warten auf Bearbeitung oder Dispatch.",
                            symbol: "ticket.fill",
                            value: "\(ownerModel.ownerOpenTicketCount)",
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
                if ownerModel.ownerAttentionCount > 0 {
                    NavigationLink {
                        OwnerNotificationsView(model: ownerModel)
                    } label: {
                        OwnerStatusRow(
                            title: "Owner-Meldungen",
                            detail: "Backend, Diagnose oder Sicherheit benötigt Aufmerksamkeit.",
                            symbol: "bell.badge.fill",
                            value: "\(ownerModel.ownerAttentionCount)",
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ownerSection: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Owner Control", subtitle: "Projekte, Betrieb, Infrastruktur und Sicherheit", symbol: "person.badge.key.fill")
            NavigationLink {
                MasterPlatformView(model: ownerModel, runnerModel: runnerModel)
            } label: {
                OwnerStatusRow(
                    title: "Master Platform",
                    detail: "Data Plane, CI, Runner, Governance, Diagnostics und Owner Actions",
                    symbol: "square.3.layers.3d",
                    value: "1.4",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)
            ownerLink(.projects) { OwnerProjectsView(model: ownerModel, capabilities: capabilities) }
            ownerLink(.operations) { OwnerOperationsView(model: ownerModel, capabilities: capabilities) }
            ownerLink(.systems) { OwnerSystemsView(model: ownerModel, capabilities: capabilities, appModel: appModel) }
            ownerLink(.security) { OwnerSecurityView(model: ownerModel, capabilities: capabilities) }
            ownerLink(.communication) { OwnerCommunicationView(model: ownerModel, capabilities: capabilities) }
            ownerLink(.releases) { OwnerReleasesView(model: ownerModel, capabilities: capabilities) }
            if capabilities.supports(.tickets) {
                NavigationLink {
                    OwnerTicketInboxView(model: ownerModel)
                } label: {
                    OwnerStatusRow(
                        title: "Tickets",
                        detail: "Anfragen lesen, beantworten und dispatchen",
                        symbol: "ticket.fill",
                        value: "\(ownerModel.ownerOpenTicketCount) offen",
                        tint: ownerModel.ownerOpenTicketCount > 0 ? .orange : .green
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ownerLink<Destination: View>(_ route: OwnerSectionRoute, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            OwnerStatusRow(title: route.title, detail: route.subtitle, symbol: route.symbol, tint: .indigo)
        }
        .buttonStyle(.plain)
    }

    private var ownerHealthy: Bool { ownerModel.backendStatus?.healthy == true }
    private var homeAssistantConnected: Bool { appModel?.connectionState == .connected }

    private var runnerHealthy: Bool {
        guard case let .ready(status) = runnerModel.state else { return false }
        return status.vmOnline && status.serviceActive
    }

    private var runnerSummaryValue: String {
        switch runnerModel.state {
        case let .ready(status): return "\(status.registeredRunners) online"
        case .loading: return "Lädt"
        case .notConfigured: return "Setup"
        case .failed: return "Offline"
        }
    }

    private var runtimeIsLive: Bool {
        runnerModel.commanderLiveState.connection == .live
    }

    private var runtimeSummaryValue: String {
        switch runnerModel.commanderLiveState.connection {
        case .live: return "LIVE"
        case .connecting, .syncing, .reconnecting: return "Verbindet"
        case .degraded: return "Eingeschränkt"
        case .unconfigured: return "Setup"
        case .disconnected: return "Offline"
        }
    }

    private var ownerActiveJobs: Int {
        ownerModel.jobsV2.filter { !["completed", "resolved", "failed"].contains($0.state) }.count
    }

    private var runnerBusyJobs: Int {
        guard case let .ready(status) = runnerModel.state else { return 0 }
        return status.busyRunners
    }

    private var hasActiveJobs: Bool { ownerActiveJobs > 0 || runnerBusyJobs > 0 }

    private var controlCenterReady: Bool {
        ownerHealthy && runnerHealthy && homeAssistantConnected
    }
}
