import Foundation

/// Prevents overlapping reads of the same authenticated service resource.
/// Each Owner/Runner/Factory model owns its own instance. It never shares a
/// response or a credential across principals, services, or login contexts.
@MainActor
final class SingleFlightRequestScheduler {
    private var inFlight: Task<Void, Never>?
    private var generation: UInt64 = 0

    func run(_ work: @escaping @MainActor () async -> Void) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let token = generation
        let task = Task { await work() }
        inFlight = task
        await task.value
        if generation == token {
            inFlight = nil
        }
    }

    /// Call during logout/reconfiguration to prevent reuse across identities.
    func invalidate() {
        generation &+= 1
        inFlight?.cancel()
        inFlight = nil
    }
}
