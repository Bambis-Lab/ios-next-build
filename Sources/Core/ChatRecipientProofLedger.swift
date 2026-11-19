import Foundation

/// Local-only sender expectations. These are created from a fully confirmed
/// outbox head before that head can be forgotten. No server-provided roster
/// or replacement key can change an existing expectation.
struct ChatRecipientProofSummary:Equatable,Sendable {
    let confirmedUsers:Int
    let totalUsers:Int
    let confirmedDevices:Int
    let totalDevices:Int
    var allConfirmed:Bool {totalDevices>0 && confirmedDevices==totalDevices && totalUsers>0 && confirmedUsers==totalUsers}
}

@MainActor
final class ChatRecipientProofLedger {
    struct Fragment:Codable,Equatable {
        let id:String
        let digest:String
        let index:Int
        let count:Int
        let recipient:ChatIdentity
        var proof:ChatRecipientProofV1?
    }
    struct Group:Codable,Equatable {
        let id:String
        var fragments:[Fragment]
    }
    private struct Snapshot:Codable {
        let version:Int
        let scope:ChatOutboxScope
        var groups:[Group]
    }
    private let scope:ChatOutboxScope
    private let archive:ChatHistoryArchive
    static let maximumGroups=200
    static let maximumFragments=20000

    convenience init(scope:ChatOutboxScope) throws {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.sortedKeys]
        let archive=try ChatHistoryArchive(scopedData:encoder.encode(scope),
            namespace:"chatRecipientProof.v1",folder:"EncryptedChatRecipientProof")
        try self.init(scope:scope,archive:archive)
    }

    init(scope:ChatOutboxScope,archive:ChatHistoryArchive) throws {
        guard scope.endpoint.scheme=="https",!scope.user.isEmpty,!scope.device.isEmpty,
              !scope.keyFingerprint.isEmpty else {throw ChatHistoryError.invalidScope}
        self.scope=scope
        self.archive=archive
    }

    private func verify(_ proof:ChatRecipientProofV1,fragment:Fragment) throws {
        try proof.verify(expectedID:fragment.id,expectedDigest:fragment.digest,
             senderUser:scope.user,senderDevice:scope.device,recipient:fragment.recipient)
    }

    private func validate(_ snapshot:Snapshot) throws {
        let groups=snapshot.groups,all=groups.flatMap(\.fragments)
        guard snapshot.version==1,snapshot.scope==scope,groups.count<=Self.maximumGroups,
              all.count<=Self.maximumFragments,Set(groups.map(\.id)).count==groups.count,
              Set(all.map(\.id)).count==all.count else {throw ChatHistoryError.invalidArchive}
        for group in groups {
            guard EncryptedTicketMessage.validID(group.id),!group.fragments.isEmpty,
                  group.fragments.count<=1024 else {throw ChatHistoryError.invalidArchive}
            for device in Dictionary(grouping:group.fragments,by:{$0.recipient.deviceID}).values {
                guard let first=device.first,EncryptedTicketMessage.validIdentity(first.recipient),
                      first.recipient.userID != scope.user,first.recipient.deviceID != scope.device,
                      (1...256).contains(first.count),device.count==first.count,
                      Set(device.map(\.index))==Set(0..<first.count),
                      device.allSatisfy({TicketIdentityBinding.matches($0.recipient,first.recipient) && $0.count==first.count})
                else {throw ChatHistoryError.invalidArchive}
                for f in device {
                    guard EncryptedTicketMessage.validID(f.id),f.digest.utf8.count==64,
                          f.digest.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
                    else {throw ChatHistoryError.invalidArchive}
                    if let proof=f.proof {try verify(proof,fragment:f)}
                }
            }
        }
    }
    private func load() throws -> Snapshot {
        let snapshot=try archive.load(Snapshot.self) ?? Snapshot(version:1,scope:scope,groups:[])
        try validate(snapshot)
        return snapshot
    }
    private func save(_ snapshot:Snapshot) throws {
        try validate(snapshot)
        try archive.save(snapshot)
    }

    /// Reserve metadata budget before any new group is submitted, including
    /// all already queued groups. This is a read-only preflight; the caller
    /// serializes sends and retains the authenticated outbox as the reservation.
    func requireCapacity(groupSizes:[String:Int],retaining retainedGroupIDs:Set<String>) throws {
        guard groupSizes.keys.allSatisfy({retainedGroupIDs.contains($0) && EncryptedTicketMessage.validID($0)}),
              groupSizes.values.allSatisfy({(1...1024).contains($0)}) else {throw ChatHistoryError.invalidArchive}
        var counts=Dictionary(uniqueKeysWithValues:try load().groups
            .filter{retainedGroupIDs.contains($0.id)}.map{($0.id,$0.fragments.count)})
        for (id,count) in groupSizes {
            if let existing=counts[id],existing != count {throw ChatHistoryError.invalidArchive}
            counts[id]=count
        }
        guard counts.count<=Self.maximumGroups,
              counts.values.reduce(0,+)<=Self.maximumFragments else {throw ChatHistoryError.capacity}
    }

    /// Caller passes an authenticated outbox snapshot; incomplete or uncertain
    /// heads must remain in the outbox and cannot become delivery expectations.
    func registerConfirmed(_ pending:DurableChatOutbox.Pending, retaining retainedGroupIDs:Set<String>?=nil) throws {
        guard pending.scope==scope,!pending.entries.isEmpty,
              pending.entries.allSatisfy({$0.phase == .confirmed}) else {throw ChatHistoryError.invalidArchive}
        let fragments=try pending.entries.map { entry -> Fragment in
            let e=entry.envelope
            guard e.groupID==pending.groupID,e.senderUserID==scope.user,e.senderDeviceID==scope.device,
                  let peer=pending.recipients.first(where:{$0.userID==e.recipientUserID && $0.deviceID==e.recipientDeviceID})
            else {throw ChatHistoryError.invalidArchive}
            return Fragment(id:e.id,digest:try ChatSendReceiptV1.digest(e),index:e.chunkIndex,count:e.chunkCount,recipient:peer,proof:nil)
        }
        guard Set(fragments.map{$0.recipient.deviceID})==Set(pending.recipients.map(\.deviceID)),
              Set(pending.recipients.map(\.deviceID)).count==pending.recipients.count
        else {throw ChatHistoryError.invalidArchive}
        var snapshot=try load()
        // Only derived delivery metadata for messages no longer present in
        // the durable history may be retired. Always protect the in-flight head.
        // No history, message, device identity or key is modified here.
        if let retainedGroupIDs {
            guard retainedGroupIDs.contains(pending.groupID) else {throw ChatHistoryError.invalidArchive}
            snapshot.groups.removeAll{!retainedGroupIDs.contains($0.id)}
        }
        if let existing=snapshot.groups.first(where:{$0.id==pending.groupID}) {
            let baseline=existing.fragments.map { f -> Fragment in var v=f;v.proof=nil;return v }
            guard baseline==fragments else {throw ChatHistoryError.invalidArchive}
            if retainedGroupIDs != nil {try save(snapshot)}
            return
        }
        guard snapshot.groups.count<Self.maximumGroups,
              snapshot.groups.flatMap(\.fragments).count+fragments.count<=Self.maximumFragments
        else {throw ChatHistoryError.capacity}
        snapshot.groups.append(Group(id:pending.groupID,fragments:fragments))
        try save(snapshot)
    }

    /// Batch processing is atomic: one unknown or invalid proof changes nothing.
    private func updating(_ proofs:[ChatRecipientProofV1],snapshot:Snapshot) throws -> Snapshot {
        var updated=snapshot
        var locations:[String:(Int,Int)]=[:]
        for i in snapshot.groups.indices {
            for j in snapshot.groups[i].fragments.indices {
                locations[snapshot.groups[i].fragments[j].id]=(i,j)
            }
        }
        for proof in proofs {
            guard let (i,j)=locations[proof.id] else {throw ChatHistoryError.invalidArchive}
            let fragment=updated.groups[i].fragments[j]
            try verify(proof,fragment:fragment)
            if let old=fragment.proof,old != proof {throw ChatHistoryError.invalidArchive}
            updated.groups[i].fragments[j].proof=proof
        }
        return updated
    }

    func apply(_ proofs:[ChatRecipientProofV1]) throws {
        guard (1...256).contains(proofs.count),Set(proofs.map(\.id)).count==proofs.count
        else {throw ChatHistoryError.invalidArchive}
        let next=try updating(proofs,snapshot:load())
        try save(next)
    }

    /// A query can be in flight while history retires an old group. Only
    /// solicited IDs may be ignored. Reload after network suspension, then
    /// verify and commit a single atomic batch and reuse its verified summary.
    @discardableResult
    func applyQuery(_ proofs:[ChatRecipientProofV1],requested:[String]) throws -> [String:ChatRecipientProofSummary] {
        guard (1...256).contains(requested.count),Set(requested).count==requested.count,
              proofs.count<=requested.count,Set(proofs.map(\.id)).count==proofs.count,
              Set(proofs.map(\.id)).isSubset(of:Set(requested)) else {throw ChatHistoryError.invalidArchive}
        let snapshot=try load()
        let known=Set(snapshot.groups.flatMap(\.fragments).map(\.id))
        let applicable=proofs.filter{known.contains($0.id)}
        guard !applicable.isEmpty else {return summaries(snapshot)}
        let next=try updating(applicable,snapshot:snapshot)
        try save(next)
        return summaries(next)
    }

    func unconfirmedIDs(limit:Int=256) throws -> [String] {
        guard (1...256).contains(limit) else {throw ChatHistoryError.invalidArchive}
        return Array(try load().groups.flatMap(\.fragments).filter{$0.proof==nil}.map(\.id).prefix(limit))
    }

    /// Rotate across unresolved IDs, not just the oldest page, so an offline
    /// recipient cannot starve later messages.
    func nextUnconfirmedIDs(after cursor:String?,limit:Int=256) throws -> [String] {
        guard (1...256).contains(limit) else {throw ChatHistoryError.invalidArchive}
        return try pollPage(after:cursor,limit:limit).ids
    }

    func pollPage(after cursor:String?,limit:Int=256) throws -> (ids:[String],summaries:[String:ChatRecipientProofSummary]) {
        guard (1...256).contains(limit) else {throw ChatHistoryError.invalidArchive}
        let snapshot=try load()
        let ids=snapshot.groups.flatMap(\.fragments).filter{$0.proof==nil}.map(\.id).sorted()
        let ordered:[String]
        if let cursor {ordered=ids.filter{$0>cursor}+ids.filter{$0<=cursor}}
        else {ordered=ids}
        return (Array(ordered.prefix(limit)),summaries(snapshot))
    }

    func summaries() throws -> [String:ChatRecipientProofSummary] {try summaries(load())}

    private func summaries(_ snapshot:Snapshot) -> [String:ChatRecipientProofSummary] {
        var result:[String:ChatRecipientProofSummary]=[:]
        for group in snapshot.groups {
            let users=Dictionary(grouping:group.fragments,by:{$0.recipient.userID})
            let devices=Dictionary(grouping:group.fragments,by:{$0.recipient.deviceID})
            result[group.id]=ChatRecipientProofSummary(
                confirmedUsers:users.values.filter{$0.allSatisfy{$0.proof != nil}}.count,totalUsers:users.count,
                confirmedDevices:devices.values.filter{$0.allSatisfy{$0.proof != nil}}.count,totalDevices:devices.count)
        }
        return result
    }

    /// A device is complete only when every expected fragment is attested.
    /// A user is complete only when all initially targeted devices are complete.
    func confirmedUsers(groupID:String) throws -> Set<String> {
        guard let g=try load().groups.first(where:{$0.id==groupID}) else {return []}
        let users=Dictionary(grouping:g.fragments,by:{$0.recipient.userID})
        return Set(users.filter{$0.value.allSatisfy{$0.proof != nil}}.keys)
    }

    func confirmedDevices(groupID:String) throws -> Set<String> {
        guard let g=try load().groups.first(where:{$0.id==groupID}) else {return []}
        return Set(Dictionary(grouping:g.fragments,by:{$0.recipient.deviceID})
            .filter{$0.value.allSatisfy{$0.proof != nil}}.keys)
    }
}
