import SwiftUI

/// Factory Control Surface independent of Home Assistant and Owner login.
/// No implicit network access, mutation actions or fabricated status values.
struct FactoryStandaloneView: View {
    @State private var factory = FactoryConnectionModel()
    @State private var runtime = IOSNextRuntime.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("FACTORY · STANDALONE", systemImage: "network")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("Master Factory").font(.largeTitle.bold())
                    Text("Unabhängig von Home Assistant. Verbinde das Factory-Gateway erst, wenn du Live-Daten brauchst.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if FactoryWorldStaticBundle.available {
                    FactoryWorldView()
                }
                FactoryCommandDeck(factoryConnected: factory.phase == .connected,
                    ownerConnected: false,
                    runnerConnected: runnerOnline,
                    reportedSources: factory.snapshot?.rows.count ?? 0)

                NavigationLink {
                    FactoryConnectionView(model: factory)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(factory.phase == .disconnected ? "Factory verbinden" : "Factory-Verbindung verwalten")
                                .font(.headline)
                            Text(factory.phase.title)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(17)
                    .ios27ContentSurface(radius: 21)
                    .contentShape(RoundedRectangle(cornerRadius: 21))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preconnect-factory-configure")

                if factory.phase == .loading {
                    ProgressView("Factory-Verbindung wird aktualisiert …")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = factory.errorMessage {
                    IOSNextErrorBanner(message: error)
                }
                if factory.phase != .disconnected {
                    Button("Factory-Daten aktualisieren", systemImage: "arrow.clockwise") {
                        Task { await factory.refresh() }
                    }
                    .disabled(factory.phase == .loading)
                }

                if let snapshot = factory.snapshot {
                    Text("Factory MCP · \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.headline)
                    ForEach(snapshot.rows) { row in
                        OwnerStatusRow(title: row.title, detail: row.detail,
                            symbol: "point.3.connected.trianglepath.dotted",
                            value: row.status, tint: .indigo)
                    }
                    NavigationLink("Factory-MCP-Inventar") {
                        FactoryMCPDetailsView(snapshot: snapshot)
                    }
                    .buttonStyle(.glass)
                } else {
                    ContentUnavailableView("Factory bereit zur Einrichtung",
                        systemImage: "network",
                        description: Text("Die Oberfläche ist vollständig erreichbar. Live-Daten erscheinen nach autorisierter Verbindung."))
                }

                NavigationLink {
                    RunnerDashboardView(model: runtime.runnerModel)
                } label: {
                    Label("Runner separat einrichten", systemImage: "server.rack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)

                Label("Keine Factory-Schreibaktionen oder freien Befehle.",
                      systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: 670)
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Master Factory")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if factory.phase == .readyForRefresh {
                await factory.refresh()
            }
        }
        .accessibilityIdentifier("preconnect-factory-root")
    }

    private var runnerOnline: Bool {
        if case let .ready(status) = runtime.runnerModel.state {
            return status.vmOnline && status.serviceActive
        }
        return false
    }
}
