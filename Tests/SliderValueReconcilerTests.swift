import XCTest
@testable import IOSNext

@MainActor
final class SliderValueReconcilerTests: XCTestCase {
    func testRemoteUpdateDoesNotInterruptActiveGesture() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 0.09, range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.70, range: 0...1)
        slider.observe(0.07, range: 0...1)
        XCTAssertEqual(slider.value, 0.70, accuracy: 0.0001)
    }

    func testStaleRemoteUpdateDoesNotUndoCommittedValue() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 0.09, range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.70, range: 0...1)
        let command = slider.endEditing(range: 0...1)
        XCTAssertEqual(command.value, 0.70, accuracy: 0.0001)
        slider.observe(0.07, range: 0...1)
        XCTAssertEqual(slider.value, 0.70, accuracy: 0.0001)
        XCTAssertTrue(slider.isAwaitingConfirmation)
        slider.observe(0.70, range: 0...1)
        XCTAssertFalse(slider.isAwaitingConfirmation)
        XCTAssertEqual(slider.value, 0.70, accuracy: 0.0001)
    }

    func testTimeoutReconcilesLatestDeviceValue() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 0.09, range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.70, range: 0...1)
        let command = slider.endEditing(range: 0...1)
        slider.observe(0.07, range: 0...1)
        slider.settle(revision: command.revision, range: 0...1)
        XCTAssertEqual(slider.value, 0.07, accuracy: 0.0001)
        XCTAssertFalse(slider.isAwaitingConfirmation)
    }

    func testTimeoutWithoutPostGestureStateDoesNotRevertToOldValue() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 0.09, range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.70, range: 0...1)
        let command = slider.endEditing(range: 0...1)
        slider.settle(revision: command.revision, range: 0...1)
        XCTAssertEqual(slider.value, 0.70, accuracy: 0.0001)
    }

    func testOldTimerCannotRollbackNewerGesture() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 0.09, range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.70, range: 0...1)
        let old = slider.endEditing(range: 0...1)
        slider.beginEditing()
        slider.updateDraft(0.55, range: 0...1)
        let latest = slider.endEditing(range: 0...1)
        slider.settle(revision: old.revision, range: 0...1)
        XCTAssertEqual(slider.value, 0.55, accuracy: 0.0001)
        XCTAssertTrue(slider.isAwaitingConfirmation)
        slider.observe(0.55, range: 0...1)
        slider.settle(revision: latest.revision, range: 0...1)
        XCTAssertEqual(slider.value, 0.55, accuracy: 0.0001)
    }

    func testSeekToleranceAllowsPositionDrift() {
        var slider = SliderValueReconciler()
        slider.initialize(from: 10, range: 0...120)
        slider.beginEditing()
        slider.updateDraft(60, range: 0...120)
        _ = slider.endEditing(range: 0...120)
        slider.observe(61, range: 0...120, tolerance: 1.5)
        XCTAssertFalse(slider.isAwaitingConfirmation)
        XCTAssertEqual(slider.value, 61, accuracy: 0.0001)
    }

    func testNonFiniteRemoteValuesCannotPoisonSlider() {
        var slider = SliderValueReconciler()
        slider.initialize(from: .nan, range: 0...1)
        XCTAssertEqual(slider.value, 0)
        slider.observe(.infinity, range: 0...1)
        XCTAssertEqual(slider.value, 0)
    }
}
