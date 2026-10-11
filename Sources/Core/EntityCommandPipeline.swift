import Foundation

/// One serial lane per HA entity. It never retries a service action on its own.
/// Non-idempotent commands stay FIFO; rapidly changing absolute setpoints may
/// replace only queued (not in-flight) commands from the same control family.
@MainActor
final class EntityCommandPipeline {
    private struct Item {
        let coalescingKey: String?
        let operation: @MainActor () async -> Void
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct Lane {
        var running = false
        var pending: [Item] = []
    }

    private var lanes: [String: Lane] = [:]

    /// Returns false when this pending value was superseded or invalidated.
    /// The operation reports its own server failure separately.
    func execute(
        entityID: String,
        coalescingKey: String? = nil,
        operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            var lane = lanes[entityID] ?? Lane()
            if let coalescingKey {
                lane.pending.removeAll { item in
                    guard item.coalescingKey == coalescingKey else { return false }
                    item.continuation.resume(returning: false)
                    return true
                }
            }
            lane.pending.append(Item(
                coalescingKey: coalescingKey,
                operation: operation,
                continuation: continuation
            ))
            let shouldStart = !lane.running
            if shouldStart { lane.running = true }
            lanes[entityID] = lane
            if shouldStart {
                Task { [self] in await drain(entityID) }
            }
        }
    }

    private func drain(_ entityID: String) async {
        while var lane = lanes[entityID] {
            guard !lane.pending.isEmpty else {
                lanes.removeValue(forKey: entityID)
                return
            }
            let next = lane.pending.removeFirst()
            lanes[entityID] = lane
            await next.operation()
            next.continuation.resume(returning: true)
        }
    }

    /// Invalidates queued commands on HA disconnect or authenticated user switch.
    /// Already-running requests terminate via the underlying HA transport.
    func invalidatePending() {
        for lane in lanes.values {
            for item in lane.pending {
                item.continuation.resume(returning: false)
            }
        }
        for entityID in lanes.keys {
            lanes[entityID]?.pending.removeAll()
        }
    }
}
