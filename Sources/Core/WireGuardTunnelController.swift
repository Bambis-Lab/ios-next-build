import Foundation
import NetworkExtension
import Observation

enum WireGuardTunnelError: LocalizedError {
    case managerUnavailable
    case configurationNotInstalled
    case macSigningRequired

    var errorDescription: String? {
        switch self {
        case .managerUnavailable: "Die iOS-VPN-Verwaltung ist nicht verfügbar."
        case .configurationNotInstalled: "Es ist noch keine WireGuard-Konfiguration installiert."
        case .macSigningRequired: "WireGuard benötigt zuerst das signierte Packet-Tunnel-Target aus dem Mac-Handoff."
        }
    }
}

@MainActor
@Observable
final class WireGuardTunnelController {
    enum State: Equatable {
        case unavailable
        case notConfigured
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(String)
    }

    var state: State = .notConfigured
    var isOnDemandEnabled = true
    private var manager: NETunnelProviderManager?
    private let providerBundleIdentifier = "de.nicofroeba16.iosnext.packet-tunnel"

    func refresh() async {
        do {
            manager = try await installedManager()
            if let manager { isOnDemandEnabled = manager.isOnDemandEnabled }
            updateState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func install(configurationText: String) async throws {
        let validated = try WireGuardConfigurationValidator.validate(configurationText)
        let previousConfiguration = try WireGuardKeychain.currentConfiguration()
        let reference = try WireGuardKeychain.replaceConfiguration(validated.rawConfiguration)
        do {
            let manager = try await installedManager() ?? NETunnelProviderManager()
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = providerBundleIdentifier
            tunnelProtocol.serverAddress = validated.endpoints.count == 1 ? validated.endpoints[0] : "Multiple WireGuard peers"
            tunnelProtocol.passwordReference = reference
            tunnelProtocol.disconnectOnSleep = false
            manager.protocolConfiguration = tunnelProtocol
            manager.localizedDescription = "iOS Next WireGuard"
            manager.isEnabled = true
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = isOnDemandEnabled
            try await save(manager)
            try await load(manager)
            self.manager = manager
            updateState()
        } catch {
            if let previousConfiguration {
                _ = try? WireGuardKeychain.replaceConfiguration(previousConfiguration)
            } else {
                WireGuardKeychain.deleteConfiguration()
            }
            throw error
        }
    }

    func connect() async {
        do {
            guard let manager = try await resolvedManager() else {
                throw WireGuardTunnelError.configurationNotInstalled
            }
            try manager.connection.startVPNTunnel()
            self.manager = manager
            updateState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        updateState()
    }

    func updateOnDemand() async {
        do {
            guard let manager = try await resolvedManager() else { return }
            manager.isOnDemandEnabled = isOnDemandEnabled
            if isOnDemandEnabled, manager.onDemandRules?.isEmpty != false {
                let connectRule = NEOnDemandRuleConnect()
                connectRule.interfaceTypeMatch = .any
                manager.onDemandRules = [connectRule]
            }
            try await save(manager)
            try await load(manager)
            self.manager = manager
            updateState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func removeConfiguration() async {
        do {
            if let manager = try await resolvedManager() {
                manager.connection.stopVPNTunnel()
                try await remove(manager)
            }
            WireGuardKeychain.deleteConfiguration()
            manager = nil
            state = .notConfigured
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func installedManager() async throws -> NETunnelProviderManager? {
        let providerBundleIdentifier = self.providerBundleIdentifier
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: managers ?? []) }
            }
        }
        return managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == providerBundleIdentifier
        })
    }

    private func resolvedManager() async throws -> NETunnelProviderManager? {
        if let manager { return manager }
        return try await installedManager()
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func load(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func remove(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func updateState() {
        guard let manager else {
            state = .notConfigured
            return
        }
        switch manager.connection.status {
        case .invalid: state = .notConfigured
        case .disconnected: state = .disconnected
        case .connecting, .reasserting: state = .connecting
        case .connected: state = .connected
        case .disconnecting: state = .disconnecting
        @unknown default: state = .unavailable
        }
    }
}
