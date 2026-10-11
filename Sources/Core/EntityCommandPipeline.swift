import Foundation

/// Explicit, user-visible result of an asynchronous device command.
enum DeviceCommandResult: Equatable {
    case executed
    case superseded
    case cancelled
    case failed(String)
    case outcomeUnknown(String)
}

/// One serial lane per HA entity. There is no automatic retry. Safe absolute
/// setpoints can replace queued values, but never replace an in-flight command.
/// On disconnect an in-flight caller is released immediately as outcomeUnknown;
/// the lane is kept occupied until its transport task actually unwinds so a new
/// command cannot race an older request that may already have reached HA.
@MainActor
final class EntityCommandPipeline {
    private struct Item {
        let id: UUID
        let coalescingKey: String?
        let operation: @MainActor () async -> DeviceCommandResult
        let continuation: CheckedContinuation<DeviceCommandResult, Never>
    }

    private struct Lane {
        var active: Item?
        var activeResultDelivered = false
        var pending: [Item] = []
    }

    private var lanes: [String: Lane] = [:]
    private var drainTasks: [String: Task<Void, Never>] = [:]
    private var activeOperationTasks: [String: Task<DeviceCommandResult, Never>] = [:]

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
                id: UUID(),
                coalescingKey: coalescingKey,
                operation: operation,
                continuation: continuation
            ))
            lanes[entityID] = lane

            if drainTasks[entityID] == nil {
                drainTasks[entityID] = Task { [self] in
                    await drain(entityID)
                }
            }
        }
    }

    private func drain(_ entityID: String) async {
        while true {
            guard var lane = lanes[entityID] else {
                drainTasks[entityID] = nil
                activeOperationTasks[entityID] = nil
                return
            }

            guard !lane.pending.isEmpty else {
                lanes.removeValue(forKey: entityID)
                drainTasks[entityID] = nil
                activeOperationTasks[entityID] = nil
                return
            }

            let next = lane.pending.removeFirst()
            lane.active = next
            lane.activeResultDelivered = false
            lanes[entityID] = lane

            // Separate unstructured operation task: cancelling a request does
            // not cancel the drain worker, so newer-generation queued commands
            // can still run after the old transport operation has unwound.
            let operationTask = Task { @MainActor in
                await next.operation()
            }
            activeOperationTasks[entityID] = operationTask
            let result = await operationTask.value
            activeOperationTasks[entityID] = nil

            guard var latest = lanes[entityID],
                  latest.active?.id == next.id else {
                // A lane is not removed while an active operation is unwinding;
                // keep this guard defensive so no continuation is resumed twice.
                continue
            }
            if !latest.activeResultDelivered {
                next.continuation.resume(returning: result)
            }
            latest.active = nil
            latest.activeResultDelivered = false
            lanes[entityID] = latest
        }
    }

    /// Supersedes queued work as cancelled and releases active callers
    /// immediately. An already-sent server side effect cannot be rolled back;
    /// that caller receives outcomeUnknown and the transport task is cancelled.
    func invalidatePending() {
        for entityID in Array(lanes.keys) {
            guard var lane = lanes[entityID] else { continue }
            for item in lane.pending {
                item.continuation.resume(returning: .cancelled)
            }
            lane.pending.removeAll()

            if let active = lane.active, !lane.activeResultDelivered {
                lane.activeResultDelivered = true
                active.continuation.resume(returning: .outcomeUnknown(
                    "Die Verbindung änderte sich während der Aktion. Der tatsächliche Geräte-Zustand muss neu synchronisiert werden."
                ))
                lanes[entityID] = lane
                activeOperationTasks[entityID]?.cancel()
            } else {
                lanes[entityID] = lane
            }
        }
    }
}