import Foundation
import XCTest
@testable import IOSNext

/// Exercises the actual factory OAuth + MCP client against a deterministic
/// HTTP transport. No live tokens or network endpoints are used in CI.
@MainActor
final class FactoryMCPIntegrationTests: XCTestCase {
    private let resource = "https://factory-iosnext-test.invalid/mcp"
    private let issuer = "https://factory-iosnext-test.invalid"
    private let testCredentials = FactoryTestCredentialBox()

    private func service() -> FactoryMCPService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FactoryMockProtocol.self]
        return FactoryMCPService(
            session: URLSession(configuration: configuration),
            credentials: testCredentials.store
        )
    }

    override func setUp() {
        super.setUp()
        FactoryMockProtocol.reset()
        testCredentials.data = nil
    }

    func testOAuthTransportRefusesOffOriginRedirectsIncluding307TokenPost() throws {
        let delegate = FactoryNoRedirects()
        let start = try XCTUnwrap(URL(string: issuer + "/token"))
        let destination = try XCTUnwrap(URL(string: "https://unauthorized-host.invalid/steal"))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: start)
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: start, statusCode: 307, httpVersion: "HTTP/1.1",
            headerFields: ["Location": destination.absoluteString]
        ))
        var forwarded: URLRequest?
        var callbackInvoked = false
        delegate.urlSession(
            session, task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: destination)
        ) { candidate in
            callbackInvoked = true
            forwarded = candidate
        }
        XCTAssertTrue(callbackInvoked)
        XCTAssertNil(forwarded, "OAuth credentials must never follow server redirects")
    }

    func testFactoryConnectionMissingCredentialsIsNotAnError() {
        let model = FactoryConnectionModel(service: service())
        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertFalse(model.hasRestorableSession)
        XCTAssertFalse(model.canRefresh)
        XCTAssertNil(model.errorMessage)
    }

    func testFactoryConnectionKeychainErrorIsNotMisreportedAsNetworkFailure() {
        let credential = FactoryCredentialStore(
            read: { throw KeychainError.unexpectedStatus(-34018) },
            write: { _ in },
            delete: {}
        )
        let model = FactoryConnectionModel(service: FactoryMCPService(credentials: credential))
        XCTAssertEqual(model.phase, .credentialUnavailable)
        XCTAssertEqual(model.phase.title, "Schlüsselbund nicht verfügbar")
        XCTAssertFalse(model.hasRestorableSession)
        XCTAssertFalse(model.canRefresh)
        XCTAssertNotNil(model.errorMessage)
    }

    func testDynamicOAuthPKCECredentialRestoreAndReadOnlyMCP() async throws {
        FactoryMockProtocol.configure(expiresIn: 3600, useSSE: true)
        let client = service()
        defer { client.clear() }

        let pending = try await client.beginAuthorization(endpoint: resource, registeredClientID: nil)
        XCTAssertEqual(pending.clientID, "iosnext-test-public-client")
        let items = try XCTUnwrap(URLComponents(url: pending.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(items.first(where: { $0.name == "resource" })?.value, resource)
        XCTAssertEqual(items.first(where: { $0.name == "state" })?.value, pending.state)
        XCTAssertNotNil(items.first(where: { $0.name == "code_challenge" })?.value)

        let callback = try XCTUnwrap(URL(string: "iosnext://factory-oauth?code=mock-code&state=\(pending.state)"))
        try await client.completeAuthorization(callback, original: pending)
        let afterRelaunch = service()
        XCTAssertTrue(try afterRelaunch.restore(), "Factory OAuth tokens were not restored from injected test credential store")
        let snapshot = try await afterRelaunch.snapshot()
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.status == "ok" })
        XCTAssertTrue(snapshot.toolNames.contains("dangerous_host_write"))
        XCTAssertFalse(FactoryMockProtocol.calledTools.contains("dangerous_host_write"),
                       "The iOS client called a disallowed write tool")
        XCTAssertEqual(Set(FactoryMockProtocol.calledTools),
                       Set(["factory_status", "factory_discover", "runner_status"]))
        XCTAssertTrue(FactoryMockProtocol.calledMethods.contains("initialize"))
        XCTAssertTrue(FactoryMockProtocol.calledMethods.contains("notifications/initialized"))
        XCTAssertTrue(FactoryMockProtocol.calledMethods.contains("tools/list"))
    }

    func testOAuthMissingDynamicRegistrationCanUseIndependentPublicClientID() async throws {
        FactoryMockProtocol.registrationBehavior(endpointVisible: false)
        let client = service()
        do {
            _ = try await client.beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("No registration endpoint must fail without a pre-registered client")
        } catch FactoryConnectionError.registrationEndpointMissing {
            // Explicit fail-closed diagnosis; no untrusted client ID invented.
        }
        let manual = try await client.beginAuthorization(
            endpoint: resource, registeredClientID: "registered-public-iosnext-client"
        )
        XCTAssertEqual(manual.clientID, "registered-public-iosnext-client")
        XCTAssertEqual(URLComponents(url: manual.authorizationURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
    }

    func testOAuthRegistrationHTTPRejectionIsRedactedAndPrecise() async throws {
        FactoryMockProtocol.registrationBehavior(status: 403)
        do {
            _ = try await service().beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("Registration HTTP 403 must not silently create an OAuth client")
        } catch FactoryConnectionError.registrationRejected(let status) {
            XCTAssertEqual(status, 403)
        }
    }

    func testOAuthNativeRedirectRejectionHasRedactedActionableDiagnostic() async throws {
        FactoryMockProtocol.registrationBehavior(status: 400)
        do {
            _ = try await service().beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("The gateway must not be treated as registered when it rejects the native redirect")
        } catch FactoryConnectionError.registrationRedirectURIRejected {
            // Server reports the RFC-standard invalid_redirect_uris value.
            // No registration response body or OAuth secret is shown.
        }
    }

    func testOAuthClientMetadataRejectionHasOnlyStandardizedErrorCode() async throws {
        FactoryMockProtocol.registrationBehavior(status: 400, errorCode: "invalid_client_metadata")
        do {
            _ = try await service().beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("Bad client metadata must never create a Factory OAuth client")
        } catch FactoryConnectionError.registrationClientMetadataRejected {
            XCTAssertTrue(FactoryConnectionError.registrationClientMetadataRejected
                .localizedDescription.contains("invalid_client_metadata"))
        }
    }

    func testOAuthUnknownRegistrationErrorIsNotSurfaced() async throws {
        FactoryMockProtocol.registrationBehavior(status: 400, errorCode: "attacker-controlled-secret")
        do {
            _ = try await service().beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("Unknown registration errors must fail closed")
        } catch FactoryConnectionError.registrationRejected(let status) {
            XCTAssertEqual(status, 400)
            XCTAssertFalse(FactoryConnectionError.registrationRejected(status)
                .localizedDescription.contains("attacker-controlled-secret"))
        }
    }

    func testOAuthRegistrationMissingClientIDIsRejected() async throws {
        FactoryMockProtocol.registrationBehavior(returnClientID: false)
        do {
            _ = try await service().beginAuthorization(endpoint: resource, registeredClientID: nil)
            XCTFail("Successful HTTP response with no client_id must fail closed")
        } catch FactoryConnectionError.registrationMissingClientID {
            // No fabricated ID.
        }
    }

    func testWrongOAuthStateCannotCreateSession() async throws {
        let client = service()
        defer { client.clear() }
        let pending = try await client.beginAuthorization(endpoint: resource, registeredClientID: "test-manual-client")
        let invalid = try XCTUnwrap(URL(string: "iosnext://factory-oauth?code=mock-code&state=wrong-state"))
        do {
            try await client.completeAuthorization(invalid, original: pending)
            XCTFail("A mismatching OAuth state must never be accepted")
        } catch FactoryConnectionError.invalidCallback {
            // Required security decision.
        }
    }

    func testRefreshTokenBeforeMCPQuery() async throws {
        FactoryMockProtocol.configure(expiresIn: 0, useSSE: false)
        let client = service()
        defer { client.clear() }
        let pending = try await client.beginAuthorization(endpoint: resource,
                                                           registeredClientID: "test-manual-client")
        let callback = try XCTUnwrap(URL(string: "iosnext://factory-oauth?code=mock-code&state=\(pending.state)"))
        try await client.completeAuthorization(callback, original: pending)
        let report = try await client.snapshot()
        XCTAssertEqual(report.rows.count, 3)
        XCTAssertTrue(FactoryMockProtocol.refreshed)
        XCTAssertTrue(FactoryMockProtocol.usedRefreshedToken)
    }

    func testServerWithoutAllowedToolsFailsClosed() async throws {
        FactoryMockProtocol.configure(noReadableTools: true)
        let client = service()
        defer { client.clear() }
        let pending = try await client.beginAuthorization(endpoint: resource,
                                                           registeredClientID: "test-manual-client")
        let callback = try XCTUnwrap(URL(string: "iosnext://factory-oauth?code=mock-code&state=\(pending.state)"))
        try await client.completeAuthorization(callback, original: pending)
        do {
            _ = try await client.snapshot()
            XCTFail("No-read-capability gateway must not be shown as connected")
        } catch FactoryConnectionError.noReadableTools {
            // Correct: no false LIVE status.
        }
    }
}

/// The production default stays KeychainStore. Only unsigned simulator tests
/// use this ephemeral store, shared across two service instances to test restore.
@MainActor
private final class FactoryTestCredentialBox {
    var data: Data?

    var store: FactoryCredentialStore {
        FactoryCredentialStore(
            read: { self.data },
            write: { self.data = $0 },
            delete: { self.data = nil }
        )
    }
}

/// Intercepts only the fixture hostname; never interferes with actual users.
private final class FactoryMockProtocol: URLProtocol {
    private static let mutex = NSLock()
    private static var tools: [String] = []
    private static var methods: [String] = []
    private static var refreshObserved = false
    private static var refreshedTokenObserved = false
    private static var expirySeconds = 3600
    private static var eventStream = false
    private static var noTools = false
    private static var registerStatusCode = 201
    private static var registerErrorCode = "invalid_redirect_uris"
    private static var registerClientIDAvailable = true
    private static var registrationEndpointVisible = true


    static var calledTools: [String] { mutex.withLock { tools } }
    static var calledMethods: [String] { mutex.withLock { methods } }
    static var refreshed: Bool { mutex.withLock { refreshObserved } }
    static var usedRefreshedToken: Bool { mutex.withLock { refreshedTokenObserved } }

    static func reset() {
        mutex.withLock {
            tools = []
            methods = []
            refreshObserved = false
            refreshedTokenObserved = false
            expirySeconds = 3600
            eventStream = false
            noTools = false
            registerStatusCode = 201
            registerErrorCode = "invalid_redirect_uris"
            registerClientIDAvailable = true
            registrationEndpointVisible = true
        }
    }

    static func registrationBehavior(
        status: Int = 201, returnClientID: Bool = true, endpointVisible: Bool = true,
        errorCode: String = "invalid_redirect_uris"
    ) {
        mutex.withLock {
            registerStatusCode = status
            registerErrorCode = errorCode
            registerClientIDAvailable = returnClientID
            registrationEndpointVisible = endpointVisible
        }
    }

    static func configure(expiresIn: Int = 3600, useSSE: Bool = false,
                          noReadableTools: Bool = false) {
        mutex.withLock {
            expirySeconds = expiresIn
            eventStream = useSSE
            noTools = noReadableTools
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "factory-iosnext-test.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        do {
            let response = try Self.reply(to: request)
            let headers = ["Content-Type": response.contentType,
                           "Mcp-Session-Id": "fixture-session-1"]
            let http = HTTPURLResponse(url: url, statusCode: response.status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func jsonData(_ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload)
    }

    private static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable && data.count < 64_000 {
            let size = stream.read(&buffer, maxLength: buffer.count)
            if size <= 0 { break }
            data.append(contentsOf: buffer[..<size])
        }
        return data
    }

    private static func reply(to request: URLRequest) throws
        -> (status: Int, contentType: String, data: Data) {
        let path = request.url?.path ?? ""
        if path == "/.well-known/oauth-protected-resource/mcp" {
            return (200, "application/json", try jsonData([
                "resource": "https://factory-iosnext-test.invalid/mcp",
                "authorization_servers": ["https://factory-iosnext-test.invalid"]
            ]))
        }
        if path == "/.well-known/oauth-authorization-server" {
            return (200, "application/json", try jsonData([
                "issuer": "https://factory-iosnext-test.invalid",
                "authorization_endpoint": "https://factory-iosnext-test.invalid/authorize",
                "token_endpoint": "https://factory-iosnext-test.invalid/token",
                "registration_endpoint": registrationEndpointVisible
                    ? "https://factory-iosnext-test.invalid/register" : "",
                "code_challenge_methods_supported": ["S256"]
            ]))
        }
        if path == "/register" {
            let state = mutex.withLock { (registerStatusCode, registerClientIDAvailable, registerErrorCode) }
            let result: [String: Any] = state.0 == 400
                ? ["error": state.2]
                : (state.1 ? ["client_id": "iosnext-test-public-client"] : [:])
            return (state.0, "application/json", try jsonData(result))
        }
        if path == "/token" {
            let form = String(decoding: requestBody(request), as: UTF8.self)
            let refresh = form.contains("grant_type=refresh_token")
            if refresh { mutex.withLock { refreshObserved = true } }
            let expires = mutex.withLock { expirySeconds }
            return (200, "application/json", try jsonData([
                "access_token": refresh ? "fixture-refreshed" : "fixture-initial",
                "refresh_token": "fixture-refresh",
                "token_type": "Bearer",
                "expires_in": refresh ? 3600 : expires
            ]))
        }
        guard path == "/mcp" else {
            return (404, "application/json", try jsonData(["error": "unknown fixture route"]))
        }
        let payload = (try JSONSerialization.jsonObject(with: requestBody(request))) as? [String: Any] ?? [:]
        let method = payload["method"] as? String ?? ""
        mutex.withLock { methods.append(method) }
        let id = payload["id"] as? String
        guard let id else {
            return (202, "application/json", Data()) // initialized notification
        }
        let parameters = payload["params"] as? [String: Any] ?? [:]
        let toolsList: [[String: String]] = mutex.withLock {
            (noTools ? [] : [
                ["name": "factory_status"],
                ["name": "factory_discover"],
                ["name": "runner_status"]
            ]) + [["name": "dangerous_host_write"]]
        }
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": "2025-06-18",
                "serverInfo": ["name": "factory-fixture", "version": "0.5.4"],
                "capabilities": ["tools": [:]]
            ]
        case "tools/list":
            result = ["tools": toolsList]
        case "tools/call":
            let name = parameters["name"] as? String ?? ""
            mutex.withLock {
                tools.append(name)
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-refreshed" {
                    refreshedTokenObserved = true
                }
            }
            result = ["content": [
                ["type": "text", "text": "{\"status\":\"ok\",\"version\":\"0.5.4\"}"]
            ]]
        default:
            return (400, "application/json", try jsonData(["error": "unknown JSON-RPC method"]))
        }
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        let data = try jsonData(envelope)
        if mutex.withLock({ eventStream }) {
            let content = "event: message\n" +
              "data: {\"jsonrpc\":\"2.0\",\"id\":\"unrelated\",\"result\":{}}\n\n" +
              "event: message\n" +
              "data: \(String(decoding: data, as: UTF8.self))\n\n" +
              ": keepalive\n"
            return (200, "text/event-stream", Data(content.utf8))
        }
        return (200, "application/json", data)
    }
}
