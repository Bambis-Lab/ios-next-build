import Foundation

/// Main-actor serialization across async durable writes. No in-memory
/// mutation is left visible while SQLite is committing. A generation change
/// prevents the old account's results from reaching the new account.
@MainActor
final class ChatHistoryMutationGate {
    private var active=false

    func waitUntilIdle(isCurrent: () -> Bool) async throws {
        let clock=ContinuousClock()
        let deadline=clock.now.advanced(by:.seconds(30))
        while active {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            guard clock.now < deadline else { throw ChatHistoryError.busy }
            try await Task.sleep(for:.milliseconds(20))
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
    }

    func commit(isCurrent: () -> Bool,
                read: () -> ChatPersistentSnapshot,
                apply: (ChatPersistentSnapshot) -> Void,
                mutate: () throws -> Void,
                persist: (ChatPersistentSnapshot, ChatPersistentSnapshot) async throws -> Void) async throws {
        try await waitUntilIdle(isCurrent:isCurrent)
        active=true
        defer { active=false }
        let previous=read()
        let next:ChatPersistentSnapshot
        do {
            try mutate()
            next=read()
        } catch {
            apply(previous)
            throw error
        }
        // Do not leave unsaved replay markers, fragments or outbound messages
        // observable across suspension or account changes.
        apply(previous)
        try await persist(previous,next)
        guard isCurrent() else { throw CancellationError() }
        apply(next)
        try Task.checkCancellation()
    }
}
