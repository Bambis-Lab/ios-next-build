import SwiftUI

/// Generic bounded display for versioned Factory list contracts.
/// Does not guess backend payloads or expose arbitrary remote fields.
struct FactoryWorkspaceCollectionView: View {
    let title: String
    let toolName: String

    @State private var runtime = IOSNextRuntime.shared
    @State private var records: [FactoryWorkspaceRecord] = []
    @State private var source = ""
    @State private var isStale = true
    @State private var nextCursor: String?
    @State private var lastError: String?
    @State private var isLoading = false

    private var workspace: FactoryWorkspaceCoordinator { runtime.factoryWorkspace }

    var body: some View {
        List {
            if !workspace.discoveredTools.contains(toolName) {
                ContentUnavailableView("Factory-Schnittstelle nicht verfügbar",
                    systemImage: "network.slash",
                    description: Text("Dieses Modul benötigt eine aktualisierte Factory-API. Bestehende Owner-/Runner-Funktionen bleiben separat zugänglich."))
            } else {
                Section {
                    LabeledContent("Quelle", value: source.isEmpty ? "Noch keine Daten" : source)
                    LabeledContent("Datenstand", value: isStale ? "Veraltet / unbekannt" : "Vom Backend aktuell gemeldet")
                }
                Section(title) {
                    if records.isEmpty && !isLoading && lastError == nil {
                        ContentUnavailableView("Keine Einträge", systemImage: "tray")
                    }
                    ForEach(records) { item in
                        LabeledContent(item.title, value: item.state)
                    }
                    if let nextCursor, !nextCursor.isEmpty {
                        Button("Weitere Einträge laden") { Task { await load(more: true) } }
                            .disabled(isLoading)
                    }
                }
            }
            if isLoading {
                ProgressView("Factory-Daten werden geladen …")
            }
            if let lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle(title)
        .refreshable { await load(more: false) }
        .task { await load(more: false) }
    }

    @MainActor private func load(more: Bool) async {
        guard !isLoading, workspace.connection.phase == .connected,
              workspace.discoveredTools.contains(toolName),
              FactoryWorkspaceToolCatalog.isPermittedRead(toolName) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var args: [String: Any] = ["limit": 100]
            if more {
                guard let nextCursor, !nextCursor.isEmpty else { return }
                args["cursor"] = nextCursor
            }
            let text = try await workspace.connection.readWorkspaceTool(toolName, arguments: args)
            let batch = try FactoryWorkspaceCollection.decode(text)
            if !more { records.removeAll() }
            for record in batch.records where !records.contains(where: { $0.id == record.id }) {
                records.append(record)
            }
            source = batch.source
            isStale = batch.stale
            nextCursor = batch.nextCursor
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
