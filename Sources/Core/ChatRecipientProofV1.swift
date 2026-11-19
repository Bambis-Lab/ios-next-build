import Foundation
import CryptoKit

/// An authenticated claim about a single encrypted envelope. Never use this
/// alone as proof of complete message assembly or of a human reading it.
struct ChatRecipientProofV1: Codable, Equatable, Sendable {
    let version:Int
    let id:String
    let envelopeSHA256:String
    let senderUserID:String
    let senderDeviceID:String
    let recipientUserID:String
    let recipientDeviceID:String
    let signature:String

    enum CodingKeys:String,CodingKey {
        case version,id,signature
        case envelopeSHA256="envelope_sha256"
        case senderUserID="sender_user_id"
        case senderDeviceID="sender_device_id"
        case recipientUserID="recipient_user_id"
        case recipientDeviceID="recipient_device_id"
    }

    private static func validID(_ s:String)->Bool {
        (1...90).contains(s.utf8.count) &&
        s.utf8.allSatisfy{ (48...57).contains($0) || (65...90).contains($0) ||
            (97...122).contains($0) || [45,46,64,95].contains($0) }
    }

    func signingBytes() throws -> Data {
        guard version==1,[id,senderUserID,senderDeviceID,recipientUserID,recipientDeviceID].allSatisfy(Self.validID),
              envelopeSHA256.utf8.count==64,
              envelopeSHA256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
        else {throw ChatError.invalidResponse}
        // All values are restricted ASCII without quotes, backslashes or
        // whitespace. Explicit key order matches Python's sort_keys=True.
        let canonical="{\"envelope_sha256\":\"\(envelopeSHA256)\",\"id\":\"\(id)\",\"recipient_device_id\":\"\(recipientDeviceID)\",\"recipient_user_id\":\"\(recipientUserID)\",\"sender_device_id\":\"\(senderDeviceID)\",\"sender_user_id\":\"\(senderUserID)\",\"version\":1}"
        return Data("iosnext/chat/recipient-persisted-envelope/v1".utf8)+Data([0])+Data(canonical.utf8)
    }

    /// Construct only a digest-bound unsigned claim. It becomes eligible for
    /// signing after the history checkpoint containing the fragment commits.
    static func unsignedClaim(_ envelope:ChatEnvelope) throws -> Self {
        let result=Self(version:1,id:envelope.id,envelopeSHA256:try ChatSendReceiptV1.digest(envelope),
            senderUserID:envelope.senderUserID,senderDeviceID:envelope.senderDeviceID,
            recipientUserID:envelope.recipientUserID,recipientDeviceID:envelope.recipientDeviceID,signature:"")
        _ = try result.signingBytes()
        return result
    }

    /// Caller must have durably committed the verified envelope first.
    static func signPersistedEnvelope(_ envelope:ChatEnvelope,local:ChatIdentity,keys:ChatDeviceKeys) throws -> Self {
        guard envelope.recipientUserID==local.userID,envelope.recipientDeviceID==local.deviceID,
              TicketIdentityBinding.matches(local,keys.publicIdentity(userID:local.userID,deviceID:local.deviceID))
        else {throw ChatError.identityChanged}
        let digest=try ChatSendReceiptV1.digest(envelope)
        let unsigned=Self(version:1,id:envelope.id,envelopeSHA256:digest,senderUserID:envelope.senderUserID,
            senderDeviceID:envelope.senderDeviceID,recipientUserID:local.userID,recipientDeviceID:local.deviceID,signature:"")
        let sig=try keys.signing.signature(for:unsigned.signingBytes()).base64EncodedString()
        return Self(version:1,id:unsigned.id,envelopeSHA256:digest,senderUserID:unsigned.senderUserID,
            senderDeviceID:unsigned.senderDeviceID,recipientUserID:local.userID,recipientDeviceID:local.deviceID,signature:sig)
    }

    func verify(expectedID:String,expectedDigest:String,senderUser:String,senderDevice:String,recipient:ChatIdentity) throws {
        guard id==expectedID,envelopeSHA256==expectedDigest,senderUserID==senderUser,senderDeviceID==senderDevice,
              recipientUserID==recipient.userID,recipientDeviceID==recipient.deviceID,
              EncryptedTicketMessage.validIdentity(recipient),
              let publicKey=Data(base64Encoded:recipient.signingPublicKey),
              signature.utf8.count==88,let sig=Data(base64Encoded:signature),sig.count==64,
              sig.base64EncodedString()==signature else {throw ChatError.invalidResponse}
        let key=try Curve25519.Signing.PublicKey(rawRepresentation:publicKey)
        guard key.isValidSignature(sig,for:try signingBytes()) else {throw ChatError.invalidResponse}
    }
}

/// Part of the encrypted history checkpoint, not a separate unbound replay
/// marker. A signed entry is immutable across ambiguous HTTP outcomes.
struct ChatPendingRecipientProof:Codable,Equatable,Sendable {
    let proof:ChatRecipientProofV1
    let keyFingerprint:String
    let committedAt:Date

    func signed(using keys:ChatDeviceKeys,configuration:ChatConfiguration) throws -> Self {
        guard keys.safetyNumber==keyFingerprint,
              proof.recipientUserID==configuration.userID,proof.recipientDeviceID==configuration.deviceID
        else {throw ChatError.identityChanged}
        let bytes=try proof.signingBytes()
        if !proof.signature.isEmpty {
            guard let sig=Data(base64Encoded:proof.signature),sig.count==64,
                  sig.base64EncodedString()==proof.signature,
                  keys.signing.publicKey.isValidSignature(sig,for:bytes)
            else {throw ChatHistoryError.invalidArchive}
            return self
        }
        let signature=try keys.signing.signature(for:bytes).base64EncodedString()
        let value=ChatRecipientProofV1(version:proof.version,id:proof.id,envelopeSHA256:proof.envelopeSHA256,
            senderUserID:proof.senderUserID,senderDeviceID:proof.senderDeviceID,recipientUserID:proof.recipientUserID,
            recipientDeviceID:proof.recipientDeviceID,signature:signature)
        return Self(proof:value,keyFingerprint:keyFingerprint,committedAt:committedAt)
    }
}
