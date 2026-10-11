import Foundation

/// Reusable normalized search snapshot. Display ordering and Unicode folding
/// are computed once per debounced data revision, not for each keystroke.
struct GlobalSearchIndex {
    struct Results {
        let areas: [HomeAssistantArea]
        let floors: [HomeAssistantFloor]
        let entities: [HomeAssistantEntity]
    }

    private struct AreaEntry {
        let value: HomeAssistantArea
        let fields: [String]
    }
    private struct FloorEntry {
        let value: HomeAssistantFloor
        let fields: [String]
    }
    private struct EntityEntry {
        let value: HomeAssistantEntity
        let fields: [String]
    }

    private var areaEntries: [AreaEntry] = []
    private var floorEntries: [FloorEntry] = []
    private var entityEntries: [EntityEntry] = []
    private(set) var sourceRevision: UInt64 = 0

    mutating func rebuild(
        areas: [HomeAssistantArea],
        floors: [HomeAssistantFloor],
        entities: [HomeAssistantEntity],
        revision: UInt64
    ) {
        areaEntries = areas.map { area in
            AreaEntry(value: area, fields: [Self.normalize(area.name), Self.normalize(area.appDisplayName)])
        }.sorted {
            let comparison = $0.value.appDisplayName.localizedStandardCompare($1.value.appDisplayName)
            return comparison == .orderedSame ? $0.value.id < $1.value.id : comparison == .orderedAscending
        }
        floorEntries = floors.map { floor in
            FloorEntry(value: floor, fields: [Self.normalize(floor.name)])
        }.sorted {
            let comparison = $0.value.name.localizedStandardCompare($1.value.name)
            return comparison == .orderedSame ? $0.value.id < $1.value.id : comparison == .orderedAscending
        }
        entityEntries = entities.map { entity in
            EntityEntry(
                value: entity,
                fields: [
                    Self.normalize(entity.displayName),
                    Self.normalize(entity.entityID),
                    Self.normalize(entity.secondaryStateText)
                ]
            )
        }.sorted {
            let comparison = $0.value.displayName.localizedStandardCompare($1.value.displayName)
            return comparison == .orderedSame
                ? $0.value.entityID < $1.value.entityID
                : comparison == .orderedAscending
        }
        sourceRevision = revision
    }

    func results(for rawQuery: String) -> Results {
        let query = Self.normalize(rawQuery)
        guard !query.isEmpty else { return Results(areas: [], floors: [], entities: []) }
        // Entries are pre-normalized and pre-sorted, so a query is only
        // substring matching; it performs no per-result locale folding/sort.
        return Results(
            areas: areaEntries.filter { $0.fields.contains { $0.contains(query) } }.map(\.value),
            floors: floorEntries.filter { $0.fields.contains { $0.contains(query) } }.map(\.value),
            entities: entityEntries.filter { $0.fields.contains { $0.contains(query) } }.map(\.value)
        )
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
