import Foundation
import CryptoKit

/// Durable sender journal. An uncertain envelope may only be replayed
/// after explicit caller negotiation of the digest-bound receipt contract.
/// Its exact signed bytes, identity and original timestamp are retained.
struct ChatOutboxScope: Codable, Equatable, Sendable {
    let endpoint: URL
    let user: String
    let device: String
    let keyFingerprint: String
}

@MainActor
final class DurableChatOutbox {
    enum Phase: String, Codable, Sendable { case ready, uncertain, confirmed }
    struct Entry: Codable, Equatable, Sendable {
        let envelope: ChatEnvelope
        var phase: Phase
    }
    struct Pending: Codable, Equatable, Sendable {
        let scope: ChatOutboxScope
        let groupID: String
        let recipients: [ChatIdentity]
        var entries: [Entry]
    }
    struct ExpiredRecord: Codable, Equatable, Sendable {
        let groupID:String
        let closedAt:Date
        let entries:[EntrySummary]
        struct EntrySummary:Codable,Equatable,Sendable {
            let id:String
            let digest:String
            let phase:Phase
        }
    }
    private struct Snapshot: Codable {
        let version: Int
        let pending: Pending?
        let expired:[ExpiredRecord]?
        // Optional only for decoding the original v1 single-slot journal.
        let queued:[Pending]?
    }

    private let scope: ChatOutboxScope
    private let local: ChatIdentity
    private let archive: ChatHistoryArchive
    private static let maxArchiveBytes = 128*1024*1024
    static let maximumPendingGroups = 8

    convenience init(scope: ChatOutboxScope, local: ChatIdentity) throws {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.sortedKeys]
        let archive=try ChatHistoryArchive(scopedData:encoder.encode(scope),
            namespace:"chatOutbox.v1",folder:"EncryptedChatOutbox")
        try self.init(scope:scope,local:local,archive:archive)
    }

    init(scope:ChatOutboxScope,local:ChatIdentity,archive:ChatHistoryArchive) throws {
        guard scope.endpoint.scheme=="https",local.userID==scope.user,local.deviceID==scope.device,
              ChatDeviceKeys.safetyNumber(for:local)==scope.keyFingerprint,
              EncryptedTicketMessage.validIdentity(local) else {throw ChatError.identityChanged}
        self.scope=scope;self.local=TicketIdentityBinding.canonical(local);self.archive=archive
    }

    private func validate(_ batch:Pending) throws {
        guard batch.scope==scope,EncryptedTicketMessage.validID(batch.groupID),
              (1...20).contains(batch.recipients.count),(1...1024).contains(batch.entries.count),
              Set(batch.entries.map{$0.envelope.id}).count==batch.entries.count,
              Set(batch.recipients.map(\.deviceID)).count==batch.recipients.count,
              batch.recipients.allSatisfy({EncryptedTicketMessage.validIdentity($0) && $0.userID != scope.user && $0.deviceID != scope.device}),
              let signing=Data(base64Encoded:local.signingPublicKey) else {throw ChatHistoryError.invalidArchive}
        let key=try Curve25519.Signing.PublicKey(rawRepresentation:signing)
        guard let first=batch.entries.first?.envelope,(1...256).contains(first.chunkCount),
              batch.entries.count==first.chunkCount*batch.recipients.count else {throw ChatHistoryError.invalidArchive}
        var indexes=Set<[String]>()
        var uncertain=0
        var incomplete=false
        for entry in batch.entries {
            let e=entry.envelope
            guard EncryptedTicketMessage.validID(e.id),e.groupID==batch.groupID,
                  e.senderUserID==scope.user,e.senderDeviceID==scope.device,
                  e.chunkCount==first.chunkCount,(0..<e.chunkCount).contains(e.chunkIndex),
                  e.messageType==first.messageType,e.contentType==first.contentType,
                  e.createdAt==first.createdAt,e.conversationID==first.conversationID,
                  e.ciphertext.utf8.count<=525000,e.signature.utf8.count<=128,
                  batch.recipients.contains(where:{$0.userID==e.recipientUserID && $0.deviceID==e.recipientDeviceID}),
                  indexes.insert([e.recipientDeviceID,String(e.chunkIndex)]).inserted,
                  let signature=Data(base64Encoded:e.signature),
                  key.isValidSignature(signature,for:try e.signingData())
            else {throw ChatHistoryError.invalidArchive}
            switch entry.phase {
            case .confirmed: guard !incomplete else {throw ChatHistoryError.invalidArchive}
            case .uncertain: guard !incomplete else {throw ChatHistoryError.invalidArchive};uncertain+=1;incomplete=true
            case .ready: incomplete=true
            }
        }
        guard uncertain<=1 else {throw ChatHistoryError.invalidArchive}
        guard try JSONEncoder().encode(batch).count<=Self.maxArchiveBytes else {throw ChatHistoryError.capacity}
    }

    private func readSnapshot() throws -> Snapshot {
        guard let snapshot=try archive.load(Snapshot.self) else {
            return Snapshot(version:1,pending:nil,expired:nil,queued:nil)
        }
        guard snapshot.version==1 || snapshot.version==2,
              snapshot.version != 1 || snapshot.queued == nil,
              snapshot.version != 2 || snapshot.queued != nil else {throw ChatHistoryError.invalidArchive}
        let queued=snapshot.queued ?? []
        guard queued.isEmpty || snapshot.pending != nil else {throw ChatHistoryError.invalidArchive}
        let batches=[snapshot.pending].compactMap{$0}+queued
        guard batches.count<=Self.maximumPendingGroups,
              Set(batches.map(\.groupID)).count==batches.count,
              queued.allSatisfy({$0.entries.allSatisfy{$0.phase == .ready}}) else {
            throw ChatHistoryError.invalidArchive
        }
        var ids=Set<String>()
        for batch in batches {
            try validate(batch)
            for entry in batch.entries {
                guard ids.insert(entry.envelope.id).inserted else {throw ChatHistoryError.invalidArchive}
            }
        }
        guard try JSONEncoder().encode(batches).count<=Self.maxArchiveBytes else {throw ChatHistoryError.capacity}
        let expired=snapshot.expired ?? []
        guard expired.count<=200,
              Set(expired.map(\.groupID)).count==expired.count,
              expired.allSatisfy({record in
                  EncryptedTicketMessage.validID(record.groupID) &&
                  (1...1024).contains(record.entries.count) &&
                  Set(record.entries.map(\.id)).count==record.entries.count &&
                  record.entries.contains(where:{$0.phase != .confirmed}) &&
                  record.entries.allSatisfy({EncryptedTicketMessage.validID($0.id) &&
                      $0.digest.utf8.count==64 && $0.digest.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})})
              }),
              !expired.contains(where:{record in batches.contains(where:{$0.groupID==record.groupID}) ||
                  record.entries.contains(where:{ids.contains($0.id)})})
        else {throw ChatHistoryError.invalidArchive}
        return snapshot
    }

    func pending() throws -> Pending? {try readSnapshot().pending}
    func expiredRecords() throws -> [ExpiredRecord] {try readSnapshot().expired ?? []}

    func pendingGroups() throws -> [Pending] {
        let old=try readSnapshot()
        return [old.pending].compactMap{$0}+(old.queued ?? [])
    }

    private func persist(_ batches:[Pending],expired:[ExpiredRecord]?) throws {
        let records=expired ?? []
        guard batches.count<=Self.maximumPendingGroups else {throw ChatHistoryError.capacity}
        guard Set(batches.map(\.groupID)).count==batches.count,
              batches.dropFirst().allSatisfy({$0.entries.allSatisfy{$0.phase == .ready}}),
              !records.contains(where:{record in batches.contains(where:{$0.groupID==record.groupID})})
        else {throw ChatHistoryError.invalidArchive}
        var ids=Set(records.flatMap{$0.entries.map(\.id)})
        for batch in batches {
            try validate(batch)
            for entry in batch.entries {
                guard ids.insert(entry.envelope.id).inserted else {throw ChatHistoryError.invalidArchive}
            }
        }
        guard try JSONEncoder().encode(batches).count<=Self.maxArchiveBytes else {throw ChatHistoryError.capacity}
        // One authenticated atomic replacement; a crash cannot orphan the tail.
        try archive.save(Snapshot(version:2,pending:batches.first,expired:expired,
                                  queued:Array(batches.dropFirst())))
    }

    private func save(_ batch:Pending?) throws {
        let old=try readSnapshot()
        if let batch,let head=old.pending,head.groupID != batch.groupID {
            throw ChatHistoryError.invalidArchive
        }
        try persist([batch].compactMap{$0}+(old.queued ?? []),expired:old.expired)
    }

    func expiredPending(now:Date = .now) throws -> Pending? {
        guard let batch=try pending(),
              batch.entries.contains(where:{$0.phase != .confirmed}),
              let first=batch.entries.first?.envelope,
              let stamp=ISO8601DateFormatter().date(from:first.createdAt),
              now.timeIntervalSince(stamp)>=90 else {return nil}
        return batch
    }

    /// No transport action is performed. The caller must first durably mark
    /// the local history as an unknown delivery outcome, then release the slot.
    /// Keep bounded, encrypted per-envelope audit metadata, not media copies.
    func closeExpiredAfterHistoryCommit(groupID:String,now:Date = .now) throws {
        guard let batch=try expiredPending(now:now),batch.groupID==groupID else {
            throw ChatHistoryError.busy
        }
        let old=try readSnapshot()
        var records=old.expired ?? []
        let entries=try batch.entries.map {
            ExpiredRecord.EntrySummary(id:$0.envelope.id,
                digest:try ChatSendReceiptV1.digest($0.envelope),phase:$0.phase)
        }
        records.append(ExpiredRecord(groupID:groupID,closedAt:now,entries:entries))
        records=Array(records.suffix(200))
        try persist(old.queued ?? [],expired:records)
    }

    func stage(groupID:String,recipients:[ChatIdentity],envelopes:[ChatEnvelope]) throws {
        let batch=Pending(scope:scope,groupID:groupID,recipients:recipients.map(TicketIdentityBinding.canonical),
            entries:envelopes.map{Entry(envelope:$0,phase:.ready)})
        if let old=try pending() {
            guard old==batch else {throw ChatHistoryError.busy}
            return
        }
        try save(batch)
    }

    /// Explicit multi-group API. The existing single-slot stage API stays
    /// fail-closed until ChatModel and history eviction are queue-aware.
    /// Only the FIFO head can enter the transport; staging never sends.
    func enqueue(groupID:String,recipients:[ChatIdentity],envelopes:[ChatEnvelope]) throws {
        let batch=Pending(scope:scope,groupID:groupID,recipients:recipients.map(TicketIdentityBinding.canonical),
            entries:envelopes.map{Entry(envelope:$0,phase:.ready)})
        let old=try readSnapshot()
        let batches=[old.pending].compactMap{$0}+(old.queued ?? [])
        if let existing=batches.first(where:{$0.groupID==groupID}) {
            guard existing==batch else {throw ChatHistoryError.busy}
            return
        }
        try persist(batches+[batch],expired:old.expired)
    }

    /// Caller must revalidate the entire peer roster with the authenticated
    /// server before sending, including before an explicitly negotiated replay.
    func beginNext(currentRecipients:[ChatIdentity],allowIdempotentReplay:Bool=false,now:Date = .now) throws -> ChatEnvelope? {
        guard var batch=try pending() else {return nil}
        let uncertain=batch.entries.firstIndex(where:{$0.phase == .uncertain})
        guard uncertain==nil || allowIdempotentReplay else {throw ChatHistoryError.busy}
        guard currentRecipients.count==batch.recipients.count,
              batch.recipients.allSatisfy({old in currentRecipients.contains(where:{TicketIdentityBinding.matches(old,$0)})})
        else {throw ChatError.identityChanged}
        guard let i=uncertain ?? batch.entries.firstIndex(where:{$0.phase == .ready}) else {return nil}
        let envelope=batch.entries[i].envelope
        // Do not submit stale signed envelopes. The broker lifetime is
        // shorter than the client's incoming timestamp window.
        guard let stamp=ISO8601DateFormatter().date(from:envelope.createdAt),
              now.timeIntervalSince(stamp)>=(-5),now.timeIntervalSince(stamp)<90 else {
            throw ChatError.invalidEnvelope
        }
        if uncertain==nil {
            batch.entries[i].phase = .uncertain
            try save(batch) // durable before returning anything to the transport
        }
        return envelope
    }

    func confirm(_ envelope:ChatEnvelope,receipt:ChatSendReceiptV1) throws {
        try receipt.requireMatch(envelope)
        guard var batch=try pending(),
              let i=batch.entries.firstIndex(where:{$0.phase == .uncertain}),
              batch.entries[i].envelope==envelope
        else {throw ChatError.invalidResponse}
        batch.entries[i].phase = .confirmed
        try save(batch)
    }

    /// Call only after the associated message's queued delivery state has
    /// been committed to the active history store.
    func finishAfterHistoryCommit(groupID:String) throws {
        guard let batch=try pending(),batch.groupID==groupID,
              batch.entries.allSatisfy({$0.phase == .confirmed}) else {throw ChatHistoryError.busy}
        try save(nil)
    }
}
