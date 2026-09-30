import SwiftUI

struct GlobalSearchView: View {
    let appModel: AppModel
    @State private var query = ""

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "iOS Next durchsuchen",
                    systemImage: "magnifyingglass",
                    description: Text("Suche nach Räumen, Etagen oder Home-Assistant-Entitäten.")
                )
            } else if !hasResults {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                if !matchingAreas.isEmpty {
                    Section("Räume") {
                        ForEach(matchingAreas.prefix(20)) { area in
                            NavigationLink {
                                RoomDetailView(area: area, appModel: appModel)
                            } label: {
                                Label(area.appDisplayName, systemImage: "door.left.hand.open")
                            }
                        }
                    }
                }

                if !matchingFloors.isEmpty {
                    Section("Etagen") {
                        ForEach(matchingFloors.prefix(12)) { floor in
                            NavigationLink {
                                FloorDetailView(floor: floor, appModel: appModel)
                            } label: {
                                Label(floor.name, systemImage: "building.2.fill")
                            }
                        }
                    }
                }

                if !matchingEntities.isEmpty {
                    Section("Entitäten") {
                        ForEach(matchingEntities.prefix(40)) { entity in
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
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private var matchingAreas: [HomeAssistantArea] {
        guard !normalizedQuery.isEmpty else { return [] }
        return appModel.areas
            .filter { area in
                matches(area.name) || matches(area.appDisplayName)
            }
            .sorted { $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending }
    }

    private var matchingFloors: [HomeAssistantFloor] {
        guard !normalizedQuery.isEmpty else { return [] }
        return appModel.floors
            .filter { matches($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var matchingEntities: [HomeAssistantEntity] {
        guard !normalizedQuery.isEmpty else { return [] }
        return appModel.entities
            .filter { entity in
                matches(entity.displayName)
                    || matches(entity.entityID)
                    || matches(entity.secondaryStateText)
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var hasResults: Bool {
        !matchingAreas.isEmpty || !matchingFloors.isEmpty || !matchingEntities.isEmpty
    }

    private func matches(_ value: String) -> Bool {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .contains(normalizedQuery)
    }
}
