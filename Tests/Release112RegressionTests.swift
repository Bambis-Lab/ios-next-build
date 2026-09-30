import XCTest
@testable import IOSNext

final class Release112RegressionTests: XCTestCase {
    func testBuellerDeviceServiceIsFiltered() {
        XCTAssertTrue(FireTVPresentationPolicy.isSystemIdentity("BuellerDeviceService"))
        XCTAssertTrue(FireTVPresentationPolicy.isSystemIdentity("com.amazon.device.settings"))
        XCTAssertFalse(FireTVPresentationPolicy.isSystemIdentity("com.netflix.ninja"))
    }

    func testOffFireTVDoesNotExposeForegroundAppOrNowPlaying() {
        let entity = HomeAssistantEntity(
            entityID: "media_player.fire_tv_companion",
            state: "off",
            attributes: [
                "foreground_app": .string("BuellerDeviceService"),
                "foreground_package": .string("com.amazon.device.bueller"),
                "media_title": .string("BuellerDeviceService")
            ]
        )

        XCTAssertEqual(FireTVPresentationState.resolve(entity: entity), .off)
        XCTAssertNil(FireTVPresentationPolicy.visibleForegroundApp(for: entity))
        XCTAssertFalse(FireTVPresentationPolicy.shouldShowNowPlaying(for: entity))
        XCTAssertFalse(FireTVPresentationPolicy.shouldShowTransport(for: entity))
    }

    func testPlayingUserAppRemainsVisible() {
        let entity = HomeAssistantEntity(
            entityID: "media_player.fire_tv_companion",
            state: "playing",
            attributes: [
                "foreground_app": .string("Netflix"),
                "foreground_package": .string("com.netflix.ninja"),
                "media_title": .string("Testfilm")
            ]
        )

        XCTAssertEqual(FireTVPresentationPolicy.visibleForegroundApp(for: entity), "Netflix")
        XCTAssertTrue(FireTVPresentationPolicy.shouldShowNowPlaying(for: entity))
    }

    func testLegacyCommanderVersionIsNotPublishedAsMasterRuntimeVersion() {
        var live = CommanderLiveViewState()
        live.snapshot = CommanderSnapshot(
            state: .active,
            online: true,
            version: "0.2.51",
            uptimeSeconds: 120,
            cpuPercent: 4.2,
            memoryPercent: 9.3,
            activeCount: 1
        )
        live.connection = .live

        let master = MasterRuntimeSnapshot(status: nil, liveState: live)
        XCTAssertNil(master.version)
        XCTAssertEqual(master.availability, .ready)
        XCTAssertEqual(master.activeOperations, 1)
    }
}
