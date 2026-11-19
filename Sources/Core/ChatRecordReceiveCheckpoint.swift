import Foundation

/// Staging-only transactional receive adapter.
/// ACK eligibility is returned only after both record changes and replay IDs
/// are committed. This object cannot transmit a network ACK or promote v1.
actor ChatRecordReceiveCheckpoint {
    private let store: EncryptedChatRecordStore

    struct Receipt: Equatable, Sendable {
        let envelopeIDs: [String]
    }

    init(store: EncryptedChatRecordStore) { self.store = store }

    func load() async throws -> ChatPersistentSnapshot {
        try ChatHistoryRecordMigration.assemble(await store.records())
    }

    /// The caller must have verified every supplied envelope cryptographically.
    /// The snapshot and replay IDs are committed together, including any
    /// partial attachment bytes. A stale writer fails without returning ACKs.
    func commit(previous: ChatPersistentSnapshot, next: ChatPersistentSnapshot,
                verifiedEnvelopeIDs: [String]) async throws -> Receipt {
        try Task.checkCancellation()
        guard verifiedEnvelopeIDs.count <= 256,
              Set(verifiedEnvelopeIDs).count == verifiedEnvelopeIDs.count,
              verifiedEnvelopeIDs.allSatisfy({ id in
                  !id.isEmpty && id.utf8.count <= 512 && next.seen[id] != nil
              }) else { throw ChatHistoryError.invalidArchive }
        let before = try ChatHistoryRecordMigration.split(previous)
        let after = try ChatHistoryRecordMigration.split(next)
        let changes = try ChatHistoryRecordMigration.delta(from: before, to: after)
        try await store.commitCheckpoint(expected: before, changes: changes)
        // Once SQLite has committed, return the durable result even if the
        // caller was cancelled during completion. The caller suppresses ACK
        // on cancellation, but must not roll back a committed local snapshot.
        return Receipt(envelopeIDs: verifiedEnvelopeIDs)
    }
}
