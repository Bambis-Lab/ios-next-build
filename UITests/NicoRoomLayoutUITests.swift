import XCTest

final class NicoRoomLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func start(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--nico-room-layout-acceptance"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Nico Zimmer"].waitForExistence(timeout: 12))
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }

    func testCompactRoomTilesAndCabinetColorLongPress() {
        let app = start()
        let cabinet = app.descendants(matching: .any)
            .matching(identifier: "nico-primary-light.kronach_schrank").firstMatch
        XCTAssertTrue(cabinet.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "nico-micro-Schreibtischlampe").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "nico-micro-Prisma").firstMatch.exists)
        XCTAssertFalse(app.buttons["Lichtsteuerung Schrank"].exists,
                       "No separate palette button is permitted")

        for _ in 0..<3 where !cabinet.isHittable { app.swipeUp() }
        XCTAssertTrue(cabinet.isHittable)
        capture("Nico-Zimmer-neue-Lichtkacheln-Light", app: app)

        let label = app.staticTexts["Schrank"].firstMatch
        XCTAssertTrue(label.exists)
        label.press(forDuration: 0.8)
        XCTAssertTrue(app.navigationBars["Schrank"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Farbe"].waitForExistence(timeout: 4))
        capture("Schrank-Langdruck-Farbsteuerung", app: app)
    }

    func testDarkCompactRoomLayout() {
        let app = start(["--nico-dark-acceptance"])
        let cabinet = app.descendants(matching: .any)
            .matching(identifier: "nico-primary-light.kronach_schrank").firstMatch
        for _ in 0..<3 where !cabinet.isHittable { app.swipeUp() }
        XCTAssertTrue(cabinet.isHittable)
        capture("Nico-Zimmer-neue-Lichtkacheln-Dark", app: app)
    }

    func testAccessibilityTypeKeepsActionsAccessible() {
        let app = start(["--nico-large-type-acceptance"])
        let cabinet = app.descendants(matching: .any)
            .matching(identifier: "nico-primary-light.kronach_schrank").firstMatch
        XCTAssertTrue(cabinet.waitForExistence(timeout: 8))
        let desk = app.descendants(matching: .any)
            .matching(identifier: "nico-micro-Schreibtischlampe").firstMatch
        XCTAssertTrue(desk.exists)
        capture("Nico-Zimmer-Dynamic-Type", app: app)
    }
}
