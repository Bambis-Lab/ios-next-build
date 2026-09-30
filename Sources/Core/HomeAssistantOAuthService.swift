import AuthenticationServices
import Foundation
import UIKit

struct HomeAssistantOAuthConfiguration: Equatable, Sendable {
    let instanceURL: URL
    let clientID: URL

    static let redirectURL = URL(string: "iosnext://auth")!
    static let productionClientID = URL(string: "https://bambis-lab.github.io/ios-next-releases/oauth-client.html")!

    static func normalizedInstanceURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let candidate: URL?
        if value.contains("://") {
            candidate = URL(string: value)
        } else if let localCandidate = URL(string: "http://\(value)"),
                  let host = localCandidate.host,
                  isLocalHost(host) {
            candidate = localCandidate
        } else {
            candidate = URL(string: "https://\(value)")
        }

        guard let candidate,
              let scheme = candidate.scheme?.lowercased(),
              let host = candidate.host,
              !host.isEmpty,
              candidate.user == nil,
              candidate.password == nil,
              candidate.query == nil,
              candidate.fragment == nil else { return nil }

        if scheme == "https" { return candidate }
        if scheme == "http", isAllowedInsecureHost(host) { return candidate }
        return nil
    }

    private static func isAllowedInsecureHost(_ host: String) -> Bool {
        isLocalHost(host) || isTailscaleHost(host)
    }

    private static func isTailscaleHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value.hasSuffix(".ts.net") { return true }

        let octets = value.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0 ... 255 ~= $0 }) else { return false }
        return octets[0] == 100 && (64 ... 127).contains(octets[1])
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value.hasSuffix(".local") || value == "::1" { return true }
        if value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd") { return true }

        let octets = value.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0 ... 255 ~= $0 }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254):
            return true
        case (172, 16 ... 31):
            return true
        default:
            return false
        }
    }

    var authorizationURL: URL? {
        authorizationURL(state: nil)
    }

    func authorizationURL(state: String?) -> URL? {
        var components = URLComponents(url: instanceURL.appending(path: "auth/authorize"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "client_id", value: clientID.absoluteString),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURL.absoluteString)
        ]
        if let state { items.append(URLQueryItem(name: "state", value: state)) }
        components?.queryItems = items
        return components?.url
    }

    var tokenURL: URL {
        instanceURL.appending(path: "auth/token")
    }
}

struct HomeAssistantOAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct HomeAssistantOAuthCredential: Codable, Equatable, Sendable {
    let configuration: HomeAssistantOAuthConfiguration
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

extension HomeAssistantOAuthConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case instanceURL
        case clientID
    }
}

enum HomeAssistantOAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case authorizationSessionFailed(String)
    case missingAuthorizationCode
    case callbackMismatch
    case stateMismatch
    case authorizationDenied(String)
    case tokenTransportFailed(String)
    case tokenExchangeFailed(Int?)
    case tokenResponseInvalid

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Die OAuth-Konfiguration ist ungültig."
        case let .authorizationSessionFailed(message): "OAuth-Anmeldung fehlgeschlagen: \(message)"
        case .missingAuthorizationCode: "OAuth-Rückruf fehlgeschlagen: Home Assistant hat keinen Autorisierungscode zurückgegeben."
        case .callbackMismatch: "OAuth-Rückruf fehlgeschlagen: Der Rückruf gehört nicht zu iOS Next."
        case .stateMismatch: "OAuth-Rückruf fehlgeschlagen: Der Rückruf konnte nicht sicher zugeordnet werden."
        case let .authorizationDenied(message): "OAuth-Anmeldung abgelehnt: \(message)"
        case let .tokenTransportFailed(message): "Token-Austausch mit Home Assistant fehlgeschlagen: \(message)"
        case let .tokenExchangeFailed(status):
            status.map { "Token-Austausch mit Home Assistant fehlgeschlagen (HTTP \($0))." }
                ?? "Token-Austausch mit Home Assistant fehlgeschlagen."
        case .tokenResponseInvalid: "Token-Austausch mit Home Assistant fehlgeschlagen: ungültige Token-Antwort."
        }
    }
}

@MainActor
final class HomeAssistantOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var authenticationSession: ASWebAuthenticationSession?
    private var presentationAnchorWindow: UIWindow?

    func authorize(using configuration: HomeAssistantOAuthConfiguration) async throws -> HomeAssistantOAuthTokens {
        let expectedState = UUID().uuidString
        guard let authorizationURL = configuration.authorizationURL(state: expectedState) else {
            throw HomeAssistantOAuthError.invalidConfiguration
        }
        let callbackURL: URL
        do {
            callbackURL = try await openAuthorizationSession(url: authorizationURL)
        } catch let error as HomeAssistantOAuthError {
            throw error
        } catch {
            throw HomeAssistantOAuthError.authorizationSessionFailed(error.localizedDescription)
        }
        let code = try Self.authorizationCode(from: callbackURL, expectedState: expectedState)
        return try await exchange(code: code, using: configuration)
    }

    nonisolated static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard callbackURL.scheme == HomeAssistantOAuthConfiguration.redirectURL.scheme,
              callbackURL.host == HomeAssistantOAuthConfiguration.redirectURL.host else {
            throw HomeAssistantOAuthError.callbackMismatch
        }

        let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard callbackComponents?.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            throw HomeAssistantOAuthError.stateMismatch
        }
        if let error = callbackComponents?.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = callbackComponents?.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw HomeAssistantOAuthError.authorizationDenied(description ?? error)
        }
        guard let code = callbackComponents?.queryItems?
            .first(where: { $0.name == "code" })?
            .value,
            !code.isEmpty
        else {
            throw HomeAssistantOAuthError.missingAuthorizationCode
        }
        return code
    }

    func refresh(_ credential: HomeAssistantOAuthCredential) async throws -> HomeAssistantOAuthCredential {
        guard credential.needsRefresh else { return credential }
        var request = URLRequest(url: credential.configuration.tokenURL)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": credential.refreshToken,
            "client_id": credential.configuration.clientID.absoluteString
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HomeAssistantOAuthError.tokenTransportFailed(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeAssistantOAuthError.tokenExchangeFailed(nil)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw HomeAssistantOAuthError.tokenExchangeFailed(httpResponse.statusCode)
        }
        let tokens: HomeAssistantOAuthRefreshTokens
        do {
            tokens = try JSONDecoder().decode(HomeAssistantOAuthRefreshTokens.self, from: data)
        } catch {
            throw HomeAssistantOAuthError.tokenResponseInvalid
        }
        return HomeAssistantOAuthCredential(
            configuration: credential.configuration,
            accessToken: tokens.accessToken,
            refreshToken: credential.refreshToken,
            expiresAt: Date().addingTimeInterval(tokens.expiresIn)
        )
    }

    private func openAuthorizationSession(url: URL) async throws -> URL {
        guard let presentationAnchor = activePresentationAnchor() else {
            throw HomeAssistantOAuthError.invalidConfiguration
        }

        return try await withCheckedThrowingContinuation { continuation in
            let callbackScheme = HomeAssistantOAuthConfiguration.redirectURL.scheme ?? "iosnext"
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { [weak self] callbackURL, error in
                self?.authenticationSession = nil
                self?.presentationAnchorWindow = nil

                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: HomeAssistantOAuthError.callbackMismatch)
                }
            }
            presentationAnchorWindow = presentationAnchor
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            guard session.start() else {
                authenticationSession = nil
                presentationAnchorWindow = nil
                continuation.resume(throwing: HomeAssistantOAuthError.invalidConfiguration)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let presentationAnchorWindow {
            return presentationAnchorWindow
        }
        if let activeWindow = activePresentationAnchor() {
            presentationAnchorWindow = activeWindow
            return activeWindow
        }
        preconditionFailure("ASWebAuthenticationSession requested a presentation anchor without an active foreground window")
    }

    private func activePresentationAnchor() -> UIWindow? {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        for scene in activeScenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow && !$0.isHidden && $0.alpha > 0 && $0.windowLevel == .normal }) {
                return keyWindow
            }
        }

        for scene in activeScenes {
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 && $0.windowLevel == .normal }) {
                return visibleWindow
            }
        }

        return nil
    }

    private func exchange(code: String, using configuration: HomeAssistantOAuthConfiguration) async throws -> HomeAssistantOAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": configuration.clientID.absoluteString
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HomeAssistantOAuthError.tokenTransportFailed(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeAssistantOAuthError.tokenExchangeFailed(nil)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw HomeAssistantOAuthError.tokenExchangeFailed(httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(HomeAssistantOAuthTokens.self, from: data)
        } catch {
            throw HomeAssistantOAuthError.tokenResponseInvalid
        }
    }

    private func formBody(_ parameters: [String: String]) -> Data? {
        let value = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key.percentEncodedForForm)=\(value.percentEncodedForForm)"
            }
            .joined(separator: "&")
        return Data(value.utf8)
    }
}

private struct HomeAssistantOAuthRefreshTokens: Codable {
    let accessToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private extension String {
    var percentEncodedForForm: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self
    }
}
