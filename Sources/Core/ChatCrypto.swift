import CryptoKit
import Foundation
import Security

struct ChatDeviceKeys: Sendable {
    private static let agreementAccount = "chatAgreementPrivateKey"
    private static let signingAccount = "chatSigningPrivateKey"

    let agreement: Curve25519.KeyAgreement.PrivateKey
    let signing: Curve25519.Signing.PrivateKey

    static func loadOrCreate() throws -> ChatDeviceKeys {
        let agreement: Curve25519.KeyAgreement.PrivateKey
        if let raw = try KeychainStore.data(account: agreementAccount) {
            agreement = try .init(rawRepresentation: raw)
        } else {
            agreement = .init()
            try KeychainStore.save(
                agreement.rawRepresentation,
                account: agreementAccount,
                accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            )
        }

        let signing: Curve25519.Signing.PrivateKey
        if let raw = try KeychainStore.data(account: signingAccount) {
            signing = try .init(rawRepresentation: raw)
        } else {
            signing = .init()
            try KeychainStore.save(
                signing.rawRepresentation,
                account: signingAccount,
                accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            )
        }
        return ChatDeviceKeys(agreement: agreement, signing: signing)
    }

    func publicIdentity(userID: String, deviceID: String) -> ChatIdentity {
        ChatIdentity(
            userID: userID,
            deviceID: deviceID,
            agreementPublicKey: agreement.publicKey.rawRepresentation.base64EncodedString(),
            signingPublicKey: signing.publicKey.rawRepresentation.base64EncodedString(),
            updatedAt: nil
        )
    }

    var safetyNumber: String {
        Self.fingerprint(
            agreement: agreement.publicKey.rawRepresentation,
            signing: signing.publicKey.rawRepresentation
        )
    }

    static func safetyNumber(for identity: ChatIdentity) -> String? {
        guard let agreement = Data(base64Encoded: identity.agreementPublicKey),
              let signing = Data(base64Encoded: identity.signingPublicKey) else { return nil }
        return fingerprint(agreement: agreement, signing: signing)
    }

    func encrypt(
        _ plaintext: Data,
        kind: ChatMessageKind,
        contentType: String,
        groupID: String,
        chunkIndex: Int,
        chunkCount: Int,
        sender: ChatIdentity,
        recipient: ChatIdentity,
        createdAt: String
    ) throws -> ChatEnvelope {
        guard let recipientKeyData = Data(base64Encoded: recipient.agreementPublicKey) else {
            throw ChatError.invalidEnvelope
        }
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientKeyData)
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: recipientKey)
        let messageID = UUID().uuidString.lowercased()
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(groupID.utf8),
            sharedInfo: Self.keyContext(messageID: messageID, recipientDeviceID: recipient.deviceID),
            outputByteCount: 32
        )
        let sealed = try ChaChaPoly.seal(plaintext, using: symmetricKey)
        var envelope = ChatEnvelope(
            id: messageID,
            groupID: groupID,
            senderUserID: sender.userID,
            senderDeviceID: sender.deviceID,
            recipientUserID: recipient.userID,
            recipientDeviceID: recipient.deviceID,
            ephemeralPublicKey: ephemeralKey.publicKey.rawRepresentation.base64EncodedString(),
            ciphertext: sealed.combined.base64EncodedString(),
            signature: "",
            messageType: kind,
            contentType: contentType,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            createdAt: createdAt
        )
        envelope.signature = try signing.signature(for: envelope.signingData()).base64EncodedString()
        return envelope
    }

    func decrypt(_ envelope: ChatEnvelope, sender: ChatIdentity) throws -> Data {
        guard envelope.senderUserID == sender.userID,
              envelope.senderDeviceID == sender.deviceID,
              let signature = Data(base64Encoded: envelope.signature),
              let signingData = Data(base64Encoded: sender.signingPublicKey),
              let ephemeralData = Data(base64Encoded: envelope.ephemeralPublicKey),
              let combined = Data(base64Encoded: envelope.ciphertext) else {
            throw ChatError.invalidEnvelope
        }
        let signingKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingData)
        guard signingKey.isValidSignature(signature, for: try envelope.signingData()) else {
            throw ChatError.invalidSignature
        }
        let ephemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralData)
        let sharedSecret = try agreement.sharedSecretFromKeyAgreement(with: ephemeralKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(envelope.groupID.utf8),
            sharedInfo: Self.keyContext(messageID: envelope.id, recipientDeviceID: envelope.recipientDeviceID),
            outputByteCount: 32
        )
        return try ChaChaPoly.open(.init(combined: combined), using: symmetricKey)
    }

    static func pin(_ identity: ChatIdentity) throws {
        guard let fingerprint = safetyNumber(for: identity) else { throw ChatError.invalidEnvelope }
        let account = "chatPinnedKey.\(identity.userID).\(identity.deviceID)"
        if let existing = try KeychainStore.value(account: account), existing != fingerprint {
            throw ChatError.identityChanged
        }
        try KeychainStore.save(fingerprint, account: account)
    }

    static func replacePin(with identity: ChatIdentity) throws {
        guard let fingerprint = safetyNumber(for: identity) else { throw ChatError.invalidEnvelope }
        try KeychainStore.save(
            fingerprint,
            account: "chatPinnedKey.\(identity.userID).\(identity.deviceID)"
        )
    }

    private static func keyContext(messageID: String, recipientDeviceID: String) -> Data {
        Data("ios-next-chat-v1|\(messageID)|\(recipientDeviceID)".utf8)
    }

    private static func fingerprint(agreement: Data, signing: Data) -> String {
        var publicKeys = Data()
        publicKeys.append(agreement)
        publicKeys.append(signing)
        let digest = SHA256.hash(data: publicKeys)
        return digest.map { String(format: "%02X", $0) }
            .joined()
            .split(every: 4)
            .joined(separator: " ")
    }
}

private extension String {
    func split(every length: Int) -> [String] {
        stride(from: 0, to: count, by: length).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: length, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}
