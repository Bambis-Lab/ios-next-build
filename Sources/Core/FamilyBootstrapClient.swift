import CryptoKit
import Foundation
import Security

/// Family enrollment credentials are independent from Owner device keys.
struct FamilyRegisteredIdentity: Equatable, Sendable {
    let deviceID: String
    let publicKey: String
}

enum FamilyDeviceBinding {
    private static let idKey = "iosnext.family.device.id"
    private static let keyAccount = "iosnext.family.p256.private"

    static func identity() throws -> FamilyRegisteredIdentity {
        let defaults = UserDefaults.standard
        let deviceID: String
        if let previous = defaults.string(forKey: idKey), previous.hasPrefix("ios-"),
           (try KeychainStore.data(account: keyAccount)) != nil {
            deviceID = previous
        } else {
            // Fresh install with orphaned UserDefaults must never inherit an
            // old device ID whose signing key can no longer prove ownership.
            deviceID = "ios-" + UUID().uuidString.lowercased()
            defaults.set(deviceID, forKey: idKey)
        }
        return FamilyRegisteredIdentity(
            deviceID: deviceID,
            publicKey: try privateKey().publicKey.x963Representation.base64EncodedString()
        )
    }

    static func sign(challenge: String) throws -> String {
        guard let bytes = Data(base64Encoded: challenge), bytes.count == 32 else {
            throw FamilyBootstrapError.invalidResponse
        }
        return try privateKey().signature(for: bytes).derRepresentation.base64EncodedString()
    }

    private static func privateKey() throws -> P256.Signing.PrivateKey {
        if let existing = try KeychainStore.data(account: keyAccount) {
            return try P256.Signing.PrivateKey(rawRepresentation: existing)
        }
        let key = P256.Signing.PrivateKey()
        try KeychainStore.save(
            key.rawRepresentation,
            account: keyAccount,
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        return key
    }
}

struct FamilyChatContext: Sendable {
    let endpoint: URL
    let haUserID: String
    let deviceID: String
    let grant: FamilyChatGrant
}

struct FamilyChatGrant: Decodable, Equatable, Sendable {
    let accessToken: String
    let expiresAt: Int
    let scopes: [String]
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
        case scopes
    }
    var isValid: Bool {
        accessToken.count >= 32 && expiresAt > Int(Date().timeIntervalSince1970) + 15
            && Set(scopes) == Set(["chat", "tickets"])
    }
}

struct FamilyRegistration: Decodable, Equatable, Sendable {
    let haUserID: String
    let profile: HomeProfile
    let role: String
    let deviceID: String
    let ownerAuthorization: String
    let chat: FamilyChatGrant?

    init(
        haUserID: String, profile: HomeProfile, role: String, deviceID: String,
        ownerAuthorization: String, chat: FamilyChatGrant? = nil
    ) {
        self.haUserID = haUserID
        self.profile = profile
        self.role = role
        self.deviceID = deviceID
        self.ownerAuthorization = ownerAuthorization
        self.chat = chat
    }

    enum CodingKeys: String, CodingKey {
        case haUserID = "ha_user_id"
        case profile
        case role
        case deviceID = "device_id"
        case ownerAuthorization = "owner_authorization"
        case chat
    }

    /// Never treat HA admin status or a display-name match as Owner entitlement.
    func isValid(for verifiedHAUserID: String, expectedDeviceID: String) -> Bool {
        guard haUserID == verifiedHAUserID, deviceID == expectedDeviceID else { return false }
        if role == "owner" {
            return profile == .nico && ownerAuthorization == "separate_device_approval_required"
        }
        return role == "member" && profile != .nico
    }
}

enum FamilyBootstrapError: LocalizedError {
    case brokerNotConfigured
    case invalidResponse
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .brokerNotConfigured: "Der Familien-Backend-Endpunkt ist noch nicht eingerichtet."
        case .invalidResponse: "Die Familienregistrierung konnte nicht sicher überprüft werden."
        case .unauthorized: "Dieses Home-Assistant-Konto ist nicht für die Familie registriert."
        case .unavailable: "Die Familienregistrierung ist zurzeit nicht erreichbar."
        }
    }
}

struct FamilyBootstrapClient: Sendable {
    let baseURL: URL

    /// The address must be supplied as a vetted build-time deployment setting.
    /// Never guess a host from an HA address or accept arbitrary redirects.
    static func configuredURL(in bundle: Bundle = .main) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: "IOSNextFamilyBrokerURL") as? String,
              let url = URL(string: value),
              url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            return nil
        }
        return url
    }

    func enroll(haToken: String, verifiedHAUserID: String) async throws -> FamilyRegistration {
        guard baseURL.scheme == "https" else { throw FamilyBootstrapError.brokerNotConfigured }
        let device = try FamilyDeviceBinding.identity()
        let challengeData = try await request(
            path: "v2/family/challenge", haToken: haToken,
            payload: FamilyDeviceRequest(deviceID: device.deviceID, publicKey: device.publicKey)
        )
        let challenge = try JSONDecoder().decode(FamilyDeviceChallenge.self, from: challengeData)
        let signature = try FamilyDeviceBinding.sign(challenge: challenge.challenge)
        let registrationData = try await request(
            path: "v2/family/register", haToken: haToken,
            payload: FamilyDeviceRegistrationRequest(
                deviceID: device.deviceID,
                publicKey: device.publicKey,
                challenge: challenge.challenge,
                signature: signature
            )
        )
        let result = try JSONDecoder().decode(FamilyRegistration.self, from: registrationData)
        guard result.isValid(for: verifiedHAUserID, expectedDeviceID: device.deviceID) else {
            throw FamilyBootstrapError.invalidResponse
        }
        guard let grant = result.chat, grant.isValid else {
            throw FamilyBootstrapError.invalidResponse
        }
        return result
    }

    private func request<Request: Encodable>(
        path: String, haToken: String, payload: Request
    ) async throws -> Data {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer " + haToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        // URLSession's automatic redirect handling can leak an HA bearer token.
        let session = URLSession(configuration: .ephemeral, delegate: NoFamilyRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FamilyBootstrapError.unavailable }
        switch response.statusCode {
        case 200: return data
        case 401, 403: throw FamilyBootstrapError.unauthorized
        default: throw FamilyBootstrapError.unavailable
        }
    }
}

private struct FamilyDeviceRequest: Encodable {
    let deviceID: String
    let publicKey: String
    enum CodingKeys: String, CodingKey { case deviceID = "device_id", publicKey = "public_key" }
}
private struct FamilyDeviceRegistrationRequest: Encodable {
    let deviceID: String
    let publicKey: String
    let challenge: String
    let signature: String
    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id", publicKey = "public_key", challenge, signature
    }
}
private struct FamilyDeviceChallenge: Decodable { let challenge: String }

private final class NoFamilyRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
