import Foundation

/// Fences asynchronous cache publications against superseding reads and writes.
struct TicketReadRequestFence {
    private(set) var scope:TicketScreenScope?
    private var revision:UInt64=0

    mutating func begin(_ scope:TicketScreenScope)->UInt64 {
        revision &+= 1
        self.scope=scope
        return revision
    }

    mutating func invalidate() {
        revision &+= 1
        scope=nil
    }

    func accepts(_ candidate:UInt64,scope:TicketScreenScope)->Bool {
        revision==candidate && self.scope==scope
    }
}

/// In-memory, scope-bound offline read window. Only construct following a
/// successful authorized server request. Never persist a lease or credentials.
/// A device revoked while truly offline cannot be detected immediately.
struct TicketOfflineLease: Sendable {
    let scope: TicketScreenScope
    let generation: UInt64
    private let deadline: ContinuousClock.Instant
    private let wallDeadline: Date

    init(scope: TicketScreenScope, verifiedGrantExpiry: Date, generation: UInt64 = 0, now: Date = .now) throws {
        let seconds = min(scope.owner ? 60.0 : 120.0,verifiedGrantExpiry.timeIntervalSince(now)-15)
        guard seconds > 0, seconds.isFinite else { throw ChatError.authenticationFailed }
        self.scope=scope
        self.generation=generation
        wallDeadline=now.addingTimeInterval(seconds)
        deadline=ContinuousClock().now.advanced(by:.milliseconds(Int64(seconds*1000)))
    }

    func require(_ expected: TicketScreenScope, generation expectedGeneration: UInt64? = nil, now: Date = .now) throws {
        guard expected==scope, expectedGeneration == nil || expectedGeneration == generation,
              now < wallDeadline, ContinuousClock().now < deadline else {
            throw ChatError.authenticationFailed
        }
    }
}

/// Authorization failures, TLS errors and cancellation never permit fallback.
enum TicketOfflineFallbackPolicy {
    static func allows(_ error: Error) -> Bool {
        guard let network = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .dnsLookupFailed].contains(network.code)
    }
}

/// Ciphertext-only offline cache. No decrypted messages or authorization
/// tokens are saved. Existing signature/key confirmation still runs when a
/// detail is opened. Not a replacement for server authorization or an outbox.
@MainActor
final class SecureTicketCache {
    private struct Snapshot: Codable {
        let version: Int
        var summaries: [EncryptedTicketSummary]
        var details: [String:EncryptedTicketDetail]
    }
    private let scope: TicketScreenScope
    private let local: ChatIdentity
    private let archive: ChatHistoryArchive
    private static let limit=24*1024*1024

    convenience init(scope: TicketScreenScope, local: ChatIdentity) throws {
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys]
        let archive=try ChatHistoryArchive(scopedData:encoder.encode(scope),
            namespace:"ticketCache.v1",folder:"EncryptedTicketCache")
        try self.init(scope:scope,local:local,archive:archive)
    }

    init(scope: TicketScreenScope, local: ChatIdentity, archive: ChatHistoryArchive) throws {
        guard local.userID==scope.user,local.deviceID==scope.device,
              EncryptedTicketMessage.validIdentity(local),
              ChatDeviceKeys.safetyNumber(for:local)==scope.keyFingerprint else {
            throw ChatError.identityChanged
        }
        self.scope=scope; self.local=TicketIdentityBinding.canonical(local); self.archive=archive
    }

    private func allowed(_ requester: ChatIdentity,_ owner: ChatIdentity) -> Bool {
        EncryptedTicketMessage.validIdentity(requester) && EncryptedTicketMessage.validIdentity(owner) &&
        requester.userID != owner.userID && requester.deviceID != owner.deviceID &&
        TicketIdentityBinding.matches(local,scope.owner ? owner : requester)
    }

    private func matches(_ detail: EncryptedTicketDetail,_ summary: EncryptedTicketSummary) -> Bool {
        detail.ticketID==summary.ticketID && detail.status==summary.status &&
        TicketIdentityBinding.matches(detail.requester,summary.requester) &&
        TicketIdentityBinding.matches(detail.owner,summary.owner)
    }

    private func validate(_ snapshot: Snapshot) throws {
        guard snapshot.version==1,snapshot.summaries.count<=1000,
              Set(snapshot.summaries.map(\.ticketID)).count==snapshot.summaries.count,
              snapshot.summaries.allSatisfy({ EncryptedTicketMessage.validID($0.ticketID) && allowed($0.requester,$0.owner) }),
              snapshot.details.count<=32 else { throw ChatHistoryError.invalidArchive }
        for (id,detail) in snapshot.details {
            guard let summary=snapshot.summaries.first(where:{$0.ticketID==id}),
                  matches(detail,summary),(1...200).contains(detail.messages.count),
                  Set(detail.messages.map(\.messageID)).count==detail.messages.count,
                  detail.messages.allSatisfy({ message in
                      message.version==1 && message.ticketID==id &&
                      EncryptedTicketMessage.validID(message.messageID) && message.copies.count==2 &&
                      message.copies.allSatisfy({ envelope in
                          envelope.ciphertext.utf8.count<=21372 &&
                          envelope.signature.utf8.count<=128 &&
                          envelope.ephemeralPublicKey.utf8.count<=64
                      })
                  }) else { throw ChatHistoryError.invalidArchive }
        }
        guard try JSONEncoder().encode(snapshot).count <= Self.limit else { throw ChatHistoryError.capacity }
    }

    private func read() throws -> Snapshot {
        let snapshot=try archive.load(Snapshot.self) ?? Snapshot(version:1,summaries:[],details:[:])
        try validate(snapshot)
        return snapshot
    }

    private func save(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        try archive.save(snapshot)
    }

    /// Input must be the complete authenticated pagination result. Removed
    /// tickets, changed peer bindings and changed statuses prune old details.
    func replaceList(_ list:[EncryptedTicketSummary],lease:TicketOfflineLease) throws {
        try lease.require(scope)
        var snapshot=try read()
        snapshot.summaries=list
        snapshot.details=snapshot.details.filter { pair in
            list.contains(where:{ matches(pair.value,$0) })
        }
        try save(snapshot)
    }

    /// Input must come from a successfully authorized, validated detail call.
    /// Cache may be full; preserve the committed archive on failure.
    func putDetail(_ detail:EncryptedTicketDetail,lease:TicketOfflineLease) throws {
        try lease.require(scope)
        var snapshot=try read()
        let summary=EncryptedTicketSummary(ticketID:detail.ticketID,requester:detail.requester,
            owner:detail.owner,status:detail.status)
        snapshot.summaries.removeAll(where:{$0.ticketID==detail.ticketID})
        snapshot.summaries.append(summary)
        snapshot.details[detail.ticketID]=detail
        try save(snapshot)
    }

    func list(lease:TicketOfflineLease) throws -> [EncryptedTicketSummary] {
        try lease.require(scope)
        return try read().summaries
    }

    func detail(_ id:String,lease:TicketOfflineLease) throws -> EncryptedTicketDetail? {
        try lease.require(scope)
        return try read().details[id]
    }

    /// Call on confirmed authorization loss. No automatic regrant and no
    /// plaintext fallback. Unsent outbox is separate and never deleted here.
    func invalidate() throws {
        try save(Snapshot(version:1,summaries:[],details:[:]))
    }
}
