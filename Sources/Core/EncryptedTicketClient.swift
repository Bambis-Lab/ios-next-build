import Foundation

enum EncryptedTicketStatus: String, Codable, Sendable {
    case open, inProgress = "in_progress", resolved
}

struct EncryptedTicketSummary: Decodable, Sendable, Identifiable {
    let ticketID: String
    let requester: ChatIdentity
    let owner: ChatIdentity
    let status: EncryptedTicketStatus
    var id: String { ticketID }

    enum CodingKeys: String, CodingKey {
        case ticketID = "ticket_id"
        case requester, owner, status
    }
}

struct EncryptedTicketDetail: Decodable, Sendable {
    let ticketID: String
    let requester: ChatIdentity
    let owner: ChatIdentity
    let status: EncryptedTicketStatus
    let messages: [EncryptedTicketMessage]

    enum CodingKeys: String, CodingKey {
        case ticketID = "ticket_id"
        case requester, owner, status, messages
    }
}

struct EncryptedTicketPage: Decodable, Sendable {
    let tickets: [EncryptedTicketSummary]
    let nextAfter: String?
    enum CodingKeys: String, CodingKey {
        case tickets
        case nextAfter = "next_after"
    }
}

/// Explicit role-specific credentials. The server independently validates
/// the family enrollment and Owner approval; this enum grants no privilege.
enum EncryptedTicketAuthorization: Sendable {
    case member(ChatConfiguration)
    case owner(AdminControlConfiguration, userID: String, deviceID: String)

    var localActor: [String] {
        switch self {
        case let .member(config): [config.userID, config.deviceID]
        case let .owner(_, user, device): [user, device]
        }
    }

    var isOwner: Bool {
        if case .owner = self { return true }
        return false
    }

    func allows(requester: ChatIdentity, owner: ChatIdentity) -> Bool {
        let local = isOwner ? owner : requester
        return EncryptedTicketMessage.validIdentity(requester)
            && EncryptedTicketMessage.validIdentity(owner)
            && requester.userID != owner.userID
            && requester.deviceID != owner.deviceID
            && [local.userID, local.deviceID] == localActor
    }

    func request(ticketID: String? = nil, action: String? = nil, method: String = "GET",
                 after: String? = nil, limit: Int? = nil) throws -> URLRequest {
        let base: URL
        let bearer: String
        let session: String?
        switch self {
        case let .member(config):
            base = ChatRelayClient.transportBaseURL(for: config.baseURL)
            bearer = config.token
            session = nil
        case let .owner(config, _, _):
            base = config.baseURL
            bearer = config.ownerToken
            guard let proof = config.ownerDeviceSession, Self.validToken(proof) else {
                throw ChatError.authenticationFailed
            }
            session = proof
        }
        guard let original = URLComponents(url: base, resolvingAgainstBaseURL: false),
              original.scheme == "https", original.host != nil,
              original.user == nil, original.password == nil, original.fragment == nil,
              original.query == nil, ["", "/"].contains(original.percentEncodedPath),
              Self.validToken(bearer) else { throw ChatError.invalidConfiguration }
        guard method == "GET" || method == "POST" else { throw ChatError.invalidConfiguration }
        if let ticketID, !EncryptedTicketMessage.validID(ticketID) { throw ChatError.invalidConfiguration }
        if let after, !EncryptedTicketMessage.validID(after) { throw ChatError.invalidConfiguration }
        if let limit, !(1...100).contains(limit) { throw ChatError.invalidConfiguration }
        if method == "GET" {
            guard action == nil, ticketID == nil || (after == nil && limit == nil) else { throw ChatError.invalidConfiguration }
        } else {
            guard after == nil, limit == nil else { throw ChatError.invalidConfiguration }
            if ticketID == nil {
                guard !isOwner, action == nil else { throw ChatError.invalidConfiguration }
            } else {
                guard action == "messages" || (isOwner && action == "status") else { throw ChatError.invalidConfiguration }
            }
        }
        var components = original
        components.path = isOwner ? "/v2/admin/encrypted-tickets" : "/v2/chat/encrypted-tickets"
        if let ticketID { components.path += "/" + ticketID }
        if let action { components.path += "/" + action }
        var query: [URLQueryItem] = []
        if let after { query.append(.init(name: "after", value: after)) }
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ChatError.invalidConfiguration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let session { request.setValue(session, forHTTPHeaderField: "X-Owner-Device-Session") }
        return request
    }

    private static func validToken(_ value: String) -> Bool {
        (1...4096).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}

actor EncryptedTicketClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: ChatRelayNoRedirects(), delegateQueue: nil)
    }

    func list(using auth: EncryptedTicketAuthorization, after: String? = nil) async throws -> EncryptedTicketPage {
        let page: EncryptedTicketPage = try await execute(auth.request(after: after, limit: 50))
        guard page.tickets.count <= 50,
              Set(page.tickets.map(\.ticketID)).count == page.tickets.count,
              page.tickets.allSatisfy({ EncryptedTicketMessage.validID($0.ticketID)
                  && auth.allows(requester: $0.requester, owner: $0.owner) }),
              page.nextAfter == nil || page.nextAfter == page.tickets.last?.ticketID else {
            throw ChatError.invalidResponse
        }
        return page
    }

    func detail(_ id: String, using auth: EncryptedTicketAuthorization) async throws -> EncryptedTicketDetail {
        try await checkedDetail(auth.request(ticketID: id), id: id, auth: auth)
    }

    func create(_ message: EncryptedTicketMessage, ownerDeviceID: String,
                using auth: EncryptedTicketAuthorization) async throws -> EncryptedTicketDetail {
        struct Body: Encodable {
            let ownerDeviceID: String
            let message: EncryptedTicketMessage
            enum CodingKeys: String, CodingKey { case ownerDeviceID = "owner_device_id", message }
        }
        var request = try auth.request(method: "POST")
        request.httpBody = try JSONEncoder().encode(Body(ownerDeviceID: ownerDeviceID, message: message))
        return try await checkedDetail(request, id: message.ticketID, auth: auth, expected: message)
    }

    func reply(_ message: EncryptedTicketMessage,
               using auth: EncryptedTicketAuthorization) async throws -> EncryptedTicketDetail {
        struct Body: Encodable { let message: EncryptedTicketMessage }
        var request = try auth.request(ticketID: message.ticketID, action: "messages", method: "POST")
        request.httpBody = try JSONEncoder().encode(Body(message: message))
        return try await checkedDetail(request, id: message.ticketID, auth: auth, expected: message)
    }

    func status(_ value: EncryptedTicketStatus, ticketID: String,
                using auth: EncryptedTicketAuthorization) async throws -> EncryptedTicketDetail {
        struct Body: Encodable { let status: EncryptedTicketStatus }
        var request = try auth.request(ticketID: ticketID, action: "status", method: "POST")
        request.httpBody = try JSONEncoder().encode(Body(status: value))
        let detail = try await checkedDetail(request, id: ticketID, auth: auth)
        guard detail.status == value else { throw ChatError.invalidResponse }
        return detail
    }

    private func checkedDetail(_ request: URLRequest, id: String, auth: EncryptedTicketAuthorization,
                               expected: EncryptedTicketMessage? = nil) async throws -> EncryptedTicketDetail {
        let detail: EncryptedTicketDetail = try await execute(request)
        guard detail.ticketID == id,
              auth.allows(requester: detail.requester, owner: detail.owner),
              (1...200).contains(detail.messages.count),
              Set(detail.messages.map(\.messageID)).count == detail.messages.count,
              detail.messages.allSatisfy({ $0.version == 1 && $0.ticketID == id && $0.copies.count == 2
                  && EncryptedTicketMessage.validID($0.messageID) }),
              expected == nil || detail.messages.contains(where: { $0 == expected }) else {
            throw ChatError.invalidResponse
        }
        return detail
    }

    private func execute<T: Decodable>(_ original: URLRequest) async throws -> T {
        var request = original
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ChatError.rejected(http.statusCode) }
        guard data.count <= 12 * 1024 * 1024 else { throw ChatError.contentTooLarge }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
