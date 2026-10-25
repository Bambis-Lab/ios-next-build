import XCTest

final class FamilyOnboardingUITests: XCTestCase {
    func testMikaFamilyPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--fam-acceptance-mika"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Willkommen, Mika"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Mika Zimmer"].exists)
        XCTAssertTrue(app.staticTexts["Member · keine Owner-Verwaltung"].exists)
        XCTAssertFalse(app.buttons["Factory"].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "FAM10-Mika-synthetic"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testJuliFamilyPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--fam-acceptance-juli"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Willkommen, Juli"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Juli Zimmer"].exists)
        XCTAssertTrue(app.staticTexts["Member · keine Owner-Verwaltung"].exists)
        XCTAssertFalse(app.buttons["Factory"].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "FAM10-Juli-synthetic"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
