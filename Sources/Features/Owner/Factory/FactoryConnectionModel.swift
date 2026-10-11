import Foundation
import Observation

@MainActor
@Observable
final class FactoryConnectionModel {
    enum Phase: Equatable {
        case disconnected
        case readyForRefresh
        case loading
        case connected
        case failed(String)
        case credentialUnavailable

        var title: String {
            switch self {
            case .disconnected: "Nicht verbunden"
            case .readyForRefresh: "Sitzung gespeichert"
            case .loading: "Synchronisiere …"
            case .connected: "Verbunden"
            case .failed: "Verbindung gestört"
            case .credentialUnavailable: "Schlüsselbund nicht verfügbar"
            }
        }
    }

    var phase: Phase = .disconnected
    var snapshot: FactorySnapshot?
    var errorMessage: String?
    var lastRefresh: Date?
    var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: "factory.mcp.endpoint") }
    }
    var registeredClientID: String {
        didSet { UserDefaults.standard.set(registeredClientID, forKey: "factory.mcp.clientID") }
    }

    private let service: FactoryMCPService
    private var isRefreshing = false
    private(set) var hasRestorableSession = false

    var canRefresh: Bool { hasRestorableSession && phase != .loading }

    init(service suppliedService: FactoryMCPService? = nil) {
        if let suppliedService {
            service = suppliedService
        } else {
#if DEBUG
            // Screenshot harness MUST NOT touch the unsigned simulator Keychain.
            // This is compiled out of the release build and never reports a live session.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--preconnect-ui-acceptance") {
                service = FactoryMCPService(credentials: FactoryCredentialStore(
                    read: {
                        if arguments.contains("--visual-factory-keychain-error") {
                            throw KeychainError.unexpectedStatus(-34018)
                        }
                        return nil
                    },
                    write: { _ in },
                    delete: {}
                ))
            } else {
                service = FactoryMCPService()
            }
#else
            service = FactoryMCPService()
#endif
        }
        endpoint = UserDefaults.standard.string(forKey: "factory.mcp.endpoint")
            ?? "https://master-appliance-build.tailff745a.ts.net/mcp"
        registeredClientID = UserDefaults.standard.string(forKey: "factory.mcp.clientID") ?? ""
        do {
            if try service.restore() {
                hasRestorableSession = true
                phase = .readyForRefresh
            }
        } catch let error as KeychainError {
            phase = .credentialUnavailable
            errorMessage = error.localizedDescription
        } catch {
            phase = .failed("Gespeicherte Factory-Sitzung ist ungültig.")
            errorMessage = error.localizedDescription
        }
    }

    func beginAuthorization() async throws -> FactoryAuthorization {
        errorMessage = nil
        phase = .loading
        do {
            return try await service.beginAuthorization(
                endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                registeredClientID: registeredClientID.isEmpty ? nil : registeredClientID
            )
        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// A cancelled browser prompt must not leave the connection spinning.
    func cancelAuthorization() {
        errorMessage = nil
        do {
            hasRestorableSession = try service.restore()
            phase = hasRestorableSession ? .readyForRefresh : .disconnected
        } catch let error as KeychainError {
            hasRestorableSession = false
            phase = .credentialUnavailable
            errorMessage = error.localizedDescription
        } catch {
            hasRestorableSession = false
            phase = .failed("Gespeicherte Factory-Sitzung ist ungültig.")
            errorMessage = error.localizedDescription
        }
    }

    func finishAuthorization(callback: URL, original: FactoryAuthorization) async throws {
        do {
            try await service.completeAuthorization(callback, original: original)
            hasRestorableSession = true
            phase = .readyForRefresh
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func refresh() async {
        guard hasRestorableSession, !isRefreshing else { return }
        isRefreshing = true
        phase = .loading
        defer { isRefreshing = false }
        do {
            let updated = try await service.snapshot()
            snapshot = updated
            lastRefresh = updated.observedAt
            errorMessage = nil
            phase = .connected
        } catch {
            // Preserve last verified snapshot only while in the current session;
            // its timestamp makes stale information visible.
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        service.clear()
        hasRestorableSession = false
        snapshot = nil
        lastRefresh = nil
        errorMessage = nil
        phase = .disconnected
    }
}
