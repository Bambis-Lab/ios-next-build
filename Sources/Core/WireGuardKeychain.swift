import Foundation
import Security

enum WireGuardKeychain {
    private static let service = "de.nicofroeba16.iosnext.wireguard"
    private static let account = "active-wg-quick-configuration"

    static func replaceConfiguration(_ configuration: String) throws -> Data {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: try accessGroup(),
        ]
        var referenceQuery = baseQuery
        referenceQuery[kSecReturnPersistentRef] = true
        referenceQuery[kSecMatchLimit] = kSecMatchLimitOne
        var existingReference: CFTypeRef?
        let lookupStatus = SecItemCopyMatching(referenceQuery as CFDictionary, &existingReference)
        if lookupStatus == errSecSuccess, let reference = existingReference as? Data {
            let status = SecItemUpdate(baseQuery as CFDictionary, [
                kSecValueData: Data(configuration.utf8),
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            return reference
        }
        guard lookupStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(lookupStatus)
        }
        var item = baseQuery
        item[kSecValueData] = Data(configuration.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecReturnPersistentRef] = true
        var result: CFTypeRef?
        let status = SecItemAdd(item as CFDictionary, &result)
        guard status == errSecSuccess, let reference = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return reference
    }

    static func currentConfiguration() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: try accessGroup(),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let configuration = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return configuration
    }

    static func configuration(referencedBy reference: Data) throws -> String {
        let query: [CFString: Any] = [
            kSecValuePersistentRef: reference,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let configuration = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return configuration
    }

    static func deleteConfiguration() {
        guard let group = try? accessGroup() else { return }
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: group,
        ] as CFDictionary)
    }

    private static func accessGroup() throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "IOSNextWireGuardKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            throw KeychainError.configurationMissing
        }
        return value
    }
}
