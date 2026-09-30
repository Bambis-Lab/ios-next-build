import CoreGraphics
import Foundation
import XCTest
import UIKit

final class IOSNextUITests: XCTestCase {
    private var app: XCUIApplication!
    private let screens = ["home", "rooms", "chat", "media", "system", "light", "media-detail", "owner", "wireguard"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
        XCUIDevice.shared.orientation = .portrait
    }

    @discardableResult
    private func launch(_ screen: String, extraArguments: [String] = []) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["--product-ui-test-screen=\(screen)"] + extraArguments
        application.launch()
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

    private func scrollUpUntilHittable(
        _ element: XCUIElement,
        in application: XCUIApplication,
        label: String,
        maxSwipes: Int = 4
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "\(label) did not exist")

        for _ in 0..<maxSwipes {
            if element.isHittable {
                return
            }
            application.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTAssertTrue(element.isHittable, "\(label) did not become hittable after \(maxSwipes) swipes")
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

        let mediaSummary = application.descendants(matching: .any)
            .matching(identifier: "media-active-summary")
            .firstMatch
        XCTAssertTrue(
            mediaSummary.waitForExistence(timeout: 5),
            "Native media tab did not expose the media summary"
        )

        let fireTV = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Companion Testfilm"))
            .firstMatch
        XCTAssertTrue(
            fireTV.waitForExistence(timeout: 5),
            "Media tab did not expose the expected Fire TV content"
        )
        tapWhenVisible(fireTV, in: application, label: "Fire TV Companion card")

        XCTAssertTrue(application.navigationBars["Fire TV Companion"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.buttons["Pause"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.buttons["10 Sekunden zurück"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.buttons["10 Sekunden vor"].waitForExistence(timeout: 3))
        attachScreenshot("product-fire-tv-companion-detail", app: application)
    }

    func testChatComposerInteraction() {
        let application = launch("chat")
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
        scrollUpUntilHittable(
            brightness,
            in: application,
            label: "Brightness slider"
        )
        let before = brightness.value as? String
        brightness.adjust(toNormalizedSliderPosition: 0.28)
        let after = brightness.value as? String
        XCTAssertNotEqual(before, after)
        attachScreenshot("product-light-slider-interaction", app: application)
    }

    func testOwnerAndWireGuardSafeEntryStates() {
        let ownerApplication = launch("owner")
        XCTAssertTrue(ownerApplication.staticTexts["Control Center nicht eingerichtet"].waitForExistence(timeout: 3))
        attachScreenshot("product-owner-entry", app: ownerApplication)

        let wireGuardApplication = launch("wireguard")
        XCTAssertTrue(wireGuardApplication.navigationBars["WireGuard"].waitForExistence(timeout: 3))
        XCTAssertTrue(wireGuardApplication.staticTexts["iOS Next WireGuard"].waitForExistence(timeout: 3))
        attachScreenshot("product-wireguard-entry", app: wireGuardApplication)
    }

    func testLiveOperationsSafeEntryState() {
        let application = launch("system")
        let liveOperations = application.descendants(matching: .any)
            .matching(identifier: "system-live-operations")
            .firstMatch
        scrollUpUntilHittable(liveOperations, in: application, label: "Live Operations", maxSwipes: 4)
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

    func testAccessibilityCoreScreenRenders() {
        let application = launch("home")
        XCTAssertTrue(application.staticTexts["Häufig genutzt"].waitForExistence(timeout: 3))
        _ = accessibilityState(in: application)
        attachScreenshot("product-accessibility-current-system-settings", app: application)
    }

    func testDynamicTypeAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("dynamicTypeAccessibility=true"))
        attachScreenshot("product-accessibility-dynamic-type-xxxl", app: application)
    }

    func testReduceMotionAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("reduceMotion=true"))
        attachScreenshot("product-accessibility-reduce-motion", app: application)
    }

    func testReduceTransparencyAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("reduceTransparency=true"))
        attachScreenshot("product-accessibility-reduce-transparency", app: application)
    }

    func testIncreaseContrastAccessibilityState() {
        let application = launch("home")
        XCTAssertTrue(accessibilityState(in: application).contains("increasedContrast=true"))
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
        case "NAV-004": spec = ("system", "Fernzugriff · WireGuard", "iOS Next WireGuard")
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
        case "A11Y-003": spec = ("reduceTransparency=true", ["home", "system", "owner", "wireguard"])
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
        case "WG-001":
            let application = phase2Product("wireguard")
            phase2AssertVisibleText("iOS Next WireGuard", application: application)
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
