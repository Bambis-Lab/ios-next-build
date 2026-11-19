import XCTest

/// Normal production root on a newly created, disposable simulator.
final class CleanInstallUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshLaunchAndInvalidHAAddressStayUnauthenticated() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()

        let connect = app.buttons["preconnect-ha"]
        XCTAssertTrue(connect.waitForExistence(timeout: 20))
        XCTAssertTrue(connect.isHittable)
        XCTAssertFalse(app.buttons["preconnect-controlCenter"].exists)
        XCTAssertFalse(app.buttons["preconnect-runner"].exists)
        XCTAssertFalse(app.buttons["system-owner-control"].exists)

        let landing = XCTAttachment(screenshot: app.screenshot())
        landing.name = "R80-clean-install-landing"
        landing.lifetime = .keepAlways
        add(landing)

        connect.tap()
        XCTAssertTrue(app.navigationBars["Verbinden"].waitForExistence(timeout: 8))
        let field = app.textFields["https://homeassistant.local:8123"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText("ftp://invalid.invalid")
        let login = app.buttons["Sicher mit Home Assistant anmelden"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        if !login.isHittable { app.swipeUp() }
        XCTAssertTrue(login.isHittable)
        login.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Bitte eine gültige HTTPS-"
        )).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Verbinden"].exists)

        let rejection = XCTAttachment(screenshot: app.screenshot())
        rejection.name = "R80-clean-install-invalid-address"
        rejection.lifetime = .keepAlways
        add(rejection)

        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(connect.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["preconnect-controlCenter"].exists)
        XCTAssertFalse(app.buttons["preconnect-runner"].exists)
        XCTAssertFalse(app.buttons["system-owner-control"].exists)
    }
}
