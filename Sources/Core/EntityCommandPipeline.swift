import Foundation

/// One serial lane per HA entity. It never retries a service action on its own.
/// Non-idempotent commands stay FIFO; rapidly changing absolute setpoints may
/// replace only queued (not in-flight) commands from the same control family.
enum DeviceCommandResult: Equatable {
    case executed
    case superseded
    case cancelled
    case failed(String)
    case outcomeUnknown(String)
}

@MainActor
final class EntityCommandPipeline {
    private struct Item {
        let coalescingKey: String?
        let operation: @MainActor () async -> DeviceCommandResult
        let continuation: CheckedContinuation<DeviceCommandResult, Never>
    }

    private struct Lane {
        var running = false
        var pending: [Item] = []
    }

    private var lanes: [String: Lane] = [:]

    /// Returns an explicit execution result. An enqueued operation cannot be
    /// called successful simply because its closure ran: preflight and server
    /// failures are surfaced distinctly.
    func execute(
        entityID: String,
        coalescingKey: String? = nil,
        operation: @escaping @MainActor () async -> DeviceCommandResult
    ) async -> DeviceCommandResult {
        await withCheckedContinuation { continuation in
            var lane = lanes[entityID] ?? Lane()
            if let coalescingKey {
                lane.pending.removeAll { item in
                    guard item.coalescingKey == coalescingKey else { return false }
                    item.continuation.resume(returning: .superseded)
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
            let result = await next.operation()
            next.continuation.resume(returning: result)
        }
    }

    /// Invalidates queued commands on HA disconnect or authenticated user switch.
    /// Already-running requests terminate via the underlying HA transport.
    func invalidatePending() {
        for lane in lanes.values {
            for item in lane.pending {
                item.continuation.resume(returning: .cancelled)
            }
        }
        for entityID in Array(lanes.keys) {
            lanes[entityID]?.pending.removeAll()
        }
    }
}
