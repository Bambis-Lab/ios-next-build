import SwiftUI

struct RunnerDashboardView: View {
    @State private var model: RunnerControlModel
    @State private var runtime = IOSNextRuntime.shared
    @State private var pendingAction: RunnerAction?
    @State private var showsTechnicalDetails = false

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
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--visual-runner-offline") {
                    runnerUnavailableSurface(message: "Simulierter Testzustand: Runner nicht erreichbar.")
                } else {
                    runnerSetupSurface
                }
#else
                runnerSetupSurface
#endif
            case .loading:
                ProgressView("Runner wird geladen …")
            case let .failed(message):
                runnerUnavailableSurface(message: message)
            case let .ready(status):
                dashboard(status)
            }
        }
        .background(FactoryAmbientBackground(kind: .runner))
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

    private var runnerSetupSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("RUNNER · CONTROL", systemImage: "server.rack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Runner Control")
                        .font(.largeTitle.bold())
                    Text("Ressourcen, laufende Jobs und begrenzte Aktionen – nach separater, gesicherter Verbindung.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                OwnerStatusRow(title: "Runner-Control-Dienst", detail: "Noch keine Verbindung eingerichtet", symbol: "server.rack", value: "Setup", tint: .blue)
                OwnerStatusRow(title: "Master Runtime Live", detail: "Read-only-Ereignisse über eigenen Live-Zugang", symbol: "waveform.path.ecg", value: "Separat", tint: .cyan)
                VStack(alignment: .leading, spacing: 12) {
                    Button("Einrichten") { model.isPresentingConfiguration = true }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("runner-setup-action")
                    Label("SSH- und GitHub-Zugangsdaten werden hier nicht benötigt.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .ios27ContentSurface(radius: 22)
            }
            .frame(maxWidth: 670)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("runner-unconfigured")
    }

    private func runnerUnavailableSurface(message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Runner nicht erreichbar", systemImage: "wifi.exclamationmark")
                    .font(.title2.bold())
                    .accessibilityIdentifier("runner-offline")
                OwnerAlertBanner(title: "Verbindung fehlgeschlagen", message: message, symbol: "exclamationmark.triangle")
                Button("Erneut versuchen") { Task { await model.refresh() } }
                    .buttonStyle(.glassProminent)
                Button("Konfiguration öffnen") { model.isPresentingConfiguration = true }
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: 670)
            .padding(.horizontal, 18)
            .padding(.top, 32)
            .frame(maxWidth: .infinity)
        }
    }

    private func dashboard(_ status: RunnerStatus) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                runnerHero(status)
                IOS27SectionHeader(title: "Kapazität", subtitle: "Aktuelle Ausführungsplätze")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    compactMetric(.registered, title: "Gesamt", value: status.registeredRunners, tint: .blue, status: status)
                    compactMetric(.idle, title: "Frei", value: status.idleRunners, tint: .green, status: status)
                    compactMetric(.busy, title: "Belegt", value: status.busyRunners, tint: .orange, status: status)
                }
                if let jobs = status.activeJobs, !jobs.isEmpty {
                    IOS27SectionHeader(title: "Laufende Jobs", subtitle: "\(jobs.count) vom Backend gemeldet")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(jobs.prefix(3)) { job in
                            HStack(spacing: 12) {
                                Image(systemName: "gearshape.2.fill").foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(job.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(job.state.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        if jobs.count > 3 {
                            Text("Weitere \(jobs.count - 3) Jobs im Runner-System")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(16).ios27ContentSurface(radius: 22)
                }
                if status.cpuPercent != nil || status.memoryPercent != nil || status.diskPercent != nil {
                    IOS27SectionHeader(title: "Ressourcen", subtitle: "Live vom Runner-Control-Dienst")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                        if let cpu = status.cpuPercent {
                            metricLink(.cpu, title: "CPU", value: percent(cpu), symbol: "cpu.fill", tint: cpu >= 85 ? .red : .blue, status: status)
                        }
                        if let ram = status.memoryPercent {
                            metricLink(.memory, title: "RAM", value: percent(ram), symbol: "memorychip.fill", tint: ram >= 85 ? .red : .purple, status: status)
                        }
                        if let disk = status.diskPercent {
                            metricLink(.disk, title: "Speicher", value: percent(disk), symbol: "internaldrive.fill", tint: disk >= 85 ? .red : .cyan, status: status)
                        }
                    }
                }
                if status.commander != nil || model.commanderLiveState.effectiveSnapshot != nil {
                    IOS27SectionHeader(title: "Master Runtime", subtitle: "Echter Live-Status")
                    NavigationLink {
                        CommanderLiveDetailView(model: model)
                    } label: {
                        CommanderLiveSummaryCard(state: model.commanderLiveState)
                    }
                    .buttonStyle(.plain)
                }
                DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                    VStack(alignment: .leading, spacing: 16) {
                        if status.bridge != nil || status.orchestrator != nil {
                            IOS27SectionHeader(title: "Infrastruktur", subtitle: "Relay und Orchestrierung")
                            if let bridge = status.bridge {
                                subsystemCard(bridge, symbol: "point.3.connected.trianglepath.dotted")
                            }
                            if let orchestrator = status.orchestrator {
                                subsystemCard(orchestrator, symbol: "flowchart.fill")
                            }
                        }
                        if let services = status.services, !services.isEmpty {
                            IOS27SectionHeader(title: "Services")
                            servicesCard(services)
                        }
                        if let backup = status.backup {
                            IOS27SectionHeader(title: "Backup")
                            IOS27StatusCard(
                                title: "Letztes Backup", value: backup.state,
                                symbol: "externaldrive.badge.checkmark",
                                tint: backup.state.localizedCaseInsensitiveContains("ok") ? .green : .blue,
                                detail: backup.lastSuccessful.map(formattedDate) ?? backup.detail
                            )
                        }
                        if let audit = status.recentAudit, !audit.isEmpty {
                            IOS27SectionHeader(title: "Letzte Aktionen")
                            auditCard(audit)
                        }
                        IOS27SectionHeader(title: "Steuerung", subtitle: "Nur freigegebene Aktionen")
                        VStack(spacing: 10) {
                            actionButton(.healthCheck, symbol: "stethoscope", status: status)
                            actionButton(.pause, symbol: "pause.circle.fill", status: status)
                            actionButton(.resume, symbol: "play.circle.fill", status: status)
                            actionButton(.gracefulRestart, symbol: "arrow.triangle.2.circlepath", status: status)
                            actionButton(.shutdown, symbol: "power", status: status, destructive: true)
                        }
                        if let receipt = model.lastReceipt {
                            IOS27StatusCard(
                                title: "Letzte Runner-Aktion", value: receipt.state,
                                symbol: "checkmark.seal.fill", tint: .green,
                                detail: "Request \(receipt.requestID)"
                            )
                        }
                    }
                    .padding(.top, 14)
                } label: {
                    Label("Diagnose & Steuerung", systemImage: "slider.horizontal.3").font(.headline)
                }
                .padding(16)
                .ios27ContentSurface(radius: 22)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaPadding(.bottom, 96)
        .background(FactoryAmbientBackground(kind: .runner))
    }

    private func compactMetric(
        _ metric: RunnerMetricDestination,
        title: String,
        value: Int,
        tint: Color,
        status: RunnerStatus
    ) -> some View {
        NavigationLink {
            RunnerMetricDetailView(metric: metric, status: status)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(value)").font(.title2.bold()).monospacedDigit().foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(14)
            .ios27ContentSurface(radius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Öffnet Runner-Details")
    }

    private func runnerHero(_ status: RunnerStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(status.serviceActive ? "Runner bereit" : "Runner gestoppt")
                        .font(.title2.bold())
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
            .background(FactoryAmbientBackground(kind: .runner))
            .navigationTitle("Runner-Zugang")
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
