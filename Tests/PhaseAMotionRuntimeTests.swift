import XCTest
@testable import IOSNext

final class PhaseAMotionRuntimeTests: XCTestCase {
    func testStartupV2HasVisibleConnectedShellReveal() {
        let start = IOSNextMasterMotion.startup(frame: 0)
        let revealed = IOSNextMasterMotion.startup(frame: 31)

        XCTAssertEqual(start.contentOpacity, 0.82, accuracy: 0.000001)
        XCTAssertEqual(start.contentYOffset, 4, accuracy: 0.000001)
        XCTAssertEqual(start.backdropOpacity, 0.20, accuracy: 0.000001)
        XCTAssertEqual(revealed.contentOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(revealed.contentYOffset, 0, accuracy: 0.000001)
        XCTAssertEqual(revealed.backdropOpacity, 0, accuracy: 0.000001)
    }

    func testControlCenterUnlockV2RevealsModulesAndReadyState() {
        let start = IOSNextMasterMotion.controlCenterUnlock(frame: 0)
        let moduleSettled = IOSNextMasterMotion.controlCenterUnlock(frame: 32)
        let ready = IOSNextMasterMotion.controlCenterUnlock(frame: 50)

        XCTAssertEqual(start.moduleReveal(index: 0), 0, accuracy: 0.000001)
        XCTAssertEqual(start.readyOpacity, 0, accuracy: 0.000001)
        XCTAssertEqual(moduleSettled.moduleReveal(index: 4), 1, accuracy: 0.000001)
        XCTAssertEqual(ready.readyOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(ready.readyScale, 1, accuracy: 0.000001)
    }

    func testControlCenterLockV2ReachesLockedSurface() {
        let start = IOSNextMasterMotion.controlCenterLock(frame: 0)
        let end = IOSNextMasterMotion.controlCenterLock(frame: 26)

        XCTAssertEqual(start.contentOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(start.lockedOpacity, 0, accuracy: 0.000001)
        XCTAssertEqual(end.lockedOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(end.lockedScale, 1, accuracy: 0.000001)
    }

    func testMotionV2SequenceDurationsRemainDeterministic() {
        XCTAssertEqual(IOSNextMotionSequence.startup.frameCount, 87)
        XCTAssertEqual(IOSNextMotionSequence.controlCenterUnlock.frameCount, 109)
        XCTAssertEqual(IOSNextMotionSequence.controlCenterLock.frameCount, 27)
        XCTAssertEqual(IOSNextMotionSequence.masterFramesPerSecond, 120, accuracy: 0.000001)
    }
}
