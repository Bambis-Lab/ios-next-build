import Foundation

/// Fail closed for every relay request carrying HA or chat bearer tokens.
/// No 301/302/307/308 may replay a sensitive request to a different origin.
final class ChatRelayNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Backend long-poll contract: GET /v1/chat/messages?wait=25 may legitimately
/// return only after 25 seconds when no messages exist. The original client
/// used a 12-second idle timeout / 20-second resource timeout, turning an
/// otherwise healthy quiet chat into recurring false "Offline" states.
enum ChatRelayPollingPolicy {
    static let serverWaitSeconds = 25
    static let ordinaryRequestTimeout: TimeInterval = 12
    static let longPollRequestTimeout: TimeInterval = 42
    static let sessionResourceTimeout: TimeInterval = 55

    static func timeout(for path: String, method: String) -> TimeInterval {
        if method == "GET",
           path.hasPrefix("v1/chat/messages?"),
           let url = URLComponents(string: path),
           url.queryItems?.contains(where: {
               $0.name == "wait" && $0.value == String(serverWaitSeconds)
           }) == true {
            return longPollRequestTimeout
        }
        return ordinaryRequestTimeout
    }
}

/// The separately approved family broker advertises opt-in volatile ack_v1.
/// The client must verify this *before* reading ciphertext to avoid the old
/// server deleting data on GET when it does not support acknowledgements.
struct ChatDeliveryContract: Decodable, Sendable {
    let mode: String
    let maxBatch: Int
    let ttlSeconds: Int
    let persistent: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case maxBatch = "max_batch"
        case ttlSeconds = "ttl_seconds"
        case persistent
    }

    var isSupported: Bool {
        mode == "ack_v1" && maxBatch >= 1 && maxBatch <= 256 &&
        ttlSeconds >= 30 && !persistent
    }
}

private struct ChatAcknowledgementRequest: Encodable {
    let recipientDeviceID: String
    let messageIDs: [String]

    enum CodingKeys: String, CodingKey {
        case recipientDeviceID = "recipient_device_id"
        case messageIDs = "message_ids"
    }
}

private struct ChatAcknowledgementResponse: Decodable {
    let acked: Int
}

actor ChatRelayClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated static let tailscaleRelayPort = 8444

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = ChatRelayPollingPolicy.ordinaryRequestTimeout
        configuration.timeoutIntervalForResource = ChatRelayPollingPolicy.sessionResourceTimeout
        session = URLSession(
            configuration: configuration,
            delegate: ChatRelayNoRedirects(),
            delegateQueue: nil
        )
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    nonisolated static func transportBaseURL(for logicalURL: URL) -> URL {
        guard let host = logicalURL.host?.lowercased(),
              host.hasPrefix("iosnext-chat."),
              host.hasSuffix(".ts.net") else {
            return logicalURL
        }

        let labels = host.split(separator: ".")
        guard labels.count >= 3 else { return logicalURL }
        let tailnet = labels.dropFirst().joined(separator: ".")

        var components = URLComponents(url: logicalURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = "runner.\(tailnet)"
        components?.port = tailscaleRelayPort
        return components?.url ?? logicalURL
    }

    func bootstrap(
        endpoint: URL,
        homeAssistantAccessToken: String,
        identity: ChatIdentity
    ) async throws -> ChatBootstrapResponse {
        let body = ChatBootstrapRequest(
            deviceID: identity.deviceID,
            agreementPublicKey: identity.agreementPublicKey,
            signingPublicKey: identity.signingPublicKey
        )
        return try await request(
            path: "v1/chat/bootstrap",
            method: "POST",
            body: body,
            baseURL: endpoint,
            bearerToken: homeAssistantAccessToken
        )
    }

    func linkHomeAssistant(
        accessToken: String,
        configuration: ChatConfiguration
    ) async throws -> ChatContact {
        let baseURL = Self.transportBaseURL(for: configuration.baseURL)
        guard let url = URL(string: "v1/chat/link-home-assistant", relativeTo: baseURL)?.absoluteURL else {
            throw ChatError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "X-Home-Assistant-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ChatError.rejected(http.statusCode) }
        guard let contact = try? decoder.decode(ChatContact.self, from: data) else {
            throw ChatError.invalidResponse
        }
        return contact
    }

    func familyGroup(configuration: ChatConfiguration) async throws -> ChatFamilyGroup {
        try await request(
            path: "v1/chat/groups/family",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func contacts(configuration: ChatConfiguration) async throws -> [ChatContact] {
        try await request(
            path: "v1/chat/contacts",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func register(identity: ChatIdentity, configuration: ChatConfiguration) async throws {
        let _: ChatIdentity = try await request(
            path: "v1/chat/identities",
            method: "POST",
            body: identity,
            configuration: configuration
        )
    }

    func identities(for userID: String, configuration: ChatConfiguration) async throws -> [ChatIdentity] {
        try await request(
            path: "v1/chat/identities/\(userID)",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func session(configuration: ChatConfiguration) async throws -> ChatSession {
        try await request(
            path: "v1/chat/session",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func memberTickets(configuration: ChatConfiguration) async throws -> [SupportTicket] {
        try await request(
            path: "v1/chat/tickets",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func memberTicket(_ ticketID: String, configuration: ChatConfiguration) async throws -> SupportTicket {
        let safeID = ticketID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticketID
        return try await request(
            path: "v1/chat/tickets/\(safeID)",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
    }

    func replyMemberTicket(_ ticketID: String, text: String,
                           configuration: ChatConfiguration) async throws -> SupportTicket {
        let safeID = ticketID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticketID
        return try await request(
            path: "v1/chat/tickets/\(safeID)/messages",
            method: "POST",
            body: SupportTicketMessageRequest(message: text),
            configuration: configuration
        )
    }

    func createSupportTicket(
        message: String,
        configuration: ChatConfiguration
    ) async throws -> SupportTicket {
        try await request(
            path: "v1/chat/tickets",
            method: "POST",
            body: SupportTicketMessageRequest(message: message),
            configuration: configuration
        )
    }

    func send(_ envelope: ChatEnvelope, configuration: ChatConfiguration) async throws -> ChatRelayReceipt {
        try await request(
            path: "v1/chat/messages",
            method: "POST",
            body: envelope,
            configuration: configuration
        )
    }

    func requireAcknowledgedDelivery(configuration: ChatConfiguration) async throws {
        let contract: ChatDeliveryContract = try await request(
            path: "v1/chat/delivery-contract",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
        guard contract.isSupported else { throw ChatError.invalidResponse }
    }

    func receive(
        configuration: ChatConfiguration, requiresAcknowledgement: Bool = false
    ) async throws -> [ChatEnvelope] {
        let device = configuration.deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? configuration.deviceID
        let suffix = requiresAcknowledgement ? "&ack=1" : ""
        let batch: ChatRelayBatch = try await request(
            path: "v1/chat/messages?recipient_device_id=\(device)&wait=\(ChatRelayPollingPolicy.serverWaitSeconds)&limit=64\(suffix)",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
        guard !requiresAcknowledgement || batch.deliveryMode == "ack_v1" else {
            throw ChatError.invalidResponse
        }
        return batch.messages
    }

    func acknowledge(_ ids: [String], configuration: ChatConfiguration) async throws {
        guard !ids.isEmpty, ids.count <= 64, Set(ids).count == ids.count else {
            throw ChatError.invalidResponse
        }
        let reply: ChatAcknowledgementResponse = try await request(
            path: "v1/chat/messages/ack",
            method: "POST",
            body: ChatAcknowledgementRequest(
                recipientDeviceID: configuration.deviceID, messageIDs: ids
            ),
            configuration: configuration
        )
        // Zero ACKs means the same IDs were already confirmed (lost response),
        // or expired; this is allowed for an idempotent endpoint.
        guard reply.acked >= 0 && reply.acked <= ids.count else {
            throw ChatError.invalidResponse
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        configuration: ChatConfiguration
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            body: body,
            baseURL: configuration.baseURL,
            bearerToken: configuration.token
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        baseURL: URL,
        bearerToken: String
    ) async throws -> Response {
        let transportBaseURL = Self.transportBaseURL(for: baseURL)
        guard let url = URL(string: path, relativeTo: transportBaseURL)?.absoluteURL else {
            throw ChatError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = ChatRelayPollingPolicy.timeout(for: path, method: method)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ChatError.rejected(http.statusCode) }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ChatError.invalidResponse
        }
    }
}
