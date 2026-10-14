import Foundation

/// UI-side reconciliation of a locally edited control with asynchronous device state.
/// Device reports observed before acknowledgement must not replace a user gesture.
@MainActor
struct SliderValueReconciler {
    private(set) var value: Double = 0
    private(set) var isEditing = false
    private(set) var isAwaitingConfirmation = false
    private var pendingValue: Double?
    private var lastObservedValue: Double?
    private(set) var revision = 0
    private(set) var issue: String?
    private(set) var didTimeOut = false

    mutating func initialize(from remote: Double, range: ClosedRange<Double>) {
        let remote = clamp(remote, range)
        lastObservedValue = remote
        guard !isEditing && !isAwaitingConfirmation else { return }
        value = remote
    }

    mutating func beginEditing() {
        isEditing = true
        isAwaitingConfirmation = false
        pendingValue = nil
        lastObservedValue = nil
        issue = nil
        didTimeOut = false
        revision &+= 1
    }

    mutating func updateDraft(_ draft: Double, range: ClosedRange<Double>) {
        value = clamp(draft, range)
    }

    @discardableResult
    mutating func endEditing(range: ClosedRange<Double>) -> (value: Double, revision: Int) {
        isEditing = false
        value = clamp(value, range)
        pendingValue = value
        isAwaitingConfirmation = true
        issue = nil
        didTimeOut = false
        revision &+= 1
        return (value, revision)
    }

    mutating func observe(_ remote: Double, range: ClosedRange<Double>, tolerance: Double = 0.015) {
        let remote = clamp(remote, range)
        guard !isEditing else { return }
        lastObservedValue = remote
        if let pendingValue, isAwaitingConfirmation {
            if abs(remote - pendingValue) <= tolerance {
                value = remote
                self.pendingValue = nil
                isAwaitingConfirmation = false
                issue = nil
                didTimeOut = false
            }
            return
        }
        value = remote
    }

    /// Reconcile an unacknowledged command after the bounded UI grace period.
    /// A late timer from an older gesture cannot roll back a newer gesture.
    @discardableResult
    mutating func settle(revision expectedRevision: Int, range: ClosedRange<Double>) -> Bool {
        guard revision == expectedRevision, isAwaitingConfirmation, !isEditing else { return false }
        isAwaitingConfirmation = false
        pendingValue = nil
        didTimeOut = true
        if let lastObservedValue { value = clamp(lastObservedValue, range) }
        return true
    }

    /// Preserve late transport errors for the current revision, even after a UI timeout.
    mutating func finishTransport(_ result: DeviceCommandResult, revision expectedRevision: Int) {
        guard revision == expectedRevision, !isEditing else { return }
        switch result {
        case .executed:
            break // Only a device observation can confirm a value.
        case .superseded:
            issue = "Gerätebefehl durch neueren Wert ersetzt"
            isAwaitingConfirmation = false
        case .cancelled:
            issue = "Gerätebefehl abgebrochen"
            isAwaitingConfirmation = false
        case let .failed(message), let .outcomeUnknown(message):
            issue = message
            isAwaitingConfirmation = false
        }
    }

    mutating func reset(from remote: Double, range: ClosedRange<Double>) {
        revision &+= 1
        isEditing = false
        isAwaitingConfirmation = false
        pendingValue = nil
        lastObservedValue = nil
        issue = nil
        didTimeOut = false
        value = clamp(remote, range)
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
