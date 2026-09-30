import XCTest
@testable import IOSNext

final class JarvisTests: XCTestCase {
    func testSmartHomeIntentRouting() {
        let intent = JarvisIntentRouter.route("Mach das Licht in Juli Zimmer an")
        XCTAssertEqual(intent.domain, .homeAssistant)
        XCTAssertEqual(intent.action, "smart-home")
    }

    func testRunnerIntentRouting() {
        let intent = JarvisIntentRouter.route("Wie geht es dem Runner?")
        XCTAssertEqual(intent.domain, .runner)
        XCTAssertEqual(intent.action, "status")
    }

    func testCommanderIntentRouting() {
        let intent = JarvisIntentRouter.route("Prüfe Code Commander")
        XCTAssertEqual(intent.domain, .commander)
    }

    func testMediaIntentRouting() {
        let intent = JarvisIntentRouter.route("Was läuft gerade auf dem Fernseher?")
        XCTAssertEqual(intent.domain, .media)
    }

    func testControlCenterIntentRouting() {
        let intent = JarvisIntentRouter.route("Öffne Control Center")
        XCTAssertEqual(intent.domain, .appNavigation)
        XCTAssertEqual(intent.action, "control-center")
    }

    func testResearchIntentRouting() {
        let intent = JarvisIntentRouter.route("Analysiere Fehler 5004 weiter")
        XCTAssertEqual(intent.domain, .research)
    }

    func testUnknownIntentFallsBackToConversation() {
        let intent = JarvisIntentRouter.route("Erzähl mir etwas")
        XCTAssertEqual(intent.domain, .conversational)
        XCTAssertEqual(intent.action, "chat")
    }

    func testSensitivityThresholdsAreOrdered() {
        XCTAssertGreaterThan(JarvisSensitivity.low.minimumConfidence, JarvisSensitivity.normal.minimumConfidence)
        XCTAssertGreaterThan(JarvisSensitivity.normal.minimumConfidence, JarvisSensitivity.high.minimumConfidence)
    }
}
