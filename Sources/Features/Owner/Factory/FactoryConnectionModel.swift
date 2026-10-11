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

        var title: String {
            switch self {
            case .disconnected: "Nicht verbunden"
            case .readyForRefresh: "Sitzung gespeichert"
            case .loading: "Synchronisiere …"
            case .connected: "Verbunden"
            case .failed: "Verbindung gestört"
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

    private let service = FactoryMCPService()
    private var isRefreshing = false

    init() {
        endpoint = UserDefaults.standard.string(forKey: "factory.mcp.endpoint")
            ?? "https://master-appliance-build.tailff745a.ts.net/mcp"
        registeredClientID = UserDefaults.standard.string(forKey: "factory.mcp.clientID") ?? ""
        do {
            if try service.restore() { phase = .readyForRefresh }
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

    func finishAuthorization(callback: URL, original: FactoryAuthorization) async throws {
        do {
            try await service.completeAuthorization(callback, original: original)
            phase = .readyForRefresh
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func refresh() async {
        if isRefreshing || phase == .disconnected { return }
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
        snapshot = nil
        lastRefresh = nil
        errorMessage = nil
        phase = .disconnected
    }
}
