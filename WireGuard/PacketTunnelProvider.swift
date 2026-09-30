import Foundation
import NetworkExtension
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var adapter = WireGuardAdapter(with: self) { _, _ in
        // Intentionally do not persist WireGuard runtime logs or configuration material.
    }

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
                  let reference = tunnelProtocol.passwordReference else {
                throw PacketTunnelError.configurationMissing
            }
            let text = try WireGuardKeychain.configuration(referencedBy: reference)
            let validated = try WireGuardConfigurationValidator.validate(text)
            let configuration = try validated.makeTunnelConfiguration(name: tunnelProtocol.serverAddress)
            adapter.start(tunnelConfiguration: configuration) { error in
                if error == nil { completionHandler(nil) }
                else { completionHandler(PacketTunnelError.backendStartFailed) }
            }
        } catch {
            completionHandler(PacketTunnelError.configurationInvalid)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        adapter.stop { _ in completionHandler() }
    }
}

private enum PacketTunnelError: LocalizedError {
    case configurationMissing
    case configurationInvalid
    case backendStartFailed

    var errorDescription: String? {
        switch self {
        case .configurationMissing: "WireGuard configuration is missing."
        case .configurationInvalid: "WireGuard configuration is invalid."
        case .backendStartFailed: "WireGuard backend could not start."
        }
    }
}
