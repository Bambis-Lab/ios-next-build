import Foundation
import CryptoKit

/// Versioned ticket wire format. Ticket and message IDs are signed with each
/// recipient copy. A ticket is initially bound to two independently verified
/// devices (requester and owner). No silent key replacement or plaintext fallback.
struct EncryptedTicketMessage: Codable, Equatable, Sendable {
    static let contentType = "application/vnd.iosnext.ticket.v1+text"
    let version: Int
    let ticketID: String
    let messageID: String
    let copies: [ChatEnvelope]

    enum CodingKeys: String, CodingKey {
        case version, copies
        case ticketID = "ticket_id"
        case messageID = "message_id"
    }

    static func validID(_ id: String) -> Bool {
        UUID(uuidString: id)?.uuidString.lowercased() == id
    }

    static func validIdentity(_ identity: ChatIdentity) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@".utf8)
        return [identity.userID, identity.deviceID].allSatisfy {
            (1...64).contains($0.utf8.count) && $0.utf8.allSatisfy { allowed.contains($0) }
        } && Data(base64Encoded: identity.signingPublicKey)?.count == 32
          && Data(base64Encoded: identity.agreementPublicKey)?.count == 32
    }

    static func seal(text: String, ticketID: String, author: ChatIdentity,
                     counterparty: ChatIdentity, confirmedSafetyNumber: String,
                     keys: ChatDeviceKeys, now: Date = .now) throws -> Self {
        let bytes = Data(text.utf8)
        guard validID(ticketID), (1...16_000).contains(bytes.count),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validIdentity(author), validIdentity(counterparty),
              author.userID != counterparty.userID, author.deviceID != counterparty.deviceID,
              author.signingPublicKey == keys.signing.publicKey.rawRepresentation.base64EncodedString(),
              author.agreementPublicKey == keys.agreement.publicKey.rawRepresentation.base64EncodedString(),
              ChatDeviceKeys.safetyNumber(for: counterparty) == confirmedSafetyNumber else {
            throw ChatError.invalidEnvelope
        }
        let messageID = UUID().uuidString.lowercased()
        let timestamp = ISO8601DateFormatter().string(from: now)
        let copies = try [author, counterparty].map { recipient in
            try keys.encrypt(bytes, kind: .text, contentType: contentType,
                groupID: messageID, chunkIndex: 0, chunkCount: 1, sender: author,
                recipient: recipient, createdAt: timestamp, conversationID: "ticket:" + ticketID)
        }
        return .init(version: 1, ticketID: ticketID, messageID: messageID, copies: copies)
    }

    /// The recipient and author must be supplied from authenticated, independently
    /// verified identity records. Validate both signed copies before opening.
    func open(expectedTicketID: String, author: ChatIdentity, counterparty: ChatIdentity,
              confirmedSafetyNumber: String, local: ChatIdentity, keys: ChatDeviceKeys) throws -> String {
        guard version == 1, ticketID == expectedTicketID, Self.validID(ticketID), Self.validID(messageID),
              Self.validIdentity(author), Self.validIdentity(counterparty),
              author.userID != counterparty.userID, author.deviceID != counterparty.deviceID,
              local == author || local == counterparty,
              local.agreementPublicKey == keys.agreement.publicKey.rawRepresentation.base64EncodedString(),
              local.signingPublicKey == keys.signing.publicKey.rawRepresentation.base64EncodedString(),
              ChatDeviceKeys.safetyNumber(for: local == author ? counterparty : author) == confirmedSafetyNumber,
              copies.count == 2, Set(copies.map(\.id)).count == 2,
              Set(copies.map { [$0.recipientUserID, $0.recipientDeviceID] }) ==
                Set([[author.userID, author.deviceID], [counterparty.userID, counterparty.deviceID]]),
              let signing = Data(base64Encoded: author.signingPublicKey) else { throw ChatError.invalidEnvelope }
        let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: signing)
        for envelope in copies {
            guard Self.validID(envelope.id), envelope.groupID == messageID,
                  envelope.conversationID == "ticket:" + ticketID,
                  envelope.senderUserID == author.userID, envelope.senderDeviceID == author.deviceID,
                  envelope.messageType == .text, envelope.contentType == Self.contentType,
                  envelope.chunkIndex == 0, envelope.chunkCount == 1,
                  envelope.createdAt == copies[0].createdAt,
                  ISO8601DateFormatter().date(from: envelope.createdAt) != nil,
                  Data(base64Encoded: envelope.ephemeralPublicKey)?.count == 32,
                  envelope.ciphertext.utf8.count <= 21_372,
                  let data = Data(base64Encoded: envelope.ciphertext), (29...16_028).contains(data.count),
                  let sig = Data(base64Encoded: envelope.signature), sig.count == 64,
                  verifier.isValidSignature(sig, for: try envelope.signingData()) else {
                throw ChatError.invalidSignature
            }
        }
        guard let copy = copies.first(where: {
            $0.recipientUserID == local.userID && $0.recipientDeviceID == local.deviceID
        }) else { throw ChatError.invalidEnvelope }
        let plain = try keys.decrypt(copy, sender: author)
        guard (1...16_000).contains(plain.count), let text = String(data: plain, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatError.invalidEnvelope }
        return text
    }
}
