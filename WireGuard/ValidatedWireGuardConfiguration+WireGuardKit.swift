import Foundation
import WireGuardKit

extension ValidatedWireGuardConfiguration {
    func makeTunnelConfiguration(name: String?) throws -> TunnelConfiguration {
        guard let privateKey = PrivateKey(base64Key: interface.privateKey) else {
            throw WireGuardConfigurationError.invalidPrivateKey
        }
        var wireGuardInterface = InterfaceConfiguration(privateKey: privateKey)
        wireGuardInterface.addresses = try interface.addresses.map {
            guard let value = IPAddressRange(from: $0) else {
                throw WireGuardConfigurationError.invalidAddress
            }
            return value
        }
        wireGuardInterface.dns = try interface.dnsServers.map {
            guard let value = DNSServer(from: $0) else {
                throw WireGuardConfigurationError.invalidDNS
            }
            return value
        }
        wireGuardInterface.listenPort = interface.listenPort
        wireGuardInterface.mtu = interface.mtu

        let wireGuardPeers = try peers.map { peer in
            guard let publicKey = PublicKey(base64Key: peer.publicKey) else {
                throw WireGuardConfigurationError.invalidPublicKey
            }
            guard let endpoint = Endpoint(from: peer.endpoint) else {
                throw WireGuardConfigurationError.invalidEndpoint
            }
            var result = PeerConfiguration(publicKey: publicKey)
            if let preSharedKey = peer.preSharedKey {
                guard let parsed = PreSharedKey(base64Key: preSharedKey) else {
                    throw WireGuardConfigurationError.invalidPreSharedKey
                }
                result.preSharedKey = parsed
            }
            result.allowedIPs = try peer.allowedIPs.map {
                guard let value = IPAddressRange(from: $0) else {
                    throw WireGuardConfigurationError.invalidAllowedIPs
                }
                return value
            }
            result.endpoint = endpoint
            result.persistentKeepAlive = peer.persistentKeepalive
            return result
        }
        return TunnelConfiguration(name: name, interface: wireGuardInterface, peers: wireGuardPeers)
    }
}
