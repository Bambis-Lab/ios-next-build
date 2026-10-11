import XCTest

/// Screenshot-only evidence for the 1.6.2 improvements.
/// Runs against the disconnected app + deterministic product acceptance.
/// No backend auth, write operations, account data or mock live claims.
final class ImprovementsGalleryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private var appearance = "light"

    private func capture(_ label: String, app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "No app window for \(label)")
        XCTAssertFalse(app.alerts["Aktion fehlgeschlagen"].exists,
                       "Screenshot contains an unexpected application action error: \(label)")
        let image = app.screenshot()
        XCTAssertGreaterThan(image.pngRepresentation.count, 25_000,
                             "Blank/undersized screenshot: \(label)")
        let evidence = XCTAttachment(screenshot: image)
        evidence.name = "iosnext-162-\(appearance)-\(label)"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func service(_ id: String, app: XCUIApplication) {
        let button = app.buttons.matching(identifier: "preconnect-\(id)").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Missing service: \(id)")
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable, "Service inaccessible: \(id)")
        button.tap()
    }

    private func action(_ title: String, app: XCUIApplication, timeout: TimeInterval = 8) {
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing action: \(title)")
        button.tap()
    }

    private func captureServiceGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["--preconnect-ui-acceptance"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "preconnect-service-hub").firstMatch
            .waitForExistence(timeout: 12))
        capture("01-independent-services-hub", app: app)

        service("chat", app: app)
        XCTAssertTrue(app.buttons["Chatoptionen"].waitForExistence(timeout: 8))
        capture("02-chat-relay-standalone", app: app)
        action("Verschlüsselten Chat einrichten", app: app)
        XCTAssertTrue(app.navigationBars["Chat einrichten"].waitForExistence(timeout: 8))
        capture("03-chat-relay-configuration", app: app)
        action("Abbrechen", app: app)
        action("Chatoptionen", app: app)
        action("Sicherheit", app: app)
        XCTAssertTrue(app.navigationBars["Sicherheit"].waitForExistence(timeout: 8))
        capture("04-chat-security", app: app)
        action("Fertig", app: app)
        action("Schließen", app: app)

        service("controlCenter", app: app)
        XCTAssertTrue(app.navigationBars["Control Center"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "control-center-unconfigured").firstMatch
            .waitForExistence(timeout: 8))
        capture("05-control-center-background-entry", app: app)
        action("Control Center einrichten", app: app)
        XCTAssertTrue(app.navigationBars["Owner-Zugang"].waitForExistence(timeout: 8))
        capture("06-control-center-setup", app: app)
        action("Abbrechen", app: app)
        action("Factory Vorschau", app: app)
        XCTAssertTrue(app.navigationBars["Factory Vorschau"].waitForExistence(timeout: 8))
        capture("07-factory-custom-preview", app: app)
        app.swipeUp()
        capture("08-factory-preview-sections", app: app)
        action("Fertig", app: app)
        action("Schließen", app: app)

        service("runner", app: app)
        XCTAssertTrue(app.navigationBars["Runner"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "runner-unconfigured").firstMatch
            .waitForExistence(timeout: 8))
        capture("09-runner-standalone-background", app: app)
        action("Einrichten", app: app)
        XCTAssertTrue(app.navigationBars["Runner-Zugang"].waitForExistence(timeout: 8))
        capture("10-runner-configuration", app: app)
        action("Abbrechen", app: app)
        action("Schließen", app: app)

        service("factory", app: app)
        XCTAssertTrue(app.navigationBars["Master Factory"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "factory-no-session").firstMatch
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Factory-Daten aktualisieren"].exists,
                       "Unconfigured Factory must not offer refresh")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "factory-credential-unavailable").firstMatch.exists)
        capture("11-factory-command-deck-topology", app: app)
        let configure = app.descendants(matching: .any)
            .matching(identifier: "preconnect-factory-configure").firstMatch
        XCTAssertTrue(configure.waitForExistence(timeout: 8))
        for _ in 0..<4 where !configure.isHittable { app.swipeUp() }
        XCTAssertTrue(configure.isHittable)
        configure.tap()
        XCTAssertTrue(app.navigationBars["Factory verbinden"].waitForExistence(timeout: 8))
        capture("12-factory-oauth-connect", app: app)
        app.swipeUp()
        capture("13-factory-oauth-security", app: app)
    }

    private func captureProductGallery() {
        // Existing acceptance harness renders representative connected screens
        // with deterministic data; they are NOT claims of live backend access.
        let screens = [
            "home", "rooms", "chat", "media", "system",
            "light", "media-detail", "owner", "wireguard"
        ]
        let darkArgument = appearance == "dark" ? ["--product-ui-test-dark"] : []

        for (index, screen) in screens.enumerated() {
            let app = XCUIApplication()
            let visualOwnerArgument = screen == "owner" ? ["--visual-owner-locked"] : []
            app.launchArguments = ["--product-ui-test-screen=\(screen)"] + darkArgument + visualOwnerArgument
            app.launch()
            let root = app.descendants(matching: .any)
                .matching(identifier: "product-acceptance-\(screen)").firstMatch
            XCTAssertTrue(root.waitForExistence(timeout: 12),
                          "Product acceptance screen missing: \(screen)")
            let readiness = app.descendants(matching: .any)
                .matching(identifier: "visual-ready-product-\(screen)-\(appearance)").firstMatch
            XCTAssertTrue(readiness.waitForExistence(timeout: 10),
                          "Appearance didn't become ready: \(screen)/\(appearance)")
            let predicate = NSPredicate(format: "value == %@", "ready")
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: predicate, object: readiness)],
                    timeout: 8
                ),
                .completed,
                "Background visual readiness timed out for \(screen)"
            )
            if screen == "owner" {
                XCTAssertTrue(app.descendants(matching: .any)
                    .matching(identifier: "visual-owner-locked").firstMatch
                    .waitForExistence(timeout: 8))
            }
            if screen == "wireguard" {
                let toggle = app.descendants(matching: .any)
                    .matching(identifier: "wireguard-on-demand").firstMatch
                XCTAssertTrue(toggle.waitForExistence(timeout: 8))
                XCTAssertFalse(toggle.isEnabled, "On-demand must be disabled without a VPN profile")
            }
            capture(String(format: "%02d", index + 14) + "-product-\(screen)", app: app)
            app.terminate()
        }
    }

    func testLightIndependentServices() {
        appearance = "light"
        captureServiceGallery()
    }

    func testDarkIndependentServices() {
        appearance = "dark"
        captureServiceGallery()
    }

    func testLightProductBackgrounds() {
        appearance = "light"
        captureProductGallery()
    }

    func testDarkProductBackgrounds() {
        appearance = "dark"
        captureProductGallery()
    }

    private func launchPreconnection(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preconnect-ui-acceptance"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "preconnect-service-hub").firstMatch.waitForExistence(timeout: 12))
        return app
    }

    private func captureAdditionalStates() {
        // 23: A distinct second half of the standalone Factory surface.
        var app = launchPreconnection()
        service("factory", app: app)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "factory-no-session").firstMatch.waitForExistence(timeout: 8))
        app.swipeUp()
        capture("23-factory-no-session-detail", app: app)
        app.terminate()

        // 24: Owner configuration security details, not another duplicate empty page.
        app = launchPreconnection()
        service("controlCenter", app: app)
        action("Control Center einrichten", app: app)
        XCTAssertTrue(app.navigationBars["Owner-Zugang"].waitForExistence(timeout: 8))
        app.swipeUp()
        capture("24-control-center-setup-security", app: app)
        app.terminate()

        // 25: Deterministically reproduce simulator Keychain read failure.
        // No production Keychain reads or real Factory operations occur.
        app = launchPreconnection(extra: ["--visual-factory-keychain-error"])
        service("factory", app: app)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "factory-credential-unavailable").firstMatch
            .waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Factory-Daten aktualisieren"].exists)
        capture("25-factory-keychain-error", app: app)
        app.terminate()

        // 26: Visually check offline runner handling without connecting anywhere.
        app = launchPreconnection(extra: ["--visual-runner-offline"])
        service("runner", app: app)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "runner-offline").firstMatch
            .waitForExistence(timeout: 8))
        capture("26-runner-offline", app: app)
        app.terminate()

        // 27: Explicit simulated OAuth rejection. The test never opens a browser.
        app = launchPreconnection(extra: ["--visual-factory-oauth-error"])
        service("factory", app: app)
        let connect = app.descendants(matching: .any)
            .matching(identifier: "preconnect-factory-configure").firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        for _ in 0..<4 where !connect.isHittable { app.swipeUp() }
        XCTAssertTrue(connect.isHittable)
        connect.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "visual-oauth-error").firstMatch
            .waitForExistence(timeout: 8))
        app.swipeUp()
        capture("27-factory-oauth-rejection", app: app)
        app.terminate()

        // 28: Verify the inactive VPN on-demand control visually and semantically.
        app = XCUIApplication()
        let darkArgument = appearance == "dark" ? ["--product-ui-test-dark"] : []
        app.launchArguments = ["--product-ui-test-screen=wireguard"] + darkArgument
        app.launch()
        let toggle = app.descendants(matching: .any)
            .matching(identifier: "wireguard-on-demand").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 12))
        XCTAssertFalse(toggle.isEnabled, "No configured VPN must not have enabled on-demand")
        app.swipeUp()
        capture("28-wireguard-offline-security", app: app)
        app.terminate()
    }

    func testLightAdditionalStates() {
        appearance = "light"
        captureAdditionalStates()
    }

    func testDarkAdditionalStates() {
        appearance = "dark"
        captureAdditionalStates()
    }
}
