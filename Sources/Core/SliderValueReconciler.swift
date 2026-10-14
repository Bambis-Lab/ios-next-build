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
    private var revision = 0

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
        revision &+= 1
        return (value, revision)
    }

    mutating func observe(_ remote: Double, range: ClosedRange<Double>, tolerance: Double = 0.015) {
        let remote = clamp(remote, range)
        lastObservedValue = remote
        guard !isEditing else { return }
        if let pendingValue, isAwaitingConfirmation {
            if abs(remote - pendingValue) <= tolerance {
                value = remote
                self.pendingValue = nil
                isAwaitingConfirmation = false
            }
            return
        }
        value = remote
    }

    /// Reconcile an unacknowledged command after the bounded UI grace period.
    /// A late timer from an older gesture cannot roll back a newer gesture.
    mutating func settle(revision expectedRevision: Int, range: ClosedRange<Double>) {
        guard revision == expectedRevision, isAwaitingConfirmation, !isEditing else { return }
        isAwaitingConfirmation = false
        pendingValue = nil
        if let lastObservedValue { value = clamp(lastObservedValue, range) }
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
