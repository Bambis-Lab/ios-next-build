import Foundation

/// Latest-wins, serial command pipeline for high-frequency UI controls.
/// Keeps the last requested value even when a service call is already in flight.
/// Does not bypass Home Assistant authorization or the existing service client.
@MainActor
final class LatestValueCommandQueue<Value: Sendable> {
    private struct Pending {
        let value: Value
        let apply: @MainActor (Value) async -> Void
    }

    private var pending: Pending?
    private var worker: Task<Void, Never>?
    private let settlingDelay: Duration

    init(settlingDelay: Duration = .milliseconds(125)) {
        self.settlingDelay = settlingDelay
    }

    func submit(_ value: Value, apply: @escaping @MainActor (Value) async -> Void) {
        pending = Pending(value: value, apply: apply)
        guard worker == nil else { return }
        // Retain the queue until the latest color command has been delivered,
        // even when the color sheet is dismissed immediately after selection.
        // drain() clears worker on completion, ending this temporary retain cycle.
        worker = Task { [self] in
            await drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: settlingDelay)
            } catch {
                break
            }
            guard let next = pending else { break }
            pending = nil
            // New input may arrive while this is awaited. It will be sent
            // after the in-flight request, not discarded by the busy guard.
            await next.apply(next.value)
        }
        worker = nil
    }

    /// Explicitly discard uncommitted input only when the user disconnects.
    func cancelPending() {
        pending = nil
        worker?.cancel()
        worker = nil
    }
}
