import Foundation
import CryptoKit

/// Device keys, not server-provided timestamps, define ticket identity.
enum TicketIdentityBinding {
    static func canonical(_ identity: ChatIdentity) -> ChatIdentity {
        ChatIdentity(userID: identity.userID, deviceID: identity.deviceID,
            agreementPublicKey: identity.agreementPublicKey,
            signingPublicKey: identity.signingPublicKey, updatedAt: nil)
    }

    static func matches(_ a: ChatIdentity, _ b: ChatIdentity) -> Bool {
        canonical(a) == canonical(b)
    }

    static func confirmed(_ peer: ChatIdentity, number: String) throws -> ChatIdentity {
        let peer = canonical(peer)
        guard EncryptedTicketMessage.validIdentity(peer),
              !number.isEmpty,
              ChatDeviceKeys.safetyNumber(for: peer) == number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        else { throw ChatError.identityChanged }
        return peer
    }
}

struct TicketScreenScope: Hashable {
    let endpoint: URL
    let user: String
    let device: String
    let owner: Bool
    let keyFingerprint: String
}

struct TicketReadableMessage: Identifiable {
    let id: String
    let text: String
    let own: Bool
}

/// Retains the original signed ciphertext for a retry, never generates a second
/// logical message after an ambiguous network failure.
struct TicketPendingSend {
    let scope: TicketScreenScope
    let message: EncryptedTicketMessage
    let peer: ChatIdentity
    let create: Bool
}

