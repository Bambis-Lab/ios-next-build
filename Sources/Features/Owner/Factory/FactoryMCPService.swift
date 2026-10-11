import Foundation
import CryptoKit

/// Credential persistence seam: production always uses iOS Keychain; the
/// unsigned CI simulator injects memory-only credentials. No user tokens are
/// persisted outside Keychain in release builds.
@MainActor
struct FactoryCredentialStore {
    let read: () throws -> Data?
    let write: (Data) throws -> Void
    let delete: () -> Void

    static var keychain: Self {
        Self(
            read: { try KeychainStore.data(account: "factory.oauth.tokens") },
            write: { try KeychainStore.save($0, account: "factory.oauth.tokens") },
            delete: { KeychainStore.delete(account: "factory.oauth.tokens") }
        )
    }
}

enum FactoryConnectionError: LocalizedError {
    case invalidEndpoint, metadataUnavailable, pkceUnavailable, registrationUnavailable
    case oauthCancelled, invalidCallback, expiredState, missingCredentials
    case unauthorized, unexpectedResponse, rpcError(String), toolNotAvailable(String)
    case invalidProtocol, noReadableTools, noSuccessfulReads

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Die Factory-Adresse muss eine gültige HTTPS-MCP-Adresse sein."
        case .metadataUnavailable: "Factory-OAuth-Metadaten konnten nicht sicher geladen werden."
        case .pkceUnavailable: "Der OAuth-Server bietet kein nachgewiesenes PKCE S256 an."
        case .registrationUnavailable: "Der OAuth-Server lässt sich nicht als iOS-Client registrieren. Client-ID manuell hinterlegen."
        case .oauthCancelled: "Die Factory-Anmeldung wurde abgebrochen."
        case .invalidCallback: "Die OAuth-Antwort ist ungültig oder gehört nicht zu dieser Anmeldung."
        case .expiredState: "Die Factory-Sitzung ist abgelaufen. Erneut anmelden."
        case .missingCredentials: "Factory noch nicht verbunden. Melde dich zuerst an."
        case .unauthorized: "Factory-Zugang ist abgelaufen oder nicht berechtigt."
        case .unexpectedResponse: "Die Factory hat eine unerwartete Antwort geliefert."
        case .invalidProtocol: "Die Factory-MCP-Antwort hat eine ungültige Protokollversion oder Sitzungskennung."
        case .noReadableTools: "Der Gateway-Zugang bietet keine freigegebenen lesenden Factory-Funktionen."
        case .noSuccessfulReads: "Die Factory ist erreichbar, aber keine lesende Datenabfrage war erfolgreich."
        case let .rpcError(message): "Factory-Anfrage abgelehnt: \(message)"
        case let .toolNotAvailable(tool): "Diese lesende Factory-Funktion wird nicht angeboten: \(tool)"
        }
    }
}

struct FactoryAuthorization: Sendable {
    let endpoint: URL
    let tokenEndpoint: URL
    let clientID: String
    let verifier: String
    let state: String
    let authorizationURL: URL
}

struct FactorySnapshotRow: Identifiable, Sendable {
    let id: String
    let title: String
    let source: String
    let detail: String
    let status: String
    let observedAt: Date
}

struct FactorySnapshot: Sendable {
    let observedAt: Date
    let rows: [FactorySnapshotRow]
    let rawReports: [String: String]
    let toolNames: [String]
}

@MainActor
final class FactoryMCPService {
    private let session: URLSession
    private let credentials: FactoryCredentialStore
    private let callbackURI = "iosnext://factory-oauth"
    private let resourceMetadataPath = "/.well-known/oauth-protected-resource"
    private let protocolVersion = "2025-06-18"
    private let maxPaginationPages = 12
    private let allowedTools: [String] = [
        "factory_status", "factory_discover", "capabilities_get",
        "control_plane_status", "control_plane_registry_summary",
        "runner_status", "runner_system", "runner_memory", "runner_mounts",
        "runtime_status", "audit_status"
    ]
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenEndpoint: URL?
    private var clientID: String?
    private var expiresAt: Date?
    private var mcpSessionID: String?
    private var endpoint: URL?

    init(
        session: URLSession = .shared,
        credentials: FactoryCredentialStore? = nil
    ) {
        self.session = session
        // Resolve the actor-isolated Keychain provider inside this
        // @MainActor initializer, never in a nonisolated default argument.
        self.credentials = credentials ?? .keychain
    }

    private func secureURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil else { throw FactoryConnectionError.invalidEndpoint }
        return url
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FactoryConnectionError.unexpectedResponse
        }
        return value
    }

    private func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (body, reply) = try await session.data(for: request)
        guard let response = reply as? HTTPURLResponse, body.count < 2_000_000 else {
            throw FactoryConnectionError.unexpectedResponse
        }
        return (body, response)
    }

    private func metadata(at url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await data(for: request)
        guard response.statusCode == 200 else { throw FactoryConnectionError.metadataUnavailable }
        return try json(data)
    }

    func beginAuthorization(endpoint input: String, registeredClientID: String?) async throws -> FactoryAuthorization {
        let target = try secureURL(input)
        // OAuth Protected Resource Metadata, first endpoint-path-specific, then root.
        var resource: [String: Any]?
        for suffix in [resourceMetadataPath + target.path, resourceMetadataPath] {
            guard var parts = URLComponents(url: target, resolvingAgainstBaseURL: false) else { continue }
            parts.path = suffix
            parts.query = nil
            if let url = parts.url, let found = try? await metadata(at: url),
               let advertised = found["resource"] as? String,
               advertised == target.absoluteString {
                resource = found
                break
            }
        }
        guard let resource,
              let issuerString = (resource["authorization_servers"] as? [String])?.first,
              let issuer = try? secureURL(issuerString),
              var wellKnown = URLComponents(url: issuer, resolvingAgainstBaseURL: false) else {
            throw FactoryConnectionError.metadataUnavailable
        }
        wellKnown.path = "/.well-known/oauth-authorization-server" + (issuer.path == "/" ? "" : issuer.path)
        wellKnown.query = nil
        let discovery = try await metadata(at: wellKnown.url!)
        guard discovery["issuer"] as? String == issuer.absoluteString,
              let methods = discovery["code_challenge_methods_supported"] as? [String],
              methods.contains("S256") else {
            throw FactoryConnectionError.pkceUnavailable
        }
        guard let authURL = try? secureURL(discovery["authorization_endpoint"] as? String ?? ""),
              let tokenURL = try? secureURL(discovery["token_endpoint"] as? String ?? "") else {
            throw FactoryConnectionError.metadataUnavailable
        }
        let client: String
        if let registeredClientID, !registeredClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            client = registeredClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            guard let registerURL = try? secureURL(discovery["registration_endpoint"] as? String ?? "") else {
                throw FactoryConnectionError.registrationUnavailable
            }
            var request = URLRequest(url: registerURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "client_name": "iOS Next Factory",
                "redirect_uris": [callbackURI],
                "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"],
                "token_endpoint_auth_method": "none"
            ])
            let (data, response) = try await self.data(for: request)
            guard [200, 201].contains(response.statusCode),
                  let registered = try json(data)["client_id"] as? String,
                  !registered.isEmpty else {
                throw FactoryConnectionError.registrationUnavailable
            }
            client = registered
        }

        let verifier = randomBase64URL(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64URLEncodedString()
        let state = randomBase64URL(byteCount: 24)
        var query = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        query.queryItems = (query.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client),
            URLQueryItem(name: "redirect_uri", value: callbackURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: target.absoluteString)
        ]
        guard let auth = query.url else { throw FactoryConnectionError.metadataUnavailable }
        return FactoryAuthorization(endpoint: target, tokenEndpoint: tokenURL,
                                    clientID: client, verifier: verifier,
                                    state: state, authorizationURL: auth)
    }

    func completeAuthorization(_ responseURL: URL, original: FactoryAuthorization) async throws {
        guard responseURL.scheme == "iosnext", responseURL.host == "factory-oauth",
              let items = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == original.state,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { throw FactoryConnectionError.invalidCallback }
        let token = try await tokenRequest(at: original.tokenEndpoint, fields: [
            "grant_type": "authorization_code", "client_id": original.clientID,
            "code": code, "redirect_uri": callbackURI,
            "code_verifier": original.verifier, "resource": original.endpoint.absoluteString
        ])
        guard let access = token["access_token"] as? String, !access.isEmpty,
              (token["token_type"] as? String)?.lowercased() == "bearer" else {
            throw FactoryConnectionError.unexpectedResponse
        }
        self.accessToken = access
        self.refreshToken = token["refresh_token"] as? String
        self.expiresAt = Date().addingTimeInterval(TimeInterval(token["expires_in"] as? Int ?? 3600))
        self.tokenEndpoint = original.tokenEndpoint
        self.clientID = original.clientID
        self.endpoint = original.endpoint
        self.mcpSessionID = nil
        try storeTokens()
    }

    private func tokenRequest(at url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }.joined(separator: "&").data(using: .utf8)
        let (body, reply) = try await data(for: request)
        guard reply.statusCode == 200 else { throw FactoryConnectionError.unauthorized }
        return try json(body)
    }

    private func formEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }

    private func storeTokens() throws {
        let record: [String: Any] = [
            "access": accessToken ?? "", "refresh": refreshToken ?? "",
            "endpoint": endpoint?.absoluteString ?? "",
            "client_id": clientID ?? "",
            "token_endpoint": tokenEndpoint?.absoluteString ?? "",
            "expires_at": expiresAt?.timeIntervalSince1970 ?? 0
        ]
        let data = try JSONSerialization.data(withJSONObject: record)
        try credentials.write(data)
    }

    func restore() throws -> Bool {
        guard let data = try credentials.read(),
              let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = record["access"] as? String, !access.isEmpty,
              let endpointString = record["endpoint"] as? String,
              let tokenString = record["token_endpoint"] as? String else { return false }
        self.endpoint = try secureURL(endpointString)
        self.tokenEndpoint = try secureURL(tokenString)
        self.accessToken = access
        self.refreshToken = record["refresh"] as? String
        self.clientID = record["client_id"] as? String
        self.expiresAt = Date(timeIntervalSince1970: record["expires_at"] as? TimeInterval ?? 0)
        return true
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        tokenEndpoint = nil
        clientID = nil
        endpoint = nil
        expiresAt = nil
        mcpSessionID = nil
        credentials.delete()
    }

    private func activeToken() async throws -> String {
        guard let accessToken else { throw FactoryConnectionError.missingCredentials }
        if let expiresAt, expiresAt <= Date().addingTimeInterval(45) {
            guard let refreshToken, !refreshToken.isEmpty,
                  let tokenEndpoint, let clientID, let endpoint else {
                throw FactoryConnectionError.expiredState
            }
            let result = try await tokenRequest(at: tokenEndpoint, fields: [
                "grant_type": "refresh_token", "client_id": clientID,
                "refresh_token": refreshToken, "resource": endpoint.absoluteString
            ])
            guard let newAccess = result["access_token"] as? String, !newAccess.isEmpty,
                  (result["token_type"] as? String)?.lowercased() == "bearer" else {
                throw FactoryConnectionError.unauthorized
            }
            self.accessToken = newAccess
            self.refreshToken = result["refresh_token"] as? String ?? refreshToken
            self.expiresAt = Date().addingTimeInterval(TimeInterval(result["expires_in"] as? Int ?? 3600))
            try storeTokens()
            return newAccess
        }
        return accessToken
    }

    private func rpc(method: String, params: [String: Any], notification: Bool = false) async throws -> [String: Any] {
        guard let endpoint else { throw FactoryConnectionError.missingCredentials }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(try await activeToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let mcpSessionID { request.setValue(mcpSessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        var value: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        let requestID = UUID().uuidString
        if !notification { value["id"] = requestID }
        request.httpBody = try JSONSerialization.data(withJSONObject: value)
        let (body, reply) = try await data(for: request)
        guard reply.statusCode != 401 else { throw FactoryConnectionError.unauthorized }
        guard (200..<300).contains(reply.statusCode) else {
            throw FactoryConnectionError.rpcError("HTTP \(reply.statusCode)")
        }
        if let session = reply.value(forHTTPHeaderField: "Mcp-Session-Id"), !session.isEmpty {
            mcpSessionID = session
        }
        if notification { return [:] }
        // Streamable HTTP can send multiple SSE events, including heartbeats.
        // Never select the last data: line without verifying its JSON-RPC id.
        let objects: [[String: Any]]
        if let contentType = reply.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/event-stream") {
            guard let text = String(data: body, encoding: .utf8) else {
                throw FactoryConnectionError.unexpectedResponse
            }
            objects = text.components(separatedBy: .newlines).compactMap { line in
                guard line.hasPrefix("data:") else { return nil }
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard value != "[DONE]", let bytes = value.data(using: .utf8) else { return nil }
                return try? json(bytes)
            }
        } else {
            objects = [try json(body)]
        }
        guard let object = objects.first(where: {
            ($0["id"] as? String) == requestID && ($0["jsonrpc"] as? String) == "2.0"
        }) else {
            throw FactoryConnectionError.invalidProtocol
        }
        if let error = object["error"] as? [String: Any] {
            throw FactoryConnectionError.rpcError(error["message"] as? String ?? "RPC Error")
        }
        guard let result = object["result"] as? [String: Any] else {
            throw FactoryConnectionError.unexpectedResponse
        }
        return result
    }

    private func openSession() async throws -> Set<String> {
        mcpSessionID = nil
        let hello = try await rpc(method: "initialize", params: [
            "protocolVersion": protocolVersion,
            "capabilities": [:],
            "clientInfo": ["name": "iOS Next Factory", "version": "1.6.2"]
        ])
        guard hello["protocolVersion"] as? String == protocolVersion else {
            throw FactoryConnectionError.invalidProtocol
        }
        _ = try await rpc(method: "notifications/initialized", params: [:], notification: true)
        var names = Set<String>()
        var cursors = Set<String>()
        var cursor: String?
        for _ in 0..<maxPaginationPages {
            var p: [String: Any] = [:]
            if let cursor { p["cursor"] = cursor }
            let result = try await rpc(method: "tools/list", params: p)
            for tool in (result["tools"] as? [[String: Any]]) ?? [] {
                if let name = tool["name"] as? String { names.insert(name) }
            }
            guard let next = result["nextCursor"] as? String, !next.isEmpty else {
                return names
            }
            guard cursors.insert(next).inserted else {
                throw FactoryConnectionError.invalidProtocol
            }
            cursor = next
        }
        throw FactoryConnectionError.invalidProtocol
    }

    private func call(_ name: String) async throws -> String {
        guard allowedTools.contains(name) else { throw FactoryConnectionError.toolNotAvailable(name) }
        let result = try await rpc(method: "tools/call", params: ["name": name, "arguments": [:]])
        if result["isError"] as? Bool == true {
            throw FactoryConnectionError.rpcError("Tool \(name) meldet einen Fehler.")
        }
        if let structured = result["structuredContent"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        let blocks = result["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    func snapshot() async throws -> FactorySnapshot {
        let available = try await openSession()
        guard !available.intersection(Set(allowedTools)).isEmpty else {
            throw FactoryConnectionError.noReadableTools
        }
        let now = Date()
        var rows: [FactorySnapshotRow] = []
        var reports: [String: String] = [:]
        var successCount = 0
        for name in allowedTools where available.contains(name) {
            do {
                let body = try await call(name)
                // Keep raw diagnostics transient in memory; the UI never dumps
                // untrusted response bodies or possible sensitive payloads.
                reports[name] = body
                successCount += 1
                let decoded = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
                let state = decoded?["state"] as? String ?? decoded?["status"] as? String ?? "Geliefert"
                let detail = decoded?["detail"] as? String ?? "Antwort vom autorisierten Factory-Gateway"
                rows.append(.init(id: name, title: name.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                                  source: "Factory MCP", detail: detail,
                                  status: state, observedAt: now))
            } catch {
                rows.append(.init(id: name, title: name.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                                  source: "Factory MCP", detail: "Teilquelle nicht verfügbar",
                                  status: "Eingeschränkt", observedAt: now))
            }
        }
        guard successCount > 0 else { throw FactoryConnectionError.noSuccessfulReads }
        return FactorySnapshot(observedAt: now, rows: rows, rawReports: reports,
                               toolNames: available.sorted())
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
