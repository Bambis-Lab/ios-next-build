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
        let fragments:[Fragment]
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
    func apply(_ proofs:[ChatRecipientProofV1]) throws {
        guard (1...256).contains(proofs.count),Set(proofs.map(\.id)).count==proofs.count
        else {throw ChatHistoryError.invalidArchive}
        var snapshot=try load()
        for proof in proofs {
            guard let i=snapshot.groups.firstIndex(where:{$0.fragments.contains(where:{$0.id==proof.id})}),
                  let j=snapshot.groups[i].fragments.firstIndex(where:{$0.id==proof.id})
            else {throw ChatHistoryError.invalidArchive}
            var entries=snapshot.groups[i].fragments
            try verify(proof,fragment:entries[j])
            if let old=entries[j].proof,old != proof {throw ChatHistoryError.invalidArchive}
            entries[j].proof=proof
            snapshot.groups[i]=Group(id:snapshot.groups[i].id,fragments:entries)
        }
        try save(snapshot)
    }

    /// A query can be in flight while the history retires an old group.
    /// Reject unsolicited IDs; ignore only requested IDs no longer retained.
    func applyQuery(_ proofs:[ChatRecipientProofV1],requested:[String]) throws {
        guard (1...256).contains(requested.count),Set(requested).count==requested.count,
              proofs.count<=requested.count,Set(proofs.map(\.id)).count==proofs.count,
              Set(proofs.map(\.id)).isSubset(of:Set(requested)) else {throw ChatHistoryError.invalidArchive}
        let known=Set(try load().groups.flatMap(\.fragments).map(\.id))
        let applicable=proofs.filter{known.contains($0.id)}
        if !applicable.isEmpty {try apply(applicable)}
    }

    func unconfirmedIDs(limit:Int=256) throws -> [String] {
        guard (1...256).contains(limit) else {throw ChatHistoryError.invalidArchive}
        return Array(try load().groups.flatMap(\.fragments).filter{$0.proof==nil}.map(\.id).prefix(limit))
    }

    /// Rotate across unresolved IDs, not just the oldest page, so an offline
    /// recipient cannot starve later messages.
    func nextUnconfirmedIDs(after cursor:String?,limit:Int=256) throws -> [String] {
        guard (1...256).contains(limit) else {throw ChatHistoryError.invalidArchive}
        let ids=try load().groups.flatMap(\.fragments).filter{$0.proof==nil}.map(\.id).sorted()
        guard let cursor else {return Array(ids.prefix(limit))}
        let later=ids.filter{$0>cursor}
        let earlier=ids.filter{$0<=cursor}
        return Array((later+earlier).prefix(limit))
    }

    func summaries() throws -> [String:ChatRecipientProofSummary] {
        var result:[String:ChatRecipientProofSummary]=[:]
        for group in try load().groups {
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
