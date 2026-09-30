import Foundation
import Security

enum KeychainStore {
    private static let service = "de.nicofroeba16.iosnext"

    static func save(_ value: String, account: String) throws {
        try save(Data(value.utf8), account: account)
    }

    static func save(
        _ data: Data,
        account: String,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: accessibility
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func value(account: String) throws -> String? {
        guard let data = try data(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return data
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus: "Der sichere iOS-Schlüsselspeicher konnte nicht verwendet werden."
        case .configurationMissing: "Die signierte WireGuard-Schlüsselbundgruppe ist noch nicht eingerichtet."
        }
    }
}
