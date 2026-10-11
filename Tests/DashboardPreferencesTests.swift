import XCTest
@testable import IOSNext

@MainActor
final class DashboardPreferencesTests: XCTestCase {
    func testVisibilityAndOrderingPersistPerProfile() {
        let profile = "test-\(UUID().uuidString)"
        let store = DashboardPreferencesStore(profileID: profile)
        store.ensureKnownIDs(["timo", "huette", "outdoors"])
        store.toggleVisibility("huette", visible: false)
        store.move("outdoors", by: -2, availableIDs: ["timo", "huette", "outdoors"])
        XCTAssertFalse(store.isVisible("huette"))
        XCTAssertLessThan(store.rank(of: "outdoors"), store.rank(of: "timo"))

        let restored = DashboardPreferencesStore(profileID: profile)
        XCTAssertFalse(restored.isVisible("huette"))
        XCTAssertLessThan(restored.rank(of: "outdoors"), restored.rank(of: "timo"))
        restored.reset()
    }

    func testMovingAtEdgesIsNoOp() {
        let profile = "test-\(UUID().uuidString)"
        let store = DashboardPreferencesStore(profileID: profile)
        store.ensureKnownIDs(["a", "b"])
        let before = store.orderedIDs
        store.move("a", by: -1, availableIDs: ["a", "b"])
        XCTAssertEqual(store.orderedIDs, before)
        store.move("b", by: 1, availableIDs: ["a", "b"])
        XCTAssertEqual(store.orderedIDs, before)
        store.reset()
    }
}
