import Foundation

/// One durable, exact pending request per role/account/device/key scope.
/// Only already signed ciphertext and public identities enter this archive.
/// A persisted pending request must be acknowledged before another is staged.
@MainActor
final class SecureTicketOutbox {
    private struct Snapshot: Codable {
        let version: Int
        let pending: TicketPendingSend?
    }
    private let archive: ChatHistoryArchive
    private let scope: TicketScreenScope

    convenience init(scope: TicketScreenScope) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(scope)
        let archive = try ChatHistoryArchive(scopedData: data, namespace: "ticketOutbox.v1", folder: "EncryptedTicketOutbox")
        self.init(scope: scope, archive: archive)
    }

    init(scope: TicketScreenScope, archive: ChatHistoryArchive) {
        self.scope = scope
        self.archive = archive
    }

    func pending() throws -> TicketPendingSend? {
        guard let state = try archive.load(Snapshot.self) else { return nil }
        guard state.version == 1 else { throw ChatHistoryError.invalidArchive }
        if let value = state.pending { try validate(value) }
        return state.pending
    }

    private func validate(_ value: TicketPendingSend) throws {
        guard value.scope == scope, !value.create || !scope.owner,
              EncryptedTicketMessage.validID(value.message.ticketID),
              EncryptedTicketMessage.validID(value.message.messageID),
              value.message.version == 1, value.message.copies.count == 2,
              EncryptedTicketMessage.validIdentity(value.peer),
              value.peer.userID != scope.user, value.peer.deviceID != scope.device,
              value.message.copies.allSatisfy({ $0.senderUserID == scope.user && $0.senderDeviceID == scope.device }),
              Set(value.message.copies.map { [$0.recipientUserID, $0.recipientDeviceID] })
                == Set([[scope.user, scope.device], [value.peer.userID, value.peer.deviceID]])
        else { throw ChatHistoryError.invalidArchive }
    }

    func stage(_ value: TicketPendingSend) throws {
        try validate(value)
        if let previous = try pending() {
            guard previous == value else { throw ChatHistoryError.capacity }
            return
        }
        try archive.save(Snapshot(version: 1, pending: value))
    }

    /// The caller must have a validated server receipt with the exact message.
    func acknowledge(_ value: TicketPendingSend, receipt: EncryptedTicketDetail) throws {
        let local=scope.owner ? receipt.owner : receipt.requester
        let peer=scope.owner ? receipt.requester : receipt.owner
        guard try pending() == value, receipt.ticketID == value.message.ticketID,
              receipt.messages.filter({$0.messageID==value.message.messageID}) == [value.message],
              local.userID==scope.user,local.deviceID==scope.device,
              ChatDeviceKeys.safetyNumber(for:local)==scope.keyFingerprint,
              TicketIdentityBinding.matches(peer,value.peer)
        else { throw ChatError.invalidResponse }
        try archive.save(Snapshot(version: 1, pending: nil))
    }
}
