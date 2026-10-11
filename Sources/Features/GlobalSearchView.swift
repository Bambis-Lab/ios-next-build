import SwiftUI

private struct GlobalSearchResults {
    var query = ""
    var areas: [HomeAssistantArea] = []
    var floors: [HomeAssistantFloor] = []
    var entities: [HomeAssistantEntity] = []
    static let empty = GlobalSearchResults()
}

struct GlobalSearchView: View {
    let appModel: AppModel
    @State private var query = ""
    @State private var results = GlobalSearchResults.empty
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "iOS Next durchsuchen",
                    systemImage: "magnifyingglass",
                    description: Text("Suche nach Räumen, Etagen oder Home-Assistant-Entitäten.")
                )
            } else if results.query != normalizedQuery {
                HStack {
                    ProgressView()
                    Text("Suche wird aktualisiert …").foregroundStyle(.secondary)
                }
            } else if !hasResults {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                if !results.areas.isEmpty {
                    Section("Räume") {
                        ForEach(results.areas.prefix(20)) { area in
                            NavigationLink {
                                RoomDetailView(area: area, appModel: appModel)
                            } label: {
                                Label(area.appDisplayName, systemImage: "door.left.hand.open")
                            }
                        }
                    }
                }

                if !results.floors.isEmpty {
                    Section("Etagen") {
                        ForEach(results.floors.prefix(12)) { floor in
                            NavigationLink {
                                FloorDetailView(floor: floor, appModel: appModel)
                            } label: {
                                Label(floor.name, systemImage: "building.2.fill")
                            }
                        }
                    }
                }

                if !results.entities.isEmpty {
                    Section("Entitäten") {
                        ForEach(results.entities.prefix(40)) { entity in
                            NavigationLink {
                                EntityDetailView(entityID: entity.entityID, appModel: appModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(entity.displayName, systemImage: entity.iconName)
                                    Text("\(entity.secondaryStateText) · \(entity.entityID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Räume, Etagen, Entitäten")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .iosNextManagementBackground()
        .navigationTitle("Suche")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { scheduleSearch(query) }
        .onChange(of: normalizedQuery) { _, value in scheduleSearch(value) }
        .onChange(of: appModel.searchRevision) { _, _ in scheduleSearch(query) }
        .onChange(of: appModel.areas) { _, _ in scheduleSearch(query) }
        .onChange(of: appModel.floors) { _, _ in scheduleSearch(query) }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        Self.normalize(trimmedQuery)
    }

    private var hasResults: Bool {
        !results.areas.isEmpty || !results.floors.isEmpty || !results.entities.isEmpty
    }

    private func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()
        let query = Self.normalize(rawQuery)
        guard !query.isEmpty else {
            results = .empty
            return
        }
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let trace = IOSNextPerformance.begin("Search.Query")
            defer { IOSNextPerformance.end("Search.Query", trace) }

            // Snapshot references are read only on MainActor. Debouncing avoids
            // sorting every collection for every intermediate keystroke.
            let areas = appModel.areas.filter {
                Self.matches($0.name, query) || Self.matches($0.appDisplayName, query)
            }.sorted {
                $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending
            }
            let floors = appModel.floors.filter {
                Self.matches($0.name, query)
            }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let entities = appModel.entities.filter {
                Self.matches($0.displayName, query)
                    || Self.matches($0.entityID, query)
                    || Self.matches($0.secondaryStateText, query)
            }.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            guard !Task.isCancelled, query == normalizedQuery else { return }
            results = GlobalSearchResults(query: query, areas: areas, floors: floors, entities: entities)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func matches(_ value: String, _ query: String) -> Bool {
        normalize(value).contains(query)
    }
}
