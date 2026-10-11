import XCTest
@testable import IOSNext

final class GlobalSearchIndexTests: XCTestCase {
    func testSearchIsCaseAndDiacriticInsensitiveAndPreservesSortOrder() {
        let index = GlobalSearchIndex()
        var local = index
        local.rebuild(
            areas: [
                HomeAssistantArea(id: "huette", name: "Hütte Master"),
                HomeAssistantArea(id: "nico", name: "Nico Zimmer"),
                HomeAssistantArea(id: "wohn", name: "Wohnzimmer")
            ],
            floors: [
                HomeAssistantFloor(id: "upper", name: "Obergeschoss"),
                HomeAssistantFloor(id: "ground", name: "Erdgeschoss")
            ],
            entities: [
                HomeAssistantEntity(entityID: "light.kronach_schrank", state: "on",
                    attributes: ["friendly_name": .string("Schrank")]),
                HomeAssistantEntity(entityID: "switch.desk", state: "off",
                    attributes: ["friendly_name": .string("Schreibtischlampe")])
            ],
            revision: 7
        )

        let result = local.results(for: "HUTTE")
        XCTAssertEqual(result.areas.map(\.id), ["huette"])
        XCTAssertEqual(result.areas.first?.appDisplayName, "Hütte")
        XCTAssertEqual(local.sourceRevision, 7)

        let entities = local.results(for: "LIGHT.KRONACH_SCHRANK").entities
        XCTAssertEqual(entities.map(\.entityID), ["light.kronach_schrank"])

        let state = local.results(for: "aus").entities
        XCTAssertTrue(state.contains(where: { $0.entityID == "switch.desk" }))
    }

    func testRebuildUpdatesChangedNamesAndStates() {
        var index = GlobalSearchIndex()
        let old = HomeAssistantEntity(entityID: "light.room", state: "off",
            attributes: ["friendly_name": .string("Lampe")])
        index.rebuild(areas: [], floors: [], entities: [old], revision: 1)
        XCTAssertEqual(index.results(for: "Lampe").entities.count, 1)
        XCTAssertTrue(index.results(for: "Ein").entities.isEmpty)

        let updated = HomeAssistantEntity(entityID: "light.room", state: "on",
            attributes: ["friendly_name": .string("Deckenlicht")])
        index.rebuild(areas: [], floors: [], entities: [updated], revision: 2)
        XCTAssertTrue(index.results(for: "Lampe").entities.isEmpty)
        XCTAssertEqual(index.results(for: "Deckenlicht").entities.count, 1)
        XCTAssertTrue(index.results(for: "Ein").entities.count == 1)
        XCTAssertEqual(index.sourceRevision, 2)
    }

    func testEmptyAndWhitespaceQueriesReturnNoResults() {
        var index = GlobalSearchIndex()
        index.rebuild(areas: [HomeAssistantArea(id: "a", name: "Raum")],
                      floors: [], entities: [], revision: 0)
        XCTAssertTrue(index.results(for: "").areas.isEmpty)
        XCTAssertTrue(index.results(for: "   ").areas.isEmpty)
    }
}
