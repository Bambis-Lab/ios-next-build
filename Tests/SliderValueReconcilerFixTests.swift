import XCTest
@testable import IOSNext

@MainActor
final class SliderValueReconcilerFixTests: XCTestCase {
    func testRemoteUpdatesCannotOverrideActiveGesture() {
        var state = SliderValueReconciler()
        state.initialize(from: 0.2, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.8, range: 0...1)
        state.observe(0.1, range: 0...1)
        XCTAssertEqual(state.value, 0.8)
    }

    func testConfirmationMatchesRequestedValue() {
        var state = SliderValueReconciler()
        state.initialize(from: 0.2, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.7, range: 0...1)
        let command = state.endEditing(range: 0...1)
        state.observe(0.2, range: 0...1)
        XCTAssertTrue(state.isAwaitingConfirmation)
        XCTAssertEqual(state.value, 0.7)
        state.observe(0.7, range: 0...1)
        XCTAssertFalse(state.isAwaitingConfirmation)
        XCTAssertEqual(state.value, 0.7)
        XCTAssertFalse(state.settle(revision: command.revision, range: 0...1))
    }

    func testOldTimeoutCannotRollbackNewGesture() {
        var state = SliderValueReconciler()
        state.initialize(from: 0.1, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.5, range: 0...1)
        let old = state.endEditing(range: 0...1)
        state.beginEditing()
        state.updateDraft(0.9, range: 0...1)
        let latest = state.endEditing(range: 0...1)
        XCTAssertFalse(state.settle(revision: old.revision, range: 0...1))
        XCTAssertTrue(state.isAwaitingConfirmation)
        XCTAssertTrue(state.settle(revision: latest.revision, range: 0...1))
    }

    func testNonFiniteDraftClampsToLowerBound() {
        var state = SliderValueReconciler()
        state.beginEditing()
        state.updateDraft(.nan, range: 0...1)
        XCTAssertEqual(state.value, 0)
    }
    func testLateTransportFailureRemainsVisibleAfterTimeout() {
        var state = SliderValueReconciler()
        state.reset(from: 0.2, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.9, range: 0...1)
        let command = state.endEditing(range: 0...1)
        XCTAssertTrue(state.settle(revision: command.revision, range: 0...1))
        state.finishTransport(.failed("Dienst nicht erreichbar"), revision: command.revision)
        XCTAssertEqual(state.issue, "Dienst nicht erreichbar")
        XCTAssertTrue(state.didTimeOut)
    }

    func testOldTransportFailureCannotReplaceNewGesture() {
        var state = SliderValueReconciler()
        state.reset(from: 0.1, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.4, range: 0...1)
        let old = state.endEditing(range: 0...1)
        state.beginEditing()
        state.updateDraft(0.8, range: 0...1)
        let latest = state.endEditing(range: 0...1)
        state.finishTransport(.failed("alter Fehler"), revision: old.revision)
        XCTAssertNil(state.issue)
        XCTAssertTrue(state.isAwaitingConfirmation)
        state.observe(0.8, range: 0...1)
        XCTAssertFalse(state.isAwaitingConfirmation)
        XCTAssertFalse(state.settle(revision: latest.revision, range: 0...1))
    }

    func testDisconnectReportsUncertainOutcome() {
        var state = SliderValueReconciler()
        state.reset(from: 0.3, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.7, range: 0...1)
        let command = state.endEditing(range: 0...1)
        state.finishTransport(.outcomeUnknown("Verbindung gewechselt"), revision: command.revision)
        XCTAssertEqual(state.issue, "Verbindung gewechselt")
        XCTAssertFalse(state.isAwaitingConfirmation)
        state.reset(from: 0.5, range: 0...1)
        XCTAssertNil(state.issue)
        XCTAssertEqual(state.value, 0.5)
    }

    func testResetInvalidatesPendingRevisionAndLateResponse() {
        var state = SliderValueReconciler()
        state.reset(from: 0.2, range: 0...1)
        state.beginEditing()
        state.updateDraft(0.9, range: 0...1)
        let old = state.endEditing(range: 0...1)
        state.reset(from: 0.4, range: 0...1)
        state.finishTransport(.failed("stale"), revision: old.revision)
        XCTAssertNil(state.issue)
        XCTAssertFalse(state.settle(revision: old.revision, range: 0...1))
        XCTAssertEqual(state.value, 0.4)
    }

}
