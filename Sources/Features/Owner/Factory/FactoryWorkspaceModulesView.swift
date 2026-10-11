import SwiftUI

/// One navigational owner for the historical Master/Owner/Runner/Live modules.
/// Backend adapters remain separate until the Factory exposes equivalent APIs.
struct FactoryWorkspaceModulesView: View {
    @State private var runtime = IOSNextRuntime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOSNextSectionHeader(
                title: "Factory Workspace",
                subtitle: "Alle Verwaltungsbereiche an einem Ort · Datenquellen getrennt geprüft",
                symbol: "square.grid.2x2.fill"
            )
            NavigationLink {
                FactoryWorkspaceSourcesView()
            } label: {
                module("Daten & Schnittstellen", "Factory MCP, Verfügbarkeit und Herkunft", "network")
            }
            if runtime.factoryWorkspace.discoveredTools.contains("repositories_list") {
                NavigationLink {
                    FactoryWorkspaceCollectionView(title: "Repositories", toolName: "repositories_list")
                } label: {
                    module("Repositories", "Kanonische Factory-Registry · versionierter Vertrag", "folder.badge.gearshape")
                }
            }
            if runtime.factoryWorkspace.discoveredTools.contains("ci_runs_list") {
                NavigationLink {
                    FactoryWorkspaceCollectionView(title: "CI-Runs", toolName: "ci_runs_list")
                } label: {
                    module("CI & Workflows", "Factory-CI-Läufe mit Provenienz und Pagination", "gearshape.2.fill")
                }
            }
            NavigationLink {
                RunnerDashboardView(model: runtime.runnerModel)
            } label: {
                module("Runner & Infrastruktur", "Runner Control · eigene Berechtigung", "server.rack")
            }
            NavigationLink {
                LiveOperationsView()
            } label: {
                module("Live-Vorgänge", "Master Runtime Ereignisse · bestehender Live-Adapter", "waveform.path.ecg")
            }
            NavigationLink {
                AdminAreaView()
            } label: {
                module("Owner, Projekte & Betrieb", "Tickets, CI, Backups, Releases · gesicherter Owner-Zugang", "person.badge.key.fill")
            }
            NavigationLink {
                FactoryWorkspaceGovernanceView()
            } label: {
                module("Governance & Sicherheit", "Factory-Capabilities und wirksame Aktionssperren", "lock.shield.fill")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("factory-workspace-modules")
    }

    private func module(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(.indigo)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .ios27ContentSurface(radius: 19)
        .accessibilityElement(children: .combine)
    }
}

struct FactoryWorkspaceSourcesView: View {
    @State private var runtime = IOSNextRuntime.shared
    private var workspace: FactoryWorkspaceCoordinator { runtime.factoryWorkspace }

    var body: some View {
        List {
            Section("Factory MCP") {
                LabeledContent("Verbindung", value: workspace.connection.phase.title)
                LabeledContent("Entdeckte Tools", value: "\(workspace.discoveredTools.count)")
                LabeledContent("Neue Workspace-API", value: workspace.canReadWorkspace ? "Verfügbar" : "Noch nicht verfügbar")
                if workspace.connection.phase == .connected, let overview = workspace.overview {
                    LabeledContent("Quelle", value: overview.source)
                    LabeledContent("Status", value: overview.status)
                    LabeledContent("Schema", value: overview.schemaVersion)
                    LabeledContent("Aktualität", value: workspace.isOverviewCurrent ? "Aktuell" : "Veraltet / unbekannt")
                } else {
                    Text("Ohne veröffentlichten Workspace-Vertrag bleiben die bisherigen autorisierten Module verfügbar.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Datenherkunft") {
                if workspace.sourceStates.isEmpty {
                    ContentUnavailableView("Noch keine Factory-Daten",
                        systemImage: "network",
                        description: Text("Die Factory benötigt eine autorisierte Sitzung."))
                } else {
                    ForEach(workspace.sourceStates) { item in
                        LabeledContent(item.title, value: item.status)
                    }
                }
            }

            if let error = workspace.overviewError {
                Section("Eingeschränkte Quelle") {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Factory Event-Replay") {
                if !workspace.discoveredTools.contains("events_history_list") {
                    Text("Noch nicht vom Factory-Gateway angeboten. Die vorhandene Master-Runtime-Live-Ansicht bleibt verfügbar.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Cursor", value: workspace.eventHistory.lastSequence.map { String($0) } ?? "Noch kein Ereignis")
                    LabeledContent("Abgleich", value: workspace.eventsRequireResync ? "Lücke erkannt" : "Keine Lücke erkannt")
                    ForEach(workspace.recentFactoryEvents.suffix(20)) { event in
                        LabeledContent(event.kind, value: event.source)
                    }
                }
                if let error = workspace.eventHistoryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Factory-Daten")
        .refreshable { await workspace.refresh() }
        .task {
            if workspace.connection.phase == .readyForRefresh {
                await workspace.refresh()
            }
        }
    }
}

/// A capability advertised by the server is NOT an action authorization.
private struct FactoryCapabilityFlag: Identifiable {
    let name: String
    let active: Bool
    var id: String { name }
}

struct FactoryWorkspaceGovernanceView: View {
    @State private var runtime = IOSNextRuntime.shared
    private var workspace: FactoryWorkspaceCoordinator { runtime.factoryWorkspace }

    private var advertisedCapabilities: [FactoryCapabilityFlag] {
        guard let payload = workspace.connection.snapshot?.rawReports["capabilities_get"],
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capabilities = json["capabilities"] as? [String: Any] else { return [] }
        return capabilities.compactMap { name, value -> FactoryCapabilityFlag? in
            guard let active = value as? Bool else { return nil }
            return FactoryCapabilityFlag(name: name, active: active)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section("Factory-Berechtigungsinformationen") {
                if advertisedCapabilities.isEmpty {
                    Label("Keine authentifizierten Capability-Daten", systemImage: "lock.shield")
                } else {
                    ForEach(advertisedCapabilities) { item in
                        LabeledContent(item.name, value: item.active ? "Vom Backend unterstützt" : "Deaktiviert")
                    }
                }
            }
            Section("Aktionsfreigabe") {
                Label("Diese App ruft keine allgemeinen Factory-Schreibtools auf.",
                      systemImage: "hand.raised.fill")
                Text("Eine Backend-Capability ist keine persönliche Freigabe. Owner- und Runner-Aktionen behalten ihre eigenen Geräte-, Rollen- und Bestätigungskontrollen.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Factory-Sicherheit")
        .accessibilityIdentifier("factory-workspace-governance")
    }
}
