import Foundation

enum ChatMessageKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case voice
    case video

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Bild"
        case .voice: "Sprachnachricht"
        case .video: "Video"
        }
    }
}

struct ChatIdentity: Codable, Equatable, Sendable {
    let userID: String
    let deviceID: String
    let agreementPublicKey: String
    let signingPublicKey: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case agreementPublicKey = "agreement_public_key"
        case signingPublicKey = "signing_public_key"
        case updatedAt = "updated_at"
    }
}

struct ChatEnvelope: Codable, Equatable, Sendable {
    let id: String
    let groupID: String
    let senderUserID: String
    let senderDeviceID: String
    let recipientUserID: String
    let recipientDeviceID: String
    let ephemeralPublicKey: String
    let ciphertext: String
    var signature: String
    let messageType: ChatMessageKind
    let contentType: String
    let chunkIndex: Int
    let chunkCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case senderUserID = "sender_user_id"
        case senderDeviceID = "sender_device_id"
        case recipientUserID = "recipient_user_id"
        case recipientDeviceID = "recipient_device_id"
        case ephemeralPublicKey = "ephemeral_public_key"
        case ciphertext
        case signature
        case messageType = "message_type"
        case contentType = "content_type"
        case chunkIndex = "chunk_index"
        case chunkCount = "chunk_count"
        case createdAt = "created_at"
    }

    func signingData() throws -> Data {
        var unsigned = self
        unsigned.signature = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(unsigned)
    }
}

struct ChatRelayReceipt: Codable, Sendable {
    let id: String
    let state: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, state
        case expiresInSeconds = "expires_in_seconds"
    }
}

struct ChatRelayBatch: Codable, Sendable {
    let messages: [ChatEnvelope]
}


struct ChatContact: Codable, Equatable, Identifiable, Sendable {
    let userID: String
    let displayName: String

    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

struct ChatBootstrapContext: Equatable, Sendable {
    let homeAssistantBaseURL: URL
    let homeAssistantAccessToken: String
    let homeAssistantUserID: String
    let displayName: String
}

struct ChatBootstrapRequest: Codable, Sendable {
    let deviceID: String
    let agreementPublicKey: String
    let signingPublicKey: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case agreementPublicKey = "agreement_public_key"
        case signingPublicKey = "signing_public_key"
    }
}

struct ChatBootstrapResponse: Codable, Equatable, Sendable {
    let userID: String
    let displayName: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case token = "chat_token"
    }
}

struct ChatConfiguration: Equatable, Sendable {
    let baseURL: URL
    let token: String
    let userID: String
    let deviceID: String
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Direction: Equatable, Sendable { case incoming, outgoing }
    enum Delivery: Equatable, Sendable { case sending, queued, received, failed }

    let id: String
    let senderUserID: String
    let kind: ChatMessageKind
    let contentType: String
    let data: Data
    let createdAt: Date
    let direction: Direction
    var delivery: Delivery

    var text: String? {
        guard kind == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum ChatError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case rejected(Int)
    case noRecipientDevice
    case identityChanged
    case invalidEnvelope
    case invalidSignature
    case contentTooLarge
    case microphoneDenied
    case unsupportedMedia
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Chat-Adresse, Chat-Token oder Benutzerkennung ist ungültig."
        case .invalidResponse: "Der Chat-Relay hat ungültige Daten gesendet."
        case let .rejected(code): "Der Chat-Relay hat die Anfrage abgelehnt (HTTP \(code))."
        case .noRecipientDevice: "Für diesen Kontakt ist kein erreichbares Gerät registriert."
        case .identityChanged: "Der Sicherheitsschlüssel des Kontakts hat sich geändert. Versand wurde blockiert."
        case .invalidEnvelope: "Eine verschlüsselte Nachricht war ungültig."
        case .invalidSignature: "Die Signatur einer Nachricht konnte nicht bestätigt werden."
        case .contentTooLarge: "Die Datei überschreitet das sichere Größenlimit."
        case .microphoneDenied: "Der Mikrofonzugriff wurde nicht erlaubt."
        case .unsupportedMedia: "Dieses Medienformat kann nicht verarbeitet werden."
        case .authenticationFailed: "Die Änderung der Sicherheitsidentität wurde nicht bestätigt."
        }
    }
}
