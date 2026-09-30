import Foundation
import XCTest

final class MotionV2LockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeterministicControlCenterLockFrames() throws {
        guard ProcessInfo.processInfo.environment["IOSNEXT_RUN_MOTION_MASTER_FRAMES"] == "1" else {
            throw XCTSkip("Deterministic motion capture runs only in the dedicated motion workflow")
        }
        guard let path = ProcessInfo.processInfo.environment["IOSNEXT_MOTION_OUTPUT_DIR"], !path.isEmpty else {
            XCTFail("IOSNEXT_MOTION_OUTPUT_DIR missing")
            return
        }

        let outputRoot = URL(fileURLWithPath: path, isDirectory: true)
        let sequence = "control-center-lock"
        let frameCount = 27
        let application = XCUIApplication()
        application.launchArguments = ["--motion-acceptance-sequence=\(sequence)", "--motion-frame=0"]
        application.launch()

        let root = application.descendants(matching: .any)
            .matching(identifier: "motion-acceptance-root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8), "Motion acceptance root missing: \(sequence)")

        let next = application.buttons["motion-next-frame"]
        XCTAssertTrue(next.waitForExistence(timeout: 4), "Motion frame stepper missing: \(sequence)")

        let directory = outputRoot.appendingPathComponent(sequence, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for frame in 0..<frameCount {
            let expected = String(format: "frame=%03d", frame)
            let predicate = NSPredicate(format: "value CONTAINS %@", expected)
            let result = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: root)],
                timeout: 3
            )
            XCTAssertEqual(result, .completed, "Motion frame did not settle: \(sequence) \(frame)")

            let url = directory.appendingPathComponent(String(format: "frame-%03d.png", frame))
            try application.screenshot().pngRepresentation.write(to: url, options: .atomic)

            if frame + 1 < frameCount {
                next.tap()
            }
        }

        application.terminate()
    }
}
