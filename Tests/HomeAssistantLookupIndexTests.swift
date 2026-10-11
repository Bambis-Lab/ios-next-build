import XCTest
@testable import IOSNext

final class HomeAssistantLookupIndexTests: XCTestCase {
    func testDuplicateRegistryRowsDoNotTrapAndLastSnapshotWins() {
        let index = HomeAssistantLookupIndex(
            devices: [
                HomeAssistantDevice(id: "device-1", name: "Old", areaID: "area-old"),
                HomeAssistantDevice(id: "device-1", name: "Current", areaID: "area-current")
            ],
            entityRegistry: [
                HomeAssistantRegistryEntity(entityID: "light.test", deviceID: "device-1", areaID: nil, platform: "old"),
                HomeAssistantRegistryEntity(entityID: "light.test", deviceID: "device-1", areaID: "area-direct", platform: "current")
            ]
        )
        XCTAssertEqual(index.deviceByID["device-1"]?.name, "Current")
        XCTAssertEqual(index.registryByEntityID["light.test"]?.platform, "current")
        XCTAssertEqual(index.resolvedAreaID(for: "light.test"), "area-direct")
        XCTAssertTrue(index.entityIDs(inArea: "area-direct").contains("light.test"))
        XCTAssertFalse(index.entityIDs(inArea: "area-old").contains("light.test"))
        XCTAssertTrue(index.deviceIDs(inArea: "area-current").contains("device-1"))
        XCTAssertFalse(index.deviceIDs(inArea: "area-old").contains("device-1"))
    }

    func testAreaResolutionUsesDeviceAreaOnlyWhenEntityHasNoDirectArea() {
        let index = HomeAssistantLookupIndex(
            devices: [HomeAssistantDevice(id: "device-1", name: "Desk", areaID: "office")],
            entityRegistry: [
                HomeAssistantRegistryEntity(entityID: "switch.desk", deviceID: "device-1", areaID: nil, platform: "fixture")
            ]
        )
        XCTAssertEqual(index.resolvedAreaID(for: "switch.desk"), "office")
        XCTAssertTrue(index.deviceIDs(inArea: "office").contains("device-1"))
    }
}
