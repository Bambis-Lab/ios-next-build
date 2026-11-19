import Foundation

// Exact legacy v1 Codable shape. The running archive still uses this type.
struct ChatPersistentPartial: Codable, Equatable, Sendable {
    let senderUserID: String
    let conversationID: String?
    let kind: ChatMessageKind
    let contentType: String
    let createdAt: Date
    let chunkCount: Int
    var chunks: [Int: Data]
    var lastUpdated: Date
}
struct ChatPersistentSnapshot: Codable, Equatable, Sendable {
    let version: Int
    let messages: [ChatMessage]
    let partials: [String: ChatPersistentPartial]
    let seen: [String: Date]
    var pendingRecipientProofs: [String:ChatPendingRecipientProof]? = nil
}

/// Rehearsal only. Never removes or promotes the original v1 archive.
enum ChatHistoryRecordMigration {
    typealias Store = EncryptedChatRecordStore
    private struct Layout: Codable {
        let version: Int
        let messages: [String]
        let partials: [String]
        let seen: [String]
        var hasRecipientProofQueue:Bool? = nil
    }
    private struct Assembly: Codable {
        let metadata: ChatPersistentPartial
        let indexes: [Int]
    }
    private static let layoutKey = Store.Key(kind: .migration, id: "history-layout-v1")
    private static let proofQueueKey = Store.Key(kind: .outbox, id: "recipient-proof-queue-v1")
    private static let limits: [ChatMessageKind: Int] = [.text: 16*1024,.image: 12*1024*1024,.voice:24*1024*1024,.video:30*1024*1024]

    private static func validate(_ s: ChatPersistentSnapshot) throws {
        guard s.version == 1, s.messages.count <= 200, s.partials.count <= 256, s.seen.count <= 20_000,
              Set(s.messages.map(\.id)).count == s.messages.count else { throw ChatHistoryError.invalidArchive }
        let queue=s.pendingRecipientProofs ?? [:]
        guard queue.count<=4096 else {throw ChatHistoryError.capacity}
        for (id,entry) in queue {
            guard id==entry.proof.id,!entry.keyFingerprint.isEmpty,
                  entry.committedAt.timeIntervalSinceReferenceDate.isFinite,
                  entry.proof.signature.isEmpty || (entry.proof.signature.utf8.count==88 &&
                    Data(base64Encoded:entry.proof.signature)?.count==64)
            else {throw ChatHistoryError.invalidArchive}
            _ = try entry.proof.signingBytes()
        }
        var complete = 0
        for m in s.messages {
            guard m.data.count <= (limits[m.kind] ?? 0), m.data.count <= 160*1024*1024-complete else { throw ChatHistoryError.capacity }
            complete += m.data.count
        }
        var fragments = 0
        for p in s.partials.values {
            guard (1...256).contains(p.chunkCount), p.chunks.count < p.chunkCount,
                  p.chunks.keys.allSatisfy({ (0..<p.chunkCount).contains($0) }) else { throw ChatHistoryError.invalidArchive }
            var bytes = 0
            for chunk in p.chunks.values {
                guard chunk.count <= 384*1024 else { throw ChatHistoryError.capacity }
                bytes += chunk.count
            }
            guard bytes <= (limits[p.kind] ?? 0), bytes <= 96*1024*1024-fragments else { throw ChatHistoryError.capacity }
            fragments += bytes
        }
    }
    private static func chunk(_ id: String, _ index: Int) -> Store.Key {
        .init(kind: .fragment,id:id+":"+String(index))
    }
    static func split(_ s: ChatPersistentSnapshot) throws -> [Store.Record] {
        try validate(s)
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        let layout = Layout(version:1,messages:s.messages.map(\.id),partials:s.partials.keys.sorted(),seen:s.seen.keys.sorted(),
            hasRecipientProofQueue:s.pendingRecipientProofs == nil ? nil : true)
        var result = [Store.Record(key:layoutKey,bytes:try e.encode(layout))]
        if let queue=s.pendingRecipientProofs {
            result.append(.init(key:proofQueueKey,bytes:try e.encode(queue)))
        }
        for m in s.messages {
            var content = m
            content.delivery = .received
            result.append(.init(key:.init(kind:.message,id:m.id),bytes:try e.encode(content)))
            result.append(.init(key:.init(kind:.delivery,id:m.id),bytes:try e.encode(m.delivery)))
        }
        for (id,p) in s.partials {
            var metadata = p
            metadata.chunks = [:]
            result.append(.init(key:.init(kind:.assembly,id:id),bytes:try e.encode(Assembly(metadata:metadata,indexes:p.chunks.keys.sorted()))))
            for (index,bytes) in p.chunks { result.append(.init(key:chunk(id,index),bytes:bytes)) }
        }
        for (id,date) in s.seen { result.append(.init(key:.init(kind:.replay,id:id),bytes:try e.encode(date))) }
        return result
    }
    static func assemble(_ records: [Store.Record]) throws -> ChatPersistentSnapshot {
        var values: [Store.Key:Data] = [:]
        for r in records { guard values.updateValue(r.bytes,forKey:r.key) == nil else { throw ChatHistoryError.invalidArchive } }
        func take(_ k: Store.Key) throws -> Data {
            guard let v = values.removeValue(forKey:k) else { throw ChatHistoryError.invalidArchive }
            return v
        }
        let d = JSONDecoder()
        let layout = try d.decode(Layout.self,from:take(layoutKey))
        guard layout.version == 1,layout.messages.count <= 200,layout.partials.count <= 256,layout.seen.count <= 20_000 else { throw ChatHistoryError.invalidArchive }
        var messages: [ChatMessage] = []
        for id in layout.messages {
            var m = try d.decode(ChatMessage.self,from:take(.init(kind:.message,id:id)))
            guard m.id == id else { throw ChatHistoryError.invalidArchive }
            m.delivery = try d.decode(ChatMessage.Delivery.self,from:take(.init(kind:.delivery,id:id)))
            messages.append(m)
        }
        var partials: [String:ChatPersistentPartial] = [:]
        for id in layout.partials {
            let a = try d.decode(Assembly.self,from:take(.init(kind:.assembly,id:id)))
            var p = a.metadata
            guard p.chunks.isEmpty,(1...256).contains(p.chunkCount),
                  a.indexes.count < p.chunkCount,Set(a.indexes).count == a.indexes.count,
                  a.indexes.allSatisfy({ (0..<p.chunkCount).contains($0) }) else { throw ChatHistoryError.invalidArchive }
            for i in a.indexes { p.chunks[i] = try take(chunk(id,i)) }
            partials[id] = p
        }
        var seen: [String:Date] = [:]
        for id in layout.seen { seen[id] = try d.decode(Date.self,from:take(.init(kind:.replay,id:id))) }
        let queue=layout.hasRecipientProofQueue == true
            ? try d.decode([String:ChatPendingRecipientProof].self,from:take(proofQueueKey)) : nil
        guard values.isEmpty else { throw ChatHistoryError.invalidArchive }
        let s = ChatPersistentSnapshot(version:1,messages:messages,partials:partials,seen:seen,pendingRecipientProofs:queue)
        try validate(s)
        return s
    }
    /// Build only the changed record operations; deletions precede additions
    /// so replacement at the configured capacity is safe.
    static func delta(from old: [Store.Record], to new: [Store.Record]) throws -> [Store.Change] {
        var before: [Store.Key:Data] = [:], after: [Store.Key:Data] = [:]
        for r in old { guard before.updateValue(r.bytes, forKey:r.key) == nil else { throw ChatHistoryError.invalidArchive } }
        for r in new { guard after.updateValue(r.bytes, forKey:r.key) == nil else { throw ChatHistoryError.invalidArchive } }
        let removed: [Store.Change] = old.filter { after[$0.key] == nil }.map { .remove($0.key) }
        let changed: [Store.Change] = new.filter { before[$0.key] != $0.bytes }.map { .put($0) }
        return removed + changed
    }

    static func rehearse(_ snapshot: ChatPersistentSnapshot,into candidate: Store) async throws {
        try await candidate.importInitial(split(snapshot))
        let records = try await candidate.records()
        guard try assemble(records) == snapshot else { throw ChatHistoryError.invalidArchive }
    }
}
