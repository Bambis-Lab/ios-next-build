import CryptoKit
import Foundation
import Security

struct OwnerDeviceIdentity: Equatable, Sendable {
    let deviceID: String
    let publicKey: String
}

enum OwnerDeviceBindingStore {
    private static let deviceIDKey = "ownerDeviceID"
    private static let privateKeyAccount = "ownerDeviceSigningKeyP256"

    static func identity() throws -> OwnerDeviceIdentity {
        let defaults = UserDefaults.standard
        let deviceID: String
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            deviceID = existing
        } else {
            deviceID = "ios-\(UUID().uuidString.lowercased())"
            defaults.set(deviceID, forKey: deviceIDKey)
        }
        let key = try privateKey()
        return OwnerDeviceIdentity(
            deviceID: deviceID,
            publicKey: key.publicKey.x963Representation.base64EncodedString()
        )
    }

    static func sign(challengeBase64: String) throws -> String {
        guard let challenge = Data(base64Encoded: challengeBase64) else {
            throw AdminControlError.invalidResponse
        }
        let signature = try privateKey().signature(for: challenge)
        return signature.derRepresentation.base64EncodedString()
    }

    private static func privateKey() throws -> P256.Signing.PrivateKey {
        if let existing = try KeychainStore.data(account: privateKeyAccount) {
            return try P256.Signing.PrivateKey(rawRepresentation: existing)
        }
        let key = P256.Signing.PrivateKey()
        try KeychainStore.save(
            key.rawRepresentation,
            account: privateKeyAccount,
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        return key
    }
}
