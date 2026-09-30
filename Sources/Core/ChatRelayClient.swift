import Foundation

actor ChatRelayClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 35
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
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
        guard let url = URL(string: "v1/chat/link-home-assistant", relativeTo: configuration.baseURL)?.absoluteURL else {
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

    func receive(configuration: ChatConfiguration) async throws -> [ChatEnvelope] {
        let device = configuration.deviceID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? configuration.deviceID
        let batch: ChatRelayBatch = try await request(
            path: "v1/chat/messages?recipient_device_id=\(device)&wait=25&limit=64",
            method: "GET",
            body: Optional<String>.none,
            configuration: configuration
        )
        return batch.messages
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
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ChatError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
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
