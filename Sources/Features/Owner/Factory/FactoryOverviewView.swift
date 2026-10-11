import SwiftUI

/// Native, read-only owner/runner projection. Factory MCP is NOT impersonated:
/// no tokens, fabricated registry values, shell commands or new write APIs.
struct FactoryOverviewView: View {
    let ownerModel: AdminControlModel
    let runnerModel: RunnerControlModel

    @State private var lastRefresh: Date?
    @State private var factoryConnection = FactoryConnectionModel()

    private var runnerStatus: RunnerStatus? {
        if case let .ready(status) = runnerModel.state { return status }
        return nil
    }

    var body: some View {
        OwnerPage {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                FactoryCommandDeck(
                    factoryConnected: factoryConnection.phase == .connected,
                    ownerConnected: ownerModel.backendStatus?.healthy == true,
                    runnerConnected: runnerStatus?.vmOnline == true,
                    reportedSources: factoryConnection.snapshot?.rows.count ?? 0
                )
                factoryLink
                summary
                sourceState
                if let snapshot = factoryConnection.snapshot {
                    factoryTelemetry(snapshot)
                }
                navigation
                provenance
            }
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Master Factory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    FactoryConnectionView(model: factoryConnection)
                } label: {
                    Label("Factory-Verbindung", systemImage: "network.badge.shield.half.filled")
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("FACTORY · CONTROL PLANE", systemImage: "network")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Deine Factory.\nEin Überblick.")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Owner, Runner und Factory MCP an einem Ort. Alles bereits vor der Anmeldung sichtbar, Livewerte erst nach autorisierter Verbindung.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Read-only Erweiterung", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .ios27ContentSurface(radius: 28, elevated: true)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            metric(title: "Projekte", value: ownerModel.backendStatus == nil ? "—" : String(ownerModel.projectsV2.count),
                   icon: "folder.fill", detail: "Owner API")
            metric(title: "Owner-Jobs", value: ownerModel.backendStatus == nil ? "—" : String(ownerModel.jobsV2.count),
                   icon: "square.stack.3d.up.fill", detail: "Owner API")
            metric(title: "Runner", value: runnerStatus.map { String($0.registeredRunners) } ?? "—",
                   icon: "server.rack", detail: "Runner Control")
            metric(title: "Aktive Runner-Jobs", value: runnerStatus?.activeJobs.map { String($0.count) } ?? "—",
                   icon: "gearshape.2.fill", detail: "Runner Control")
        }
    }

    private func metric(title: String, value: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text(value).font(.title.bold()).monospacedDigit()
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .padding(15)
        .ios27ContentSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }

    private var sourceState: some View {
        VStack(alignment: .leading, spacing: 10) {
            IOSNextSectionHeader(title: "Quellen", subtitle: "Jede Quelle wird unabhängig bewertet", symbol: "point.3.connected.trianglepath.dotted")
            OwnerStatusRow(
                title: "Owner Backend",
                detail: "Authentifizierter Control-Center-Zugang",
                symbol: "person.badge.key.fill",
                value: ownerModel.backendStatus == nil ? "Keine Daten" :
                    (ownerModel.backendStatus?.healthy == true ? "Online" : "Eingeschränkt"),
                tint: ownerModel.backendStatus?.healthy == true ? .green : .orange
            )
            OwnerStatusRow(
                title: "Runner Control",
                detail: "Runner-Daten und freigegebene Dienste",
                symbol: "server.rack",
                value: runnerStateTitle,
                tint: runnerStatus?.vmOnline == true ? .green : .orange
            )
            OwnerStatusRow(
                title: "Factory-MCP-Registry",
                detail: factoryConnection.lastRefresh.map { "Letzte MCP-Abfrage · \($0.formatted(date: .omitted, time: .shortened))" } ?? "OAuth 2.1 + PKCE S256 · nur lesende Tools",
                symbol: "network",
                value: factoryConnection.phase.title,
                tint: factoryConnection.phase == .connected ? .green : .secondary
            )
        }
    }

    private var factoryLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Factory Gateway").font(.headline)
                    Text(factoryConnection.phase.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: factoryConnection.phase == .connected ?
                      "checkmark.shield.fill" : "network.badge.shield.half.filled")
                    .font(.title3)
                    .foregroundStyle(factoryConnection.phase == .connected ? .green : .indigo)
            }
            if let error = factoryConnection.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                NavigationLink {
                    FactoryConnectionView(model: factoryConnection)
                } label: {
                    Label(factoryConnection.phase == .disconnected ? "Verbinden" : "Verwalten",
                          systemImage: "lock.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("factory-connect-entry")
                if factoryConnection.phase != .disconnected {
                    Button {
                        Task { await factoryConnection.refresh() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(factoryConnection.phase == .loading)
                }
            }
            .controlSize(.regular)
        }
        .padding(18)
        .ios27ContentSurface(radius: 24)
    }

    @ViewBuilder
    private func factoryTelemetry(_ snapshot: FactorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IOSNextSectionHeader(
                title: "Factory MCP",
                subtitle: "Letzte erfolgreiche Abfrage · \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))",
                symbol: "network"
            )
            if snapshot.rows.isEmpty {
                OwnerStatusRow(
                    title: "Keine kompatiblen lesenden Tools",
                    detail: "Die Verbindung steht, aber der Server bietet keine bekannten Read-only-Funktionen an.",
                    symbol: "lock.shield", value: "0", tint: .secondary
                )
            } else {
                ForEach(snapshot.rows) { row in
                    OwnerStatusRow(
                        title: row.title,
                        detail: row.detail,
                        symbol: "point.3.connected.trianglepath.dotted",
                        value: row.status,
                        tint: row.status.lowercased().contains("ready") ||
                              row.status.lowercased() == "ok" ? .green : .indigo
                    )
                }
                NavigationLink {
                    FactoryMCPDetailsView(snapshot: snapshot)
                } label: {
                    item("MCP-Funktionsinventar",
                         detail: "Verfügbare Schnittstellen und sichere Telemetrie",
                         icon: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var runnerStateTitle: String {
        switch runnerModel.state {
        case .ready: "Online"
        case .notConfigured: "Nicht eingerichtet"
        case .loading: "Verbindet"
        case .failed: "Offline"
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 10) {
            IOSNextSectionHeader(title: "Arbeitsbereiche", subtitle: "Native Details aus bestehenden Datenquellen", symbol: "square.grid.2x2.fill")
            NavigationLink {
                FactoryProjectsView(ownerModel: ownerModel)
            } label: {
                item("Organisation & Projekte", detail: "Owner-Projekte mit Repository-Zuordnung", icon: "folder.badge.gearshape")
            }
            NavigationLink {
                FactoryJobsView(ownerModel: ownerModel, runnerModel: runnerModel)
            } label: {
                item("CI & Jobs", detail: "Owner-Aufträge und zugeordnete Runner-Jobs", icon: "gearshape.2.fill")
            }
            NavigationLink {
                RunnerDashboardView(model: runnerModel)
            } label: {
                item("Runner & Infrastruktur", detail: "CPU, RAM, Speicher, Dienste und Steuerung", icon: "server.rack")
            }
            NavigationLink {
                MasterPlatformView(model: ownerModel, runnerModel: runnerModel)
            } label: {
                item("Master Platform", detail: "Bestandsansicht für CI und Datenherkunft", icon: "square.3.layers.3d")
            }
            NavigationLink {
                FactoryGovernanceView(ownerModel: ownerModel)
            } label: {
                item("Governance & Diagnose", detail: "Rechte, Sperren und redigierte Diagnosen", icon: "lock.shield.fill")
            }
        }
        .buttonStyle(.plain)
    }

    private func item(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 28)
                .foregroundStyle(.indigo).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .ios27ContentSurface(radius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Detailansicht öffnen")
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Datenherkunft").font(.caption.weight(.semibold))
            Text("Owner-Backend, Runner-Control und optional Factory MCP. Die einzelnen Quellen melden ihren Datenstand unabhängig. Keine neuen Schreibaktionen.")
            if let lastRefresh {
                Text("Zuletzt abgefragt: \(lastRefresh.formatted(date: .abbreviated, time: .standard))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor private func refresh() async {
        await ownerModel.refreshStatusV2()
        await runnerModel.refresh()
        if factoryConnection.phase != .disconnected {
            await factoryConnection.refresh()
        }
        lastRefresh = Date()
    }
}

private struct FactoryProjectsView: View {
    let ownerModel: AdminControlModel

    var body: some View {
        OwnerPage {
            LazyVStack(alignment: .leading, spacing: 12) {
                IOSNextSectionHeader(title: "Organisation & Projekte",
                    subtitle: "Nur vom Owner-Backend gelieferte Einträge", symbol: "folder.fill")
                if ownerModel.projectsV2.isEmpty {
                    ContentUnavailableView("Keine Projekte geladen", systemImage: "folder",
                        description: Text("Owner-Backend prüfen oder die Liste aktualisieren."))
                } else {
                    ForEach(ownerModel.projectsV2) { project in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(project.title).font(.headline)
                            Text(project.repository ?? "Keine Repository-Zuordnung geliefert")
                                .font(.subheadline).foregroundStyle(.secondary)
                            LabeledContent("Aktive Jobs", value: "\(project.activeJobs)")
                            LabeledContent("Dispatches", value: "\(project.dispatchCount)")
                            if let state = project.latestDispatchState {
                                LabeledContent("Letzter Dispatch", value: state)
                            }
                        }
                        .padding(16)
                        .ios27ContentSurface(radius: 20)
                    }
                }
            }
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Projekte")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await ownerModel.refreshStatusV2() }
    }
}

private struct FactoryJobsView: View {
    let ownerModel: AdminControlModel
    let runnerModel: RunnerControlModel

    private var status: RunnerStatus? {
        if case let .ready(snapshot) = runnerModel.state { return snapshot }
        return nil
    }

    var body: some View {
        OwnerPage {
            LazyVStack(alignment: .leading, spacing: 12) {
                IOSNextSectionHeader(title: "Runner-Jobs",
                    subtitle: "Quelle: Runner Control /v1/status", symbol: "server.rack")
                if let jobs = status?.activeJobs, !jobs.isEmpty {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(job.name).font(.headline)
                            Text([job.repository, job.workflow].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            LabeledContent("Status", value: job.state)
                            if let name = job.runnerName {
                                LabeledContent("Runner", value: name)
                            }
                        }
                        .padding(16)
                        .ios27ContentSurface(radius: 20)
                    }
                } else {
                    OwnerStatusRow(title: "Keine Runner-Jobs geladen",
                        detail: "Keine aktiven Jobs gemeldet oder Runner nicht verbunden.",
                        symbol: "clock", value: "—", tint: .secondary)
                }

                IOSNextSectionHeader(title: "Owner-Aufträge",
                    subtitle: "Quelle: authentifiziertes Owner-Backend", symbol: "checkmark.shield.fill")
                if ownerModel.jobsV2.isEmpty {
                    OwnerStatusRow(title: "Keine Owner-Aufträge geladen",
                        detail: "Keine Aufträge gemeldet oder Quelle nicht verbunden.",
                        symbol: "tray", value: "—", tint: .secondary)
                } else {
                    ForEach(ownerModel.jobsV2) { job in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(job.id).font(.subheadline.weight(.semibold)).textSelection(.enabled)
                            LabeledContent("Projekt", value: job.projectID)
                            LabeledContent("Status", value: job.state)
                            Text("Freigabe: \(job.approvedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .ios27ContentSurface(radius: 20)
                    }
                }
            }
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("CI & Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await ownerModel.refreshStatusV2()
            await runnerModel.refresh()
        }
    }
}

private struct FactoryGovernanceView: View {
    let ownerModel: AdminControlModel

    var body: some View {
        OwnerPage {
            LazyVStack(alignment: .leading, spacing: 12) {
                IOSNextSectionHeader(title: "Factory-Governance",
                    subtitle: "Die neue Factory-Seite führt keine Schreibaktionen aus", symbol: "lock.shield.fill")
                ForEach(MasterCapability.allCases) { capability in
                    OwnerStatusRow(
                        title: capability.title,
                        detail: capability == .readOnly ?
                            "Lesender Zugriff über bestehende Owner- und Runner-Dienste." :
                            "Nicht über das neue Factory-Modul ausführbar.",
                        symbol: capability == .readOnly ? "eye.fill" : "lock.fill",
                        value: capability == .readOnly ? "Lesen" : "Gesperrt",
                        tint: capability == .readOnly ? .green : .secondary
                    )
                }
                IOSNextSectionHeader(title: "Owner-API-Capabilities",
                    subtitle: "Serverseitig gemeldete Rechte, keine Factory-MCP-Autorisierung", symbol: "checkmark.shield")
                if let values = ownerModel.v2Capabilities?.capabilities, !values.isEmpty {
                    ForEach(Array(Set(values)).sorted(), id: \.self) { value in
                        Text(value)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .ios27ContentSurface(radius: 14)
                    }
                } else {
                    Text("Keine Capabilities vom Owner-Backend geladen.")
                        .foregroundStyle(.secondary)
                }
                IOSNextSectionHeader(title: "Diagnosen", subtitle: "Sensibler Inhalt wird entfernt", symbol: "stethoscope")
                if let checks = ownerModel.diagnosticsV2?.checks, !checks.isEmpty {
                    ForEach(checks.prefix(20)) { check in
                        OwnerStatusRow(title: check.title,
                            detail: MasterDiagnosticRedactor.sanitized(check.detail),
                            symbol: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            value: check.ok ? "OK" : check.severity,
                            tint: check.ok ? .green : .orange)
                    }
                } else {
                    Text("Keine Diagnosewerte geliefert.").foregroundStyle(.secondary)
                }
            }
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Governance")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await ownerModel.refreshStatusV2() }
    }
}
