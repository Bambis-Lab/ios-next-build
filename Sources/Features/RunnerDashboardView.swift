import SwiftUI

struct RunnerDashboardView: View {
    @State private var model: RunnerControlModel
    @State private var runtime = IOSNextRuntime.shared
    @State private var pendingAction: RunnerAction?

    init() {
        _model = State(initialValue: IOSNextRuntime.shared.runnerModel)
    }

    init(model: RunnerControlModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state {
            case .notConfigured:
                ContentUnavailableView {
                    Label("Runner nicht eingerichtet", systemImage: "server.rack")
                } description: {
                    Text("Verbinde die App mit dem begrenzten Runner-Control-Dienst. SSH- und GitHub-Zugangsdaten bleiben außerhalb der App.")
                } actions: {
                    Button("Einrichten") { model.isPresentingConfiguration = true }
                        .buttonStyle(.glassProminent)
                }
            case .loading:
                ProgressView("Runner wird geladen …")
            case let .failed(message):
                ContentUnavailableView {
                    Label("Runner nicht erreichbar", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(message)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.refresh() } }
                        .buttonStyle(.glassProminent)
                    Button("Konfiguration öffnen") { model.isPresentingConfiguration = true }
                        .buttonStyle(.glass)
                }
            case let .ready(status):
                dashboard(status)
            }
        }
        .background(IOS27HomeBackground(style: .neutral))
        .navigationTitle("Runner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            runtime.setRunnerPollingActive("runner-dashboard", active: true)
        }
        .onDisappear {
            runtime.setRunnerPollingActive("runner-dashboard", active: false)
        }
        .alert("Runner-Aktion fehlgeschlagen", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "Unbekannter Fehler")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Konfigurieren", systemImage: "gearshape") {
                    model.isPresentingConfiguration = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $model.isPresentingConfiguration) {
            RunnerConfigurationView(model: model)
        }
        .confirmationDialog(
            pendingAction?.title ?? "Runner-Aktion",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(action.title, role: action == .shutdown ? .destructive : nil) {
                    Task { await model.perform(action) }
                    pendingAction = nil
                }
            }
            Button("Abbrechen", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Laufende Jobs werden geschützt. Kritische Aktionen verlangen zusätzlich die Geräteauthentifizierung.")
        }
    }

    private func dashboard(_ status: RunnerStatus) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                runnerHero(status)

                IOS27SectionHeader(title: "Systemstatus", subtitle: "Live vom begrenzten Runner-Control-Dienst")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    metricLink(.registered, title: "Registriert", value: "\(status.registeredRunners)", symbol: "server.rack", tint: .blue, status: status)
                    metricLink(.idle, title: "Frei", value: "\(status.idleRunners)", symbol: "checkmark.circle.fill", tint: .green, status: status)
                    metricLink(.busy, title: "Beschäftigt", value: "\(status.busyRunners)", symbol: "hammer.fill", tint: .orange, status: status)
                    if let cpu = status.cpuPercent {
                        metricLink(.cpu, title: "CPU", value: percent(cpu), symbol: "cpu.fill", tint: cpu >= 85 ? .red : .blue, status: status)
                    }
                    if let memory = status.memoryPercent {
                        metricLink(.memory, title: "RAM", value: percent(memory), symbol: "memorychip.fill", tint: memory >= 85 ? .red : .purple, status: status)
                    }
                    if let disk = status.diskPercent {
                        metricLink(.disk, title: "Speicher", value: percent(disk), symbol: "internaldrive.fill", tint: disk >= 85 ? .red : .cyan, status: status)
                    }
                }

                if status.bridge != nil || status.orchestrator != nil {
                    IOS27SectionHeader(title: "Infrastruktur", subtitle: "Relay · Orchestrierung")
                    if let bridge = status.bridge { subsystemCard(bridge, symbol: "point.3.connected.trianglepath.dotted") }
                    if let orchestrator = status.orchestrator { subsystemCard(orchestrator, symbol: "flowchart.fill") }
                }

                if status.commander != nil || model.commanderLiveState.effectiveSnapshot != nil {
                    IOS27SectionHeader(
                        title: "Master Runtime",
                        subtitle: "Sanitisierte Echtzeit-Telemetrie des eigenen Systems"
                    )
                    NavigationLink {
                        CommanderLiveDetailView(model: model)
                    } label: {
                        CommanderLiveSummaryCard(state: model.commanderLiveState)
                    }
                    .buttonStyle(.plain)
                }

                if let services = status.services, !services.isEmpty {
                    IOS27SectionHeader(title: "Services", subtitle: "Nur vom Backend freigegebene Dienste")
                    servicesCard(services)
                }

                if let backup = status.backup {
                    IOS27SectionHeader(title: "Backup")
                    IOS27StatusCard(
                        title: "Letztes Backup",
                        value: backup.state,
                        symbol: "externaldrive.badge.checkmark",
                        tint: backup.state.localizedCaseInsensitiveContains("ok") ? .green : .blue,
                        detail: backup.lastSuccessful.map(formattedDate) ?? backup.detail
                    )
                }

                if let audit = status.recentAudit, !audit.isEmpty {
                    IOS27SectionHeader(title: "Letzte Aktionen", subtitle: "Audit-Ansicht")
                    auditCard(audit)
                }

                IOS27SectionHeader(title: "Steuerung", subtitle: "Nur fest freigegebene Aktionen")
                VStack(spacing: 10) {
                    actionButton(.healthCheck, symbol: "stethoscope", status: status)
                    actionButton(.pause, symbol: "pause.circle.fill", status: status)
                    actionButton(.resume, symbol: "play.circle.fill", status: status)
                    actionButton(.gracefulRestart, symbol: "arrow.triangle.2.circlepath", status: status)
                    actionButton(.shutdown, symbol: "power", status: status, destructive: true)
                }

                if let receipt = model.lastReceipt {
                    IOS27StatusCard(
                        title: "Letzte Runner-Aktion",
                        value: receipt.state,
                        symbol: "checkmark.seal.fill",
                        tint: .green,
                        detail: "Request \(receipt.requestID)"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground(style: .neutral))
    }

    private func runnerHero(_ status: RunnerStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(status.serviceActive ? "Runner bereit" : "Runner gestoppt")
                        .font(.largeTitle.bold())
                    Text(status.vmOnline ? "Ubuntu-VM erreichbar" : "Ubuntu-VM offline")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: status.serviceActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(status.serviceActive ? .green : .red)
                    .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { heroMetadata(status) }
                VStack(alignment: .leading, spacing: 8) { heroMetadata(status) }
            }
        }
        .padding(20)
        .ios27ContentSurface(radius: 28, elevated: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func heroMetadata(_ status: RunnerStatus) -> some View {
        if let maintenance = status.maintenanceMode {
            Label(
                maintenance ? "Wartung" : "Jobannahme aktiv",
                systemImage: maintenance ? "wrench.and.screwdriver.fill" : "play.fill"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(maintenance ? .orange : .green)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.055), in: Capsule())
        }
        if let activeJobs = status.activeJobs?.count, activeJobs > 0 {
            Label("\(activeJobs) Jobs aktiv", systemImage: "gearshape.2.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        if let uptime = status.uptimeSeconds {
            Label(formatUptime(uptime), systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        if let health = status.lastHealthCheck {
            Label(formattedDate(health), systemImage: "heart.text.square.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
    }

    private func metricLink(
        _ metric: RunnerMetricDestination,
        title: String,
        value: String,
        symbol: String,
        tint: Color,
        status: RunnerStatus
    ) -> some View {
        NavigationLink {
            RunnerMetricDetailView(metric: metric, status: status)
        } label: {
            IOS27StatusCard(title: title, value: value, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet die Detailansicht")
    }

    private func subsystemCard(_ subsystem: RunnerSubsystemStatus, symbol: String) -> some View {
        IOS27StatusCard(
            title: subsystem.name,
            value: subsystem.active ? "Aktiv" : "Inaktiv",
            symbol: symbol,
            tint: subsystem.active ? .green : .secondary,
            detail: [subsystem.version, subsystem.detail, subsystem.lastSeen.map(formattedDate)]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
    }

    private func servicesCard(_ services: [RunnerServiceStatus]) -> some View {
        DisclosureGroup("Services (\(services.count))") {
            VStack(spacing: 0) {
                ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(service.active ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name).font(.subheadline.weight(.semibold))
                            if let detail = service.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(service.active ? "Aktiv" : "Aus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(service.active ? .green : .secondary)
                    }
                    .padding(.vertical, 9)
                    if index != services.indices.last { Divider() }
                }
            }
            .padding(.top, 6)
        }
        .padding(14)
        .ios27ContentSurface(radius: 24)
    }

    private func auditCard(_ audit: [RunnerAuditEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(audit.prefix(5))) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.action).font(.subheadline.weight(.semibold))
                        Text(entry.result).font(.caption).foregroundStyle(.secondary)
                        Text(formattedDate(entry.timestamp)).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                if entry.id != audit.prefix(5).last?.id { Divider().padding(.leading, 34) }
            }
        }
        .padding(.horizontal, 14)
        .ios27ContentSurface(radius: 24)
    }

    private func actionButton(
        _ action: RunnerAction,
        symbol: String,
        status: RunnerStatus,
        destructive: Bool = false
    ) -> some View {
        let enabled = actionEnabled(action, status: status)
        return Button {
            pendingAction = action
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(destructive ? Color.red : Color.blue)
                    .frame(width: 38, height: 38)
                    .background((destructive ? Color.red : Color.blue).opacity(0.10), in: Circle())
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer(minLength: 0)
                if action.requiresBiometrics {
                    Image(systemName: "faceid")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Geräteauthentifizierung erforderlich")
                }
            }
            .padding(14)
            .ios27ContentSurface(radius: 20)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func actionEnabled(_ action: RunnerAction, status: RunnerStatus) -> Bool {
        guard status.vmOnline else { return false }
        switch action {
        case .pause: return status.maintenanceMode != true
        case .resume: return status.maintenanceMode != false
        case .healthCheck: return true
        case .gracefulRestart: return status.serviceActive
        case .shutdown: return true
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let totalHours = max(0, Int(seconds / 3_600))
        let days = totalHours / 24
        let hours = totalHours % 24
        return days > 0 ? "\(days) T \(hours) Std" : "\(hours) Std"
    }
}

private struct RunnerConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    let model: RunnerControlModel
    @State private var endpoint = ""
    @State private var token = ""
    @State private var liveToken = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Runner-Control-Dienst") {
                    TextField("https://runner-control.local/", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Control-Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Runtime-Live-Token (read-only)", text: $liveToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Die App unterstützt keine freie Shell. Der vorhandene Commander-Live-Vertrag wird nur als Kompatibilitätsadapter für die sanitisierte Master-Runtime-Telemetrie verwendet; das read-only Token fällt nie auf das Control-Token zurück.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Konfiguration entfernen", role: .destructive) {
                        model.removeConfiguration()
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(IOS27HomeBackground(style: .neutral))
            .navigationTitle("Runner einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        do {
                            try model.configure(endpoint: endpoint, token: token, liveToken: liveToken)
                            Task { await model.refresh() }
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(endpoint.isEmpty || token.isEmpty)
                }
            }
        }
    }
}
