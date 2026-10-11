import XCTest

/// Release-independent navigation verification. No Home Assistant connection,
/// Factory login, Runner operation or live write is performed.
final class FactoryWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUnifiedPreconnectionNavigationAndFailClosedState() {
        let app = XCUIApplication()
        app.launchArguments = ["--factory-workspace-acceptance"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "preconnect-service-hub").firstMatch
            .waitForExistence(timeout: 12))

        XCTAssertTrue(app.buttons.matching(identifier: "preconnect-factory").firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(identifier: "preconnect-controlCenter").firstMatch.exists,
                       "Legacy Owner has a single Factory entry in production")
        XCTAssertFalse(app.buttons.matching(identifier: "preconnect-runner").firstMatch.exists,
                       "Legacy Runner has a single Factory entry in production")

        let factory = app.buttons.matching(identifier: "preconnect-factory").firstMatch
        for _ in 0..<5 where !factory.isHittable { app.swipeUp() }
        XCTAssertTrue(factory.isHittable)
        factory.tap()

        XCTAssertTrue(app.navigationBars["Factory"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "factory-no-session").firstMatch
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Factory-Daten aktualisieren"].exists,
                       "Unconfigured Factory must not attempt remote data reads")

        let modules = app.descendants(matching: .any)
            .matching(identifier: "factory-workspace-modules").firstMatch
        for _ in 0..<7 where !modules.exists { app.swipeUp() }
        XCTAssertTrue(modules.exists,
                      "Factory must expose the complete module navigation while disconnected")
    }
}
