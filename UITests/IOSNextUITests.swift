import CoreGraphics
import Foundation
import XCTest
import UIKit

final class IOSNextUITests: XCTestCase {
    private var app: XCUIApplication!
    private var accessibilityRestore: (path: [String], toggle: String, enabled: Bool)?
    private let screens = ["home", "rooms", "chat", "media", "system", "light", "media-detail", "owner"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        if let original = accessibilityRestore {
            _ = setAccessibilityPreference(path: original.path, toggle: original.toggle, enabled: original.enabled, recordRestore: false)
            accessibilityRestore = nil
        }
        // A failed XCUIApplication.launch() must not strand its process.
        // Ownership is set before launch(), including its error path.
        if let application = app, application.state != .notRunning {
            application.terminate()
        }
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(_ screen: String, extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--product-ui-test-screen=\(screen)"] + extraArguments
        app = application
        NSLog("G99-01 launch begin screen=\(screen) arguments=\(application.launchArguments) orientation=\(XCUIDevice.shared.orientation.rawValue)")
        application.launch()
        NSLog("G99-01 launch end screen=\(screen) appState=\(application.state.rawValue)")
        let root = application.descendants(matching: .any)
            .matching(identifier: "product-acceptance-\(screen)")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8), "Product screen did not render: \(screen)")
        waitForVisualReady(
            screen,
            dark: extraArguments.contains("--product-ui-test-dark"),
            in: application,
            timeout: 8
        )
        app = application
        return application
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        var accepted: XCUIScreenshot?

        for attempt in 1...4 {
            let screenshot = app.screenshot()
            if isValidVisualScreenshot(screenshot) {
                accepted = screenshot
                break
            }

            if attempt < 4 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            }
        }

        guard let screenshot = accepted else {
            XCTFail("Screenshot remained blank/flat after retries: \(name)")
            return
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func isValidVisualScreenshot(_ screenshot: XCUIScreenshot) -> Bool {
        guard let source = UIImage(data: screenshot.pngRepresentation)?.cgImage else {
            return false
        }

        let sampleWidth = 80
        let aspect = Double(source.height) / Double(max(source.width, 1))
        let sampleHeight = max(80, min(180, Int((Double(sampleWidth) * aspect).rounded())))
        let bytesPerRow = sampleWidth * 4
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var count = 0
        var sum = 0.0
        var sumSquares = 0.0
        var nearBlack = 0
        var nearWhite = 0
        var minLuma = 1.0
        var maxLuma = 0.0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[offset]) / 255.0
            let g = Double(pixels[offset + 1]) / 255.0
            let b = Double(pixels[offset + 2]) / 255.0
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

            count += 1
            sum += luma
            sumSquares += luma * luma
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
            if luma < 0.02 { nearBlack += 1 }
            if luma > 0.98 { nearWhite += 1 }
        }

        guard count > 0 else { return false }

        let mean = sum / Double(count)
        let variance = max(0, sumSquares / Double(count) - mean * mean)
        let deviation = sqrt(variance)
        let blackRatio = Double(nearBlack) / Double(count)
        let whiteRatio = Double(nearWhite) / Double(count)
        let dynamicRange = maxLuma - minLuma

        let blank = mean < 0.015 || mean > 0.985
        let flat = deviation < 0.025 || dynamicRange < 0.12
        let dominated = (blackRatio > 0.985 || whiteRatio > 0.985) && deviation < 0.07

        return !(blank || flat || dominated)
    }

    private func tapWhenVisible(
        _ element: XCUIElement,
        in application: XCUIApplication,
        label: String,
        timeout: TimeInterval = 4
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(label) did not exist")

        let hittable = NSPredicate(format: "hittable == true")
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: hittable, object: element)],
            timeout: timeout
        )
        if result == .completed {
            element.tap()
            return
        }

        let window = application.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 2), "Application window did not exist")
        let visibleFrame = element.frame.intersection(window.frame)
        XCTAssertFalse(
            visibleFrame.isNull || visibleFrame.isEmpty,
            "\(label) exists but is outside the visible application window"
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func captureInteractionFailure(
        _ label: String,
        in application: XCUIApplication,
        element: XCUIElement? = nil,
        scrollContainer: XCUIElement? = nil
    ) {
        let window = application.windows.firstMatch
        var details = [
            "test=\(name)",
            "label=\(label)",
            "application_state=\(application.state.rawValue)",
            "launch_arguments=\(application.launchArguments.joined(separator: " "))",
            "orientation=\(XCUIDevice.shared.orientation.rawValue)",
            "window_exists=\(window.exists)",
            "window_frame=\(window.exists ? String(describing: window.frame) : "absent")",
            "fixture_fallback_visible=\(application.staticTexts["Live-HA-Fixture nicht geladen"].exists)"
        ]
        if let element {
            details += [
                "element_identifier=\(element.identifier)",
                "element_type=\(element.elementType.rawValue)",
                "element_exists=\(element.exists)",
                "element_enabled=\(element.exists && element.isEnabled)",
                "element_hittable=\(element.exists && element.isHittable)",
                "element_frame=\(element.exists ? String(describing: element.frame) : "absent")"
            ]
        }
        if let scrollContainer {
            details += [
                "scroll_type=\(scrollContainer.elementType.rawValue)",
                "scroll_identifier=\(scrollContainer.identifier)",
                "scroll_frame=\(scrollContainer.frame)"
            ]
        }
        let metadata = XCTAttachment(string: details.joined(separator: "\n"))
        metadata.name = "G99-01 metadata - \(label)"
        metadata.lifetime = .keepAlways
        add(metadata)
        NSLog("G99-01 failure \(details.joined(separator: " | "))")

        let hierarchy = XCTAttachment(string: application.debugDescription)
        hierarchy.name = "UI hierarchy - \(label)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "UI failure - \(label)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func scrollUpUntilHittable(
        _ element: XCUIElement,
        in application: XCUIApplication,
        label: String,
        maxSwipes: Int = 4,
        containerIdentifier: String? = nil
    ) {
        guard element.waitForExistence(timeout: 3) else {
            captureInteractionFailure(label, in: application, element: element)
            XCTFail("\(label) did not exist")
            return
        }
        if element.isHittable { return }

        let namedContainer = containerIdentifier.map {
            application.descendants(matching: .any).matching(identifier: $0).firstMatch
        }
        let scrollContainer: XCUIElement
        if let namedContainer, namedContainer.waitForExistence(timeout: 2) {
            scrollContainer = namedContainer
        } else if application.scrollViews.firstMatch.exists {
            scrollContainer = application.scrollViews.firstMatch
        } else if application.tables.firstMatch.exists {
            scrollContainer = application.tables.firstMatch
        } else if application.collectionViews.firstMatch.exists {
            scrollContainer = application.collectionViews.firstMatch
        } else {
            captureInteractionFailure(label, in: application, element: element)
            XCTFail("\(label) has no identifiable scrollable container")
            return
        }

        for _ in 0..<maxSwipes {
            if element.isHittable { return }
            let before = element.frame
            scrollContainer.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            NSLog("IPH-SCROLL \(label): before=\(before) after=\(element.frame) container=\(scrollContainer.frame)")
        }

        if !element.isHittable {
            captureInteractionFailure(label, in: application, element: element, scrollContainer: scrollContainer)
            XCTFail("\(label) not hittable after \(maxSwipes) scoped swipes; frame=\(element.frame), enabled=\(element.isEnabled), container=\(scrollContainer.frame)")
        }
    }

    private func waitForVisualReady(
        _ screen: String,
        dark: Bool,
        in application: XCUIApplication,
        timeout: TimeInterval
    ) {
        let appearance = dark ? "dark" : "light"
        let probe = application.descendants(matching: .any)
            .matching(identifier: "visual-ready-product-\(screen)-\(appearance)")
            .firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: timeout), "Visual-ready probe missing: \(screen) \(appearance)")
        let predicate = NSPredicate(format: "value == %@", "ready")
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: probe)],
            timeout: timeout
        )
        XCTAssertEqual(result, .completed, "Visual frame did not settle: \(screen) \(appearance)")
    }

    private func setOrientation(_ orientation: UIDeviceOrientation, in application: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let expectsLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let deadline = Date().addingTimeInterval(6)
        var lastFrame = CGRect.zero
        var stableSamples = 0

        while Date() < deadline {
            let frame = application.windows.firstMatch.frame
            if frame.width > 0, frame.height > 0 {
                let isLandscape = frame.width > frame.height
                let sameSize = abs(frame.width - lastFrame.width) < 0.5
                    && abs(frame.height - lastFrame.height) < 0.5

                if isLandscape == expectsLandscape {
                    stableSamples = sameSize ? stableSamples + 1 : 1
                    if stableSamples >= 4 {
                        return
                    }
                } else {
                    stableSamples = 0
                }

                lastFrame = frame
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Orientation did not settle: \(orientation.rawValue)")
    }

    private func captureAllProductScreens(
        prefix: String,
        dark: Bool,
        orientation: UIDeviceOrientation? = nil
    ) {
        for screen in screens {
            let arguments = dark ? ["--product-ui-test-dark"] : []
            let application = launch(screen, extraArguments: arguments)

            if let orientation {
                setOrientation(orientation, in: application)
                waitForVisualReady(screen, dark: dark, in: application, timeout: 6)
            }

            attachScreenshot("\(prefix)-\(screen)", app: application)
        }
    }


    func testHomeUsesApprovedFourCardHierarchyAndOutdoorResources() {
        let application = launch("home")
        for identifier in ["home-shortcut-timo", "home-shortcut-huette", "home-shortcut-outdoors", "home-shortcut-ground-floor"] {
            let element = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 4), "Missing Home shortcut: \(identifier)")
        }

        let outdoors = application.descendants(matching: .any)
            .matching(identifier: "home-shortcut-outdoors")
            .firstMatch
        scrollUpUntilHittable(outdoors, in: application, label: "Außenbereich", maxSwipes: 4)
        outdoors.tap()

        for identifier in ["outdoor-resource-pool", "outdoor-resource-lawn", "outdoor-resource-mower"] {
            let resource = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(resource.waitForExistence(timeout: 4), "Missing outdoor resource: \(identifier)")
        }
    }

    func testPrimaryProductScreensRenderLightAndDark() {
        captureAllProductScreens(prefix: "product-light", dark: false)
        captureAllProductScreens(prefix: "product-dark", dark: true)

        // Four additional screenshots of the actual redesigned pages with
        // synthetic data. Safe for iPhone CI without Owner/Runner credentials.
        for screen in ["runner", "projects"] {
            for dark in [false, true] {
                let mode = dark ? "dark" : "light"
                let arguments = dark ? ["--product-ui-test-dark"] : []
                let application = launch(screen, extraArguments: arguments)
                if screen == "runner" {
                    XCTAssertTrue(
                        application.staticTexts["Kapazität"].waitForExistence(timeout: 8),
                        "Runner dashboard capacity section did not render"
                    )
                    XCTAssertTrue(
                        application.staticTexts["Laufende Jobs"].waitForExistence(timeout: 5),
                        "Runner fixture did not render active jobs"
                    )
                } else {
                    XCTAssertTrue(
                        application.staticTexts["Deine Projekte"].waitForExistence(timeout: 8),
                        "Owner Projects screen did not render"
                    )
                    let populatedProject = application.descendants(matching: .any)
                        .matching(NSPredicate(format: "label CONTAINS[c] %@", "Master Control Factory"))
                        .firstMatch
                    XCTAssertTrue(
                        populatedProject.waitForExistence(timeout: 5),
                        "Project fixture is not populated or accessible"
                    )
                }
                attachScreenshot("g99-fix03-\(screen)-\(mode)", app: application)
            }
        }
    }

    func testNativeTabNavigationAndMediaDetail() throws {
        let application = launch("home")
        if application.tabBars.buttons["Medien"].waitForExistence(timeout: 2) {
            let mediaTab = application.tabBars.buttons["Medien"]
            XCTAssertTrue(mediaTab.isHittable)
            mediaTab.tap()
        } else {
            let mediaRow = application.descendants(matching: .any)
                .matching(identifier: "app-tab-media")
                .firstMatch
            guard mediaRow.waitForExistence(timeout: 2) else {
                throw XCTSkip("Adaptive media navigation control not available on this device.")
            }
            mediaRow.tap()
        }

        let mediaContent = application.staticTexts["Weitere Medien"].firstMatch
        let mediaHeading = application.navigationBars["Medien"].firstMatch
        let mediaSummary = application.descendants(matching: .any)
            .matching(identifier: "media-active-summary")
            .firstMatch
        if !mediaSummary.waitForExistence(timeout: 8) {
            captureInteractionFailure("Media tab content", in: application, element: mediaSummary)
            XCTFail("Media tab did not render the expected active-player summary; heading=\(mediaHeading.exists), otherMedia=\(mediaContent.exists)")
            return
        }
        XCTAssertTrue(mediaHeading.exists || mediaSummary.isHittable, "Media content exists but neither title nor summary is accessible")

        let fireTV = application.descendants(matching: .any)
            .matching(identifier: "fire-tv-companion-card-media_player.fire_tv_companion")
            .firstMatch
        XCTAssertTrue(
            fireTV.waitForExistence(timeout: 8),
            "Media tab did not expose the Fire TV Companion V2 card"
        )
        scrollUpUntilHittable(fireTV, in: application, label: "Fire TV Companion V2 card")
        guard fireTV.isHittable else { return }
        fireTV.press(forDuration: 0.8)

        XCTAssertTrue(application.navigationBars["Fire TV"].waitForExistence(timeout: 5), "Fire TV V2 control sheet did not open")
        XCTAssertTrue(application.buttons["Fertig"].waitForExistence(timeout: 3), "Fire TV V2 control sheet cannot be dismissed")
        XCTAssertTrue(application.buttons["Pause"].waitForExistence(timeout: 3), "Fire TV playback controls are missing")
        attachScreenshot("product-fire-tv-companion-detail", app: application)
        application.buttons["Fertig"].tap()
        XCTAssertTrue(application.navigationBars["Medien"].waitForExistence(timeout: 3), "Media screen did not return after closing Fire TV")
    }

    func testChatComposerInteraction() {
        let application = launch("chat")
        XCTAssertTrue(application.navigationBars["Chats"].waitForExistence(timeout: 5),
                      "New chats inbox must be the root of the Chat tab")
        XCTAssertTrue(application.buttons["chat-inbox-family"].waitForExistence(timeout: 5),
                      "Synthetic five-person family group row missing")
        let mika = application.buttons["chat-inbox-person-Mika"].firstMatch
        XCTAssertTrue(mika.waitForExistence(timeout: 5), "Verified preview contact not visible")
        mika.tap()
        let field = application.textFields["chat-composer-field"].firstMatch
        tapWhenVisible(field, in: application, label: "Chat composer")
        application.typeText("Hallo aus XCUITest")
        XCTAssertEqual(field.value as? String, "Hallo aus XCUITest")

        let sendButton = application.buttons["Nachricht senden"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        XCTAssertTrue(sendButton.isEnabled)
        attachScreenshot("product-chat-composer", app: application)
    }

    func testLightSliderInteraction() {
        let application = launch("light")
        let power = application.buttons["light-power-button"]
        XCTAssertTrue(power.waitForExistence(timeout: 3))
        XCTAssertTrue(power.isEnabled)

        let brightness = application.sliders["light-brightness-slider"]
        XCTAssertTrue(brightness.waitForExistence(timeout: 5), "Brightness slider missing")
        XCTAssertTrue(brightness.isEnabled, "Brightness slider is disabled in the preview fixture")
        scrollUpUntilHittable(
            brightness,
            in: application,
            label: "Brightness slider",
            containerIdentifier: "entity-detail-scroll"
        )
        guard brightness.isHittable else { return }
        let before = brightness.value as? String
        brightness.adjust(toNormalizedSliderPosition: 0.28)
        let after = brightness.value as? String
        XCTAssertNotEqual(before, after)
        attachScreenshot("product-light-slider-interaction", app: application)
    }

    func testOwnerSafeEntryState() {
        let ownerApplication = launch("owner")
        let unconfigured = ownerApplication.descendants(matching: .any)
            .matching(identifier: "control-center-unconfigured").firstMatch
        XCTAssertTrue(unconfigured.waitForExistence(timeout: 4), "Owner unconfigured state is missing")
        XCTAssertTrue(ownerApplication.buttons["control-center-setup-action"].waitForExistence(timeout: 3), "Owner setup action is missing")
        attachScreenshot("product-owner-entry", app: ownerApplication)
    }

    func testRemovedVPNFeatureIsAbsentFromSystem() {
        let application = launch("system")
        let removedEntry = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "WireGuard"))
            .firstMatch
        XCTAssertFalse(removedEntry.exists, "Removed WireGuard navigation is still visible")
        let management = application.descendants(matching: .any)
            .matching(identifier: "system-live-operations").firstMatch
        XCTAssertTrue(management.waitForExistence(timeout: 4), "System management content missing")
        attachScreenshot("product-system-no-wireguard", app: application)
    }

    func testLiveOperationsSafeEntryState() {
        let application = launch("system")
        let liveOperations = application.descendants(matching: .any)
            .matching(identifier: "system-live-operations")
            .firstMatch
        scrollUpUntilHittable(liveOperations, in: application, label: "Live Operations", maxSwipes: 4)
        guard liveOperations.isHittable else { return }
        liveOperations.tap()
        XCTAssertTrue(
            application.staticTexts["Live Operations nicht eingerichtet"].waitForExistence(timeout: 4),
            "Live Operations did not expose the safe unconfigured state"
        )
        attachScreenshot("product-live-operations-unconfigured", app: application)
    }

    private func accessibilityState(in application: XCUIApplication) -> String {
        let root = application.descendants(matching: .any)
            .matching(identifier: "product-acceptance-home")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        return root.value as? String ?? ""
    }

    // Xcode 27 simctl does not expose Reduce Motion / Reduce Transparency.
    // This driver taps actual controls in the installed iOS Settings application.
    private func settingsValue(_ element: XCUIElement) -> Bool? {
        guard element.exists else { return nil }
        let raw = String(describing: element.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "on", "enabled", "true", "ein"].contains(raw) { return true }
        if ["0", "off", "disabled", "false", "aus"].contains(raw) { return false }
        return nil
    }

    private func settingsTap(_ title: String, in settings: XCUIApplication) -> Bool {
        for attempt in 0..<5 {
            let choices = [
                settings.cells.containing(.staticText, identifier: title).firstMatch,
                settings.buttons[title].firstMatch,
                settings.staticTexts[title].firstMatch
            ]
            if let choice = choices.first(where: { $0.exists && $0.isHittable }) {
                choice.tap()
                return true
            }
            if attempt < 4 { settings.swipeUp() }
        }
        return false
    }

    @discardableResult
    private func setAccessibilityPreference(
        path: [String],
        toggle: String,
        enabled: Bool,
        recordRestore: Bool = true
    ) -> Bool {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        // Settings can restore the previously visited detail screen.
        for _ in 0..<5 {
            if settings.navigationBars["Settings"].exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        for segment in path {
            guard settingsTap(segment, in: settings) else {
                let attachment = XCTAttachment(string: settings.debugDescription)
                attachment.name = "Settings navigation missing - \(segment)"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTFail("Cannot navigate real Settings > \(path.joined(separator: " > "))")
                return false
            }
        }
        // Settings can expose the same switch by its visible label or by an
        // internal accessibility identifier (e.g. REDUCE_MOTION). Re-resolve
        // the control after interaction instead of reading a stale snapshot.
        func currentSwitch() -> XCUIElement {
            let row = settings.cells.containing(.staticText, identifier: toggle).firstMatch
            let named = settings.switches[toggle].firstMatch
            if named.exists { return named }
            if row.exists, row.switches.firstMatch.exists { return row.switches.firstMatch }
            return settings.switches.firstMatch
        }
        func observedValue() -> Bool? {
            settingsValue(currentSwitch())
        }
        let control = currentSwitch()
        guard control.waitForExistence(timeout: 5), let original = observedValue() else {
            let attachment = XCTAttachment(string: settings.debugDescription)
            attachment.name = "Settings switch missing - \(toggle)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Real system switch \(toggle) missing or unparseable")
            return false
        }
        if original != enabled {
            if recordRestore {
                accessibilityRestore = (path: path, toggle: toggle, enabled: original)
            }
            guard control.isHittable else {
                XCTFail("System switch \(toggle) is not hittable")
                return false
            }
            control.tap()
        }
        // UIKit/Settings accessibility values may lag the tap and can be
        // refreshed asynchronously. Poll the actual Settings switch state,
        // never infer success from tap() returning.
        let deadline = Date().addingTimeInterval(8)
        var actual = observedValue()
        while actual != enabled && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            actual = observedValue()
        }
        guard actual == enabled else {
            let attachment = XCTAttachment(string: settings.debugDescription)
            attachment.name = "Settings switch did not change - \(toggle)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("System switch \(toggle) failed to reach requested value; observed=\(String(describing: actual))")
            return false
        }
        NSLog("G99 system Settings verified \(toggle)=\(enabled)")
        settings.terminate()
        return true
    }

    func testUnverifiedFamilyHomeDoesNotExposePersonalizedShortcuts() {
        // An explicitly unverified family fixture must not inherit Nico's Home.
        let application = launch("home", extraArguments: ["--product-ui-test-unverified"])
        XCTAssertTrue(
            application.staticTexts["Familienprofil noch nicht bestätigt"].waitForExistence(timeout: 6),
            "Unverified family account must see neutral Rooms instead of personalized Home"
        )
        let personalized = application.descendants(matching: .any)
            .matching(identifier: "home-shortcut-timo").firstMatch
        XCTAssertFalse(personalized.exists, "Unverified family account must not inherit Nico shortcuts")
        attachScreenshot("family-unverified-rooms-home", app: application)
    }

    func testAccessibilityCoreScreenRenders() {
        let application = launch("home")
        XCTAssertTrue(application.staticTexts["Häufig genutzt"].waitForExistence(timeout: 3))
        _ = accessibilityState(in: application)
        attachScreenshot("product-accessibility-current-system-settings", app: application)
    }

    // Genuine system settings only; no synthetic launch arguments.
    func testDynamicTypeAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("dynamicTypeAccessibility=true"),
                      "Simulator content_size must be an accessibility category")
        attachScreenshot("product-accessibility-dynamic-type-xxxl", app: application)
    }

    func testReduceMotionAccessibilityState() {
        guard setAccessibilityPreference(path: ["Accessibility", "Motion"],
                                         toggle: "Reduce Motion", enabled: true) else { return }
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("reduceMotion=true"),
                      "System Reduce Motion not observed by SwiftUI")
        attachScreenshot("product-accessibility-reduce-motion", app: application)
    }

    func testReduceTransparencyAccessibilityState() {
        guard setAccessibilityPreference(path: ["Accessibility", "Display & Text Size"],
                                         toggle: "Reduce Transparency", enabled: true) else { return }
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("reduceTransparency=true"),
                      "System Reduce Transparency not observed by SwiftUI")
        attachScreenshot("product-accessibility-reduce-transparency", app: application)
    }

    func testIncreaseContrastAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("increasedContrast=true"),
                      "Simulator increase_contrast must be enabled before launch")
        attachScreenshot("product-accessibility-increase-contrast", app: application)
    }

    func testIPadPortraitLandscapeCoreScreens() {
        captureAllProductScreens(prefix: "ipad-portrait-light", dark: false, orientation: .portrait)
        captureAllProductScreens(prefix: "ipad-portrait-dark", dark: true, orientation: .portrait)
        captureAllProductScreens(prefix: "ipad-landscape-dark", dark: true, orientation: .landscapeLeft)
        captureAllProductScreens(prefix: "ipad-landscape-light", dark: false, orientation: .landscapeLeft)
    }
}


extension IOSNextUITests {
    private var phase2ScenarioID: String {
        ProcessInfo.processInfo.environment["IOSNEXT_PHASE2_SCENARIO_ID"] ?? ""
    }

    private var phase2Appearance: String {
        ProcessInfo.processInfo.environment["IOSNEXT_PHASE2_APPEARANCE"] ?? "light"
    }

    private var phase2Orientation: String {
        ProcessInfo.processInfo.environment["IOSNEXT_PHASE2_ORIENTATION"] ?? "portrait"
    }

    private func phase2PrepareOrientationBeforeLaunch() {
        XCUIDevice.shared.orientation = phase2Orientation == "landscape" ? .landscapeLeft : .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private func phase2SettleOrientation(in application: XCUIApplication) {
        setOrientation(phase2Orientation == "landscape" ? .landscapeLeft : .portrait, in: application)
    }

    private func phase2Product(_ screen: String) -> XCUIApplication {
        phase2PrepareOrientationBeforeLaunch()
        let arguments = phase2Appearance == "dark" ? ["--product-ui-test-dark"] : []
        let application = launch(screen, extraArguments: arguments)
        phase2SettleOrientation(in: application)
        return application
    }

    private func phase2WaitReady(
        identifier: String,
        in application: XCUIApplication,
        timeout: TimeInterval = 10
    ) {
        let probe = application.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(
            probe.waitForExistence(timeout: timeout),
            "PHASE2_CLASS=ready_timeout probe missing: \(identifier)"
        )
        let predicate = NSPredicate(format: "value == %@", "ready")
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: probe)],
            timeout: timeout
        )
        XCTAssertEqual(result, .completed, "PHASE2_CLASS=ready_timeout probe not ready: \(identifier)")
    }

    private func phase2Launch(arguments: [String]) -> XCUIApplication {
        phase2PrepareOrientationBeforeLaunch()
        let application = XCUIApplication()
        application.launchArguments = arguments
        application.launch()
        phase2SettleOrientation(in: application)
        app = application
        return application
    }

    private func phase2Screenshot(_ suffix: String, application: XCUIApplication) {
        attachScreenshot(
            "PHASE2-\(phase2ScenarioID)-\(phase2Appearance)-\(phase2Orientation)-\(suffix)",
            app: application
        )
    }

    private func phase2TapLabel(_ label: String, application: XCUIApplication) {
        let exact = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        if exact.waitForExistence(timeout: 2) {
            tapWhenVisible(exact, in: application, label: label)
            return
        }
        let contains = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", label))
            .firstMatch
        tapWhenVisible(contains, in: application, label: label)
    }

    private func phase2AssertVisibleText(
        _ text: String,
        application: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        let element = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "PHASE2_CLASS=wrong_surface expected text missing: \(text)"
        )
    }

    private func phase2AccessibilityState(screen: String, application: XCUIApplication) -> String {
        let root = application.descendants(matching: .any)
            .matching(identifier: "product-acceptance-\(screen)")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 5), "PHASE2_CLASS=wrong_surface missing root \(screen)")
        return root.value as? String ?? ""
    }

    private func phase2RunNavigation(_ scenario: String) {
        let spec: (screen: String, tap: String, verify: String)
        switch scenario {
        case "NAV-001": spec = ("rooms", "Timo Zimmer", "Nur verifizierte Geräte")
        case "NAV-002": spec = ("rooms", "Alle Entitäten", "Name oder Entity-ID")
        case "NAV-003": spec = ("media", "Companion Testfilm", "10 Sekunden vor")
        case "NAV-004": spec = ("system", "Live Operations", "Live Operations nicht eingerichtet")
        case "NAV-005": spec = ("system", "Szenen", "Abend")
        case "NAV-006": spec = ("system", "Control Center", "Control Center nicht eingerichtet")
        case "NAV-007": spec = ("system", "Diagnose", "Tokens werden nie in der Diagnose angezeigt")
        default:
            XCTFail("PHASE2_CLASS=selector_contract unknown navigation scenario: \(scenario)")
            return
        }

        let application = phase2Product(spec.screen)
        phase2TapLabel(spec.tap, application: application)
        phase2AssertVisibleText(spec.verify, application: application)
        phase2Screenshot("terminal", application: application)
    }

    private func phase2RunAccessibility(_ scenario: String) {
        let spec: (token: String, targets: [String])
        switch scenario {
        case "A11Y-001": spec = ("dynamicTypeAccessibility=true", ["home", "chat", "system", "light"])
        case "A11Y-002": spec = ("reduceMotion=true", ["home", "chat", "media", "light"])
        case "A11Y-003": spec = ("reduceTransparency=true", ["home", "system", "owner", "chat"])
        case "A11Y-004": spec = ("increasedContrast=true", ["home", "rooms", "media", "system", "light"])
        default:
            XCTFail("PHASE2_CLASS=selector_contract unknown accessibility scenario: \(scenario)")
            return
        }

        for target in spec.targets {
            let application = phase2Product(target)
            let state = phase2AccessibilityState(screen: target, application: application)
            XCTAssertTrue(
                state.contains(spec.token),
                "PHASE2_CLASS=accessibility_state_mismatch \(scenario) target=\(target) state=\(state)"
            )
            phase2Screenshot(target, application: application)
        }
    }

    private func phase2RunOrientation() {
        let targets = ["home", "rooms", "media", "system"]
        for target in targets {
            let application = phase2Product(target)
            phase2Screenshot(target, application: application)
        }
    }

    private func phase2RunCard(_ scenario: String) {
        let page: Int
        switch scenario {
        case "CARD-001": page = 0
        case "CARD-002": page = 1
        case "CARD-003": page = 2
        default:
            XCTFail("PHASE2_CLASS=selector_contract unknown card scenario: \(scenario)")
            return
        }
        let application = phase2Launch(arguments: ["--live-card-test-mode", "--live-card-page=\(page)"])
        phase2WaitReady(identifier: "visual-ready-live-card-page-\(page)", in: application)
        phase2AssertVisibleText("Testmodus · Seite \(page + 1)/3", application: application)
        phase2Screenshot("page-\(page)", application: application)
    }

    private func phase2RunAnimation(_ scenario: String) {
        if scenario == "ANIM-009" {
            let application = phase2Launch(arguments: ["--animation-acceptance-mode"])
            phase2WaitReady(identifier: "visual-ready-animation-stage-7", in: application, timeout: 24)
            phase2AssertVisibleText("Owner Area", application: application, timeout: 24)
            phase2Screenshot("sequence-terminal", application: application)
            return
        }

        guard let suffix = Int(scenario.split(separator: "-").last ?? ""), (1...8).contains(suffix) else {
            XCTFail("PHASE2_CLASS=selector_contract unknown animation scenario: \(scenario)")
            return
        }
        let stage = suffix - 1
        let application = phase2Launch(arguments: [
            "--animation-acceptance-mode",
            "--animation-stage=\(stage)"
        ])
        phase2WaitReady(identifier: "visual-ready-animation-stage-\(stage)", in: application)
        phase2Screenshot("stage-\(stage)", application: application)
    }

    private func phase2RunColdLaunch() {
        let application = phase2Launch(arguments: [])
        phase2AssertVisibleText("iOS Next", application: application, timeout: 8)
        XCTAssertTrue(
            application.buttons["Home Assistant verbinden"].waitForExistence(timeout: 5),
            "PHASE2_CLASS=wrong_surface connection action missing"
        )
        XCTAssertTrue(
            application.buttons["Verschlüsselten Chat öffnen"].waitForExistence(timeout: 5),
            "PHASE2_CLASS=wrong_surface chat action missing"
        )
        phase2Screenshot("landing", application: application)
    }

    private func phase2RunSetup() {
        let application = phase2Launch(arguments: [])
        let connect = application.buttons["Home Assistant verbinden"]
        tapWhenVisible(connect, in: application, label: "Home Assistant verbinden")
        XCTAssertTrue(
            application.navigationBars["Verbinden"].waitForExistence(timeout: 5),
            "PHASE2_CLASS=wrong_surface connection setup sheet missing"
        )
        phase2AssertVisibleText("Home-Assistant-Adresse", application: application)
        phase2Screenshot("setup", application: application)
    }

    private func phase2RunRunnerSafeState() {
        let application = phase2Product("system")
        phase2TapLabel("Control Center", application: application)
        phase2AssertVisibleText("Control Center nicht eingerichtet", application: application)
        phase2Screenshot("not-configured", application: application)
    }

    private func phase2RunChatInteraction() {
        let application = phase2Product("chat")
        XCTAssertTrue(application.navigationBars["Chats"].waitForExistence(timeout: 5),
                      "PHASE2_CLASS=wrong_surface new chats inbox missing")
        let mika = application.buttons["chat-inbox-person-Mika"].firstMatch
        tapWhenVisible(mika, in: application, label: "Mika private conversation")
        let field = application.textFields["chat-composer-field"].firstMatch
        tapWhenVisible(field, in: application, label: "Chat composer")
        application.typeText("Phase2 Visual")
        XCTAssertEqual(
            field.value as? String,
            "Phase2 Visual",
            "PHASE2_CLASS=wrong_surface chat draft did not update"
        )
        phase2Screenshot("draft", application: application)
    }

    private func phase2RunLightInteraction() {
        let application = phase2Product("light")
        let brightness = application.sliders["light-brightness-slider"]
        scrollUpUntilHittable(brightness, in: application, label: "Brightness slider")
        let before = brightness.value as? String
        brightness.adjust(toNormalizedSliderPosition: 0.28)
        XCTAssertNotEqual(before, brightness.value as? String, "PHASE2_CLASS=wrong_surface slider did not change")
        phase2Screenshot("slider", application: application)
    }

    func testPhase2Scenario() {
        let scenario = phase2ScenarioID
        XCTAssertFalse(scenario.isEmpty, "PHASE2_CLASS=selector_contract missing scenario id")

        switch scenario {
        case "CLD-001":
            phase2RunColdLaunch()
        case "SETUP-001":
            phase2RunSetup()
        case "SHELL-001": phase2Screenshot("home", application: phase2Product("home"))
        case "SHELL-002": phase2Screenshot("rooms", application: phase2Product("rooms"))
        case "SHELL-003": phase2Screenshot("chat", application: phase2Product("chat"))
        case "SHELL-004": phase2Screenshot("media", application: phase2Product("media"))
        case "SHELL-005": phase2Screenshot("system", application: phase2Product("system"))
        case "NAV-001"..."NAV-007":
            phase2RunNavigation(scenario)
        case "DETAIL-001": phase2Screenshot("light", application: phase2Product("light"))
        case "DETAIL-002": phase2Screenshot("media-detail", application: phase2Product("media-detail"))
        case "OWNER-001":
            let application = phase2Product("owner")
            phase2AssertVisibleText("Control Center nicht eingerichtet", application: application)
            phase2Screenshot("not-configured", application: application)
        case "RUNNER-001": phase2RunRunnerSafeState()
        case "CHAT-INT-001": phase2RunChatInteraction()
        case "LIGHT-INT-001": phase2RunLightInteraction()
        case "A11Y-001"..."A11Y-004": phase2RunAccessibility(scenario)
        case "CARD-001"..."CARD-003": phase2RunCard(scenario)
        case "ANIM-001"..."ANIM-009": phase2RunAnimation(scenario)
        case "ORIENT-001": phase2RunOrientation()
        default:
            XCTFail("PHASE2_CLASS=selector_contract unsupported scenario: \(scenario)")
        }
    }

    private func waitForMotionFrame(_ expectedFrame: Int, sequence: String, in application: XCUIApplication) {
        let root = application.descendants(matching: .any)
            .matching(identifier: "motion-acceptance-root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8), "Motion acceptance root missing: \(sequence)")
        let expected = String(format: "frame=%03d", expectedFrame)
        let predicate = NSPredicate(format: "value CONTAINS %@", expected)
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: root)],
            timeout: 3
        )
        XCTAssertEqual(result, .completed, "Motion frame did not settle: \(sequence) \(expectedFrame)")
    }

    private func writeMotionFrame(_ application: XCUIApplication, sequence: String, frame: Int, outputRoot: URL) throws {
        let directory = outputRoot.appendingPathComponent(sequence, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(String(format: "frame-%03d.png", frame))
        try application.screenshot().pngRepresentation.write(to: url, options: .atomic)
    }

    func testDeterministicMotionMasterFrames() throws {
        guard ProcessInfo.processInfo.environment["IOSNEXT_RUN_MOTION_MASTER_FRAMES"] == "1" else {
            throw XCTSkip("Deterministic motion capture runs only in the dedicated motion workflow")
        }
        guard let path = ProcessInfo.processInfo.environment["IOSNEXT_MOTION_OUTPUT_DIR"], !path.isEmpty else {
            XCTFail("IOSNEXT_MOTION_OUTPUT_DIR missing")
            return
        }

        let outputRoot = URL(fileURLWithPath: path, isDirectory: true)
        let sequences: [(name: String, frameCount: Int)] = [
            ("startup", 87),
            ("control-center-unlock", 109)
        ]

        for sequence in sequences {
            let application = XCUIApplication()
            application.launchArguments = ["--motion-acceptance-sequence=\(sequence.name)", "--motion-frame=0"]
            application.launch()
            waitForMotionFrame(0, sequence: sequence.name, in: application)

            let next = application.buttons["motion-next-frame"]
            XCTAssertTrue(next.waitForExistence(timeout: 4), "Motion frame stepper missing: \(sequence.name)")

            for frame in 0..<sequence.frameCount {
                waitForMotionFrame(frame, sequence: sequence.name, in: application)
                try writeMotionFrame(application, sequence: sequence.name, frame: frame, outputRoot: outputRoot)
                if frame + 1 < sequence.frameCount {
                    next.tap()
                }
            }

            application.terminate()
        }
    }

}
