import Foundation
import Network

struct ValidatedWireGuardConfiguration: Sendable {
    struct Interface: Sendable {
        let privateKey: String
        let addresses: [String]
        let dnsServers: [String]
        let listenPort: UInt16?
        let mtu: UInt16?
    }

    struct Peer: Sendable {
        let publicKey: String
        let preSharedKey: String?
        let allowedIPs: [String]
        let endpoint: String
        let persistentKeepalive: UInt16?
    }

    let rawConfiguration: String
    let interface: Interface
    let peers: [Peer]

    var endpoints: [String] { peers.map(\.endpoint) }
}

enum WireGuardConfigurationError: LocalizedError {
    case empty
    case invalidSection
    case invalidLine
    case unsupportedDirective(String)
    case missingInterface
    case missingPrivateKey
    case invalidPrivateKey
    case missingPeer
    case missingPublicKey
    case invalidPublicKey
    case invalidPreSharedKey
    case missingEndpoint
    case invalidEndpoint
    case missingAllowedIPs
    case invalidAllowedIPs
    case invalidKeepalive
    case missingAddress
    case invalidAddress
    case invalidDNS
    case invalidListenPort
    case invalidMTU
    case duplicatePeer
    case tooLarge
    case tooManyPeers

    var errorDescription: String? {
        switch self {
        case .empty: "Die WireGuard-Konfiguration ist leer."
        case .invalidSection: "Die WireGuard-Konfiguration enthält einen ungültigen Abschnitt."
        case .invalidLine: "Die WireGuard-Konfiguration enthält eine ungültige Zeile."
        case let .unsupportedDirective(key): "Die nicht unterstützte WireGuard-Anweisung „\(key)“ wurde blockiert."
        case .missingInterface: "Der Abschnitt [Interface] fehlt."
        case .missingPrivateKey: "Der private WireGuard-Schlüssel fehlt."
        case .invalidPrivateKey: "Der private WireGuard-Schlüssel ist ungültig."
        case .missingPeer: "Mindestens ein [Peer]-Abschnitt ist erforderlich."
        case .missingPublicKey: "Ein öffentlicher Peer-Schlüssel fehlt."
        case .invalidPublicKey: "Ein öffentlicher Peer-Schlüssel ist ungültig."
        case .invalidPreSharedKey: "Ein Pre-Shared Key ist ungültig."
        case .missingEndpoint: "Ein WireGuard-Endpunkt fehlt."
        case .invalidEndpoint: "Ein WireGuard-Endpunkt ist ungültig."
        case .missingAllowedIPs: "AllowedIPs fehlt für einen Peer."
        case .invalidAllowedIPs: "AllowedIPs enthält einen ungültigen Eintrag."
        case .invalidKeepalive: "PersistentKeepalive ist ungültig."
        case .missingAddress: "Mindestens eine Tunnel-Adresse fehlt."
        case .invalidAddress: "Die Tunnel-Adresse ist ungültig."
        case .invalidDNS: "Der DNS-Server ist ungültig; nur IP-Adressen sind erlaubt."
        case .invalidListenPort: "Der WireGuard-Listen-Port ist ungültig."
        case .invalidMTU: "Die WireGuard-MTU muss zwischen 576 und 9000 liegen."
        case .duplicatePeer: "Öffentliche Peer-Schlüssel dürfen nicht doppelt vorkommen."
        case .tooLarge: "Die WireGuard-Konfiguration ist zu groß."
        case .tooManyPeers: "Die WireGuard-Konfiguration enthält zu viele Peers."
        }
    }
}

enum WireGuardConfigurationValidator {
    private enum Section { case interface, peer }

    static func validate(_ input: String) throws -> ValidatedWireGuardConfiguration {
        guard input.utf8.count <= 64 * 1024 else { throw WireGuardConfigurationError.tooLarge }
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WireGuardConfigurationError.empty
        }

        let interfaceKeys: Set<String> = ["privatekey", "address", "dns", "listenport", "mtu"]
        let peerKeys: Set<String> = ["publickey", "presharedkey", "allowedips", "endpoint", "persistentkeepalive"]
        let explicitlyBlocked: Set<String> = ["preup", "postup", "predown", "postdown", "table", "fwmark", "saveconfig"]
        var section: Section?
        var interfaceCount = 0
        var interfaceValues: [String: String] = [:]
        var peerValues: [[String: String]] = []
        var activePeer: [String: String]?

        func finishPeer() {
            if let activePeer { peerValues.append(activePeer) }
        }

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let line = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else { throw WireGuardConfigurationError.invalidSection }
                let name = line.dropFirst().dropLast().lowercased()
                switch name {
                case "interface":
                    finishPeer()
                    activePeer = nil
                    interfaceCount += 1
                    guard interfaceCount == 1 else { throw WireGuardConfigurationError.invalidSection }
                    section = .interface
                case "peer":
                    finishPeer()
                    activePeer = [:]
                    section = .peer
                default:
                    throw WireGuardConfigurationError.invalidSection
                }
                continue
            }

            guard let section, let separator = line.firstIndex(of: "=") else {
                throw WireGuardConfigurationError.invalidLine
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedKey = key.lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw WireGuardConfigurationError.invalidLine }
            if explicitlyBlocked.contains(normalizedKey) {
                throw WireGuardConfigurationError.unsupportedDirective(key)
            }
            switch section {
            case .interface:
                guard interfaceKeys.contains(normalizedKey) else {
                    throw WireGuardConfigurationError.unsupportedDirective(key)
                }
                guard interfaceValues[normalizedKey] == nil else { throw WireGuardConfigurationError.invalidLine }
                interfaceValues[normalizedKey] = value
            case .peer:
                guard peerKeys.contains(normalizedKey) else {
                    throw WireGuardConfigurationError.unsupportedDirective(key)
                }
                guard activePeer?[normalizedKey] == nil else { throw WireGuardConfigurationError.invalidLine }
                activePeer?[normalizedKey] = value
            }
        }
        finishPeer()

        guard interfaceCount == 1 else { throw WireGuardConfigurationError.missingInterface }
        guard let privateKey = interfaceValues["privatekey"] else { throw WireGuardConfigurationError.missingPrivateKey }
        guard isValidKey(privateKey) else { throw WireGuardConfigurationError.invalidPrivateKey }
        guard let addressValue = interfaceValues["address"] else { throw WireGuardConfigurationError.missingAddress }
        let addresses = commaSeparated(addressValue)
        guard !addresses.isEmpty else { throw WireGuardConfigurationError.missingAddress }
        guard addresses.allSatisfy(isValidIPRange) else { throw WireGuardConfigurationError.invalidAddress }
        let dnsServers = interfaceValues["dns"].map(commaSeparated) ?? []
        guard dnsServers.allSatisfy({ IPv4Address($0) != nil || IPv6Address($0) != nil }) else {
            throw WireGuardConfigurationError.invalidDNS
        }
        let listenPort = try optionalUInt16(interfaceValues["listenport"], error: .invalidListenPort)
        let mtu = try optionalUInt16(interfaceValues["mtu"], error: .invalidMTU)
        if let mtu, !(576...9000).contains(Int(mtu)) { throw WireGuardConfigurationError.invalidMTU }
        guard !peerValues.isEmpty else { throw WireGuardConfigurationError.missingPeer }
        guard peerValues.count <= 32 else { throw WireGuardConfigurationError.tooManyPeers }

        var peers: [ValidatedWireGuardConfiguration.Peer] = []
        var publicKeys = Set<String>()
        for peer in peerValues {
            guard let publicKey = peer["publickey"] else { throw WireGuardConfigurationError.missingPublicKey }
            guard isValidKey(publicKey) else { throw WireGuardConfigurationError.invalidPublicKey }
            guard publicKeys.insert(publicKey).inserted else { throw WireGuardConfigurationError.duplicatePeer }
            if let preSharedKey = peer["presharedkey"], !isValidKey(preSharedKey) {
                throw WireGuardConfigurationError.invalidPreSharedKey
            }
            guard let endpoint = peer["endpoint"] else { throw WireGuardConfigurationError.missingEndpoint }
            guard isValidEndpoint(endpoint) else { throw WireGuardConfigurationError.invalidEndpoint }
            guard let allowedIPs = peer["allowedips"] else { throw WireGuardConfigurationError.missingAllowedIPs }
            let parsedAllowedIPs = commaSeparated(allowedIPs)
            guard !parsedAllowedIPs.isEmpty, parsedAllowedIPs.allSatisfy(isValidIPRange) else {
                throw WireGuardConfigurationError.invalidAllowedIPs
            }
            let keepalive = try optionalUInt16(peer["persistentkeepalive"], error: .invalidKeepalive)
            peers.append(.init(
                publicKey: publicKey,
                preSharedKey: peer["presharedkey"],
                allowedIPs: parsedAllowedIPs,
                endpoint: endpoint,
                persistentKeepalive: keepalive
            ))
        }
        return .init(
            rawConfiguration: normalized,
            interface: .init(
                privateKey: privateKey,
                addresses: addresses,
                dnsServers: dnsServers,
                listenPort: listenPort,
                mtu: mtu
            ),
            peers: peers
        )
    }

    private static func isValidKey(_ value: String) -> Bool {
        Data(base64Encoded: value)?.count == 32
    }

    private static func isValidEndpoint(_ value: String) -> Bool {
        guard !value.contains("://"), !value.contains("/"), !value.contains(" ") else { return false }
        if value.hasPrefix("[") {
            guard let closing = value.lastIndex(of: "]"),
                  value.index(after: closing) < value.endIndex,
                  value[value.index(after: closing)] == ":" else { return false }
            let host = String(value[value.index(after: value.startIndex)..<closing])
            return IPv6Address(host) != nil && validPort(value[value.index(closing, offsetBy: 2)...])
        }
        guard let separator = value.lastIndex(of: ":"), separator != value.startIndex else { return false }
        let host = String(value[..<separator])
        guard IPv4Address(host) != nil || isValidHostname(host) else { return false }
        return validPort(value[value.index(after: separator)...])
    }

    private static func commaSeparated(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func isValidIPRange(_ value: String) -> Bool {
        guard let slash = value.lastIndex(of: "/"), slash != value.startIndex else { return false }
        let address = String(value[..<slash])
        guard let prefix = Int(value[value.index(after: slash)...]) else { return false }
        if IPv4Address(address) != nil { return (0...32).contains(prefix) }
        if IPv6Address(address) != nil { return (0...128).contains(prefix) }
        return false
    }

    private static func optionalUInt16(
        _ value: String?,
        error: WireGuardConfigurationError
    ) throws -> UInt16? {
        guard let value else { return nil }
        guard let parsed = UInt16(value) else { throw error }
        return parsed
    }

    private static func validPort(_ value: Substring) -> Bool {
        guard let port = UInt16(value) else { return false }
        return port > 0
    }

    private static func isValidHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.first != "-", label.last != "-" else { return false }
            return label.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
            }
        }
    }
}
