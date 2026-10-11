import XCTest

/// S02 static-image acceptance. Requires the pinned Blender images staged in Assets.xcassets.
/// No Factory OAuth, Home Assistant, Runner commands or synthetic live state.
final class FactoryWorldStaticUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFactoryWorldStartsWithEntireCityAndZoomResets() {
        let app = XCUIApplication()
        app.launchArguments = ["--preconnect-ui-acceptance"]
        app.launch()

        let entry = app.buttons.matching(identifier: "preconnect-factory").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 12))
        entry.tap()

        let city = app.descendants(matching: .any)
            .matching(identifier: "factory-world-static-root").firstMatch
        XCTAssertTrue(city.waitForExistence(timeout: 10), "Actual Blender images not loaded")

        let zoom = app.staticTexts["Zoom 100 Prozent"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5), "Static overview not at 100 percent")

        let plus = app.buttons["Factory vergrößern"]
        XCTAssertTrue(plus.exists)
        plus.tap()

        XCTAssertTrue(app.staticTexts["Zoom 125 Prozent"].waitForExistence(timeout: 5),
                      "Zoom did not update")
        app.buttons["Gesamtansicht wiederherstellen"].tap()
        XCTAssertTrue(app.staticTexts["Zoom 100 Prozent"].waitForExistence(timeout: 5),
                      "Reset did not restore whole-city view")
    }
}
