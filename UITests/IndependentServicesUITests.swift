import XCTest

/// Independent pre-connection smoke test. No credentials, backend or Home
/// Assistant server is required, and the test never executes a write action.
final class IndependentServicesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tapService(_ name: String, in app: XCUIApplication) {
        let item = app.buttons.matching(identifier: "preconnect-\(name)").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing service \(name)")
        if !item.isHittable {
            for _ in 0..<4 where !item.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(item.isHittable, "Service entry is not tappable: \(name)")
        item.tap()
    }

    func testAllServiceEntriesWorkWithoutHomeAssistant() {
        let app = XCUIApplication()
        app.launchArguments = ["--preconnect-ui-acceptance"]
        app.launch()

        let hub = app.descendants(matching: .any)
            .matching(identifier: "preconnect-service-hub").firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10), "Independent service hub did not load")

        for name in ["ha", "chat", "controlCenter", "runner", "factory"] {
            let entry = app.buttons.matching(identifier: "preconnect-\(name)").firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5),
                          "Preconnection service not accessible: \(name)")
        }

        tapService("chat", in: app)
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 8),
                      "Chats inbox cannot be opened before HA configuration")
        XCTAssertTrue(app.buttons["chat-inbox-settings"].waitForExistence(timeout: 5),
                      "Chats inbox has no setup entry")
        app.buttons["chat-inbox-settings"].tap()
        XCTAssertTrue(app.navigationBars["Chat-Einstellungen"].waitForExistence(timeout: 8),
                      "Gear must open dedicated Chat settings, not a conversation")
        XCTAssertFalse(app.textFields["chat-composer-field"].exists,
                       "Settings accidentally displayed the message composer")
        XCTAssertFalse(app.buttons["Chatoptionen"].exists,
                       "Settings accidentally navigated into ChatView")
        let done = app.buttons["Fertig"]
        XCTAssertTrue(done.waitForExistence(timeout: 8),
                      "Chat settings must be dismissible")
        done.tap()
        let closeChat = app.buttons["Schließen"]
        XCTAssertTrue(closeChat.waitForExistence(timeout: 8),
                      "Standalone chat inbox is missing its close button")
        closeChat.tap()

        tapService("controlCenter", in: app)
        XCTAssertTrue(app.navigationBars["Control Center"].waitForExistence(timeout: 8),
                      "Control Center cannot be opened before HA configuration")
        let ownerSetup = app.buttons["Control Center einrichten"]
        XCTAssertTrue(ownerSetup.waitForExistence(timeout: 5),
                      "Control Center has no setup action")
        app.buttons["Schließen"].tap()

        tapService("runner", in: app)
        XCTAssertTrue(app.navigationBars["Runner"].waitForExistence(timeout: 8),
                      "Runner cannot be opened before HA configuration")
        XCTAssertTrue(app.buttons["Einrichten"].waitForExistence(timeout: 5),
                      "Runner setup is not accessible")
        app.buttons["Schließen"].tap()

        tapService("factory", in: app)
        XCTAssertTrue(app.navigationBars["Master Factory"].waitForExistence(timeout: 8),
                      "Factory cannot be opened before HA configuration")
        let configuration = app.descendants(matching: .any)
            .matching(identifier: "preconnect-factory-configure").firstMatch
        XCTAssertTrue(configuration.waitForExistence(timeout: 5),
                      "Factory connection is missing")
        configuration.tap()
        XCTAssertTrue(app.navigationBars["Factory verbinden"].waitForExistence(timeout: 8),
                      "Factory OAuth setup does not open")
    }
}
