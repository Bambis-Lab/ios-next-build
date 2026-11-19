import CryptoKit
import Foundation
import Security

enum ChatHistoryError: LocalizedError {
    case invalidScope, missingKey, invalidArchive, capacity
    var errorDescription: String? { "Der verschlüsselte Chatverlauf konnte nicht sicher gespeichert oder geöffnet werden." }
}

/// Local-only, authenticated, account/device/endpoint scoped archive.
/// A missing key for an existing archive never triggers replacement.
/// All callers are serialized on the main actor. No plaintext file is written.
@MainActor
final class ChatHistoryArchive {
    private let url: URL
    private let key: SymmetricKey
    private let aad: Data
    private static let maxBytes = 384 * 1024 * 1024
    private static let magic = Data("IOSNEXT-CHAT-HISTORY-1".utf8)

    convenience init(configuration: ChatConfiguration) throws {
        guard configuration.baseURL.scheme == "https",
              !configuration.userID.isEmpty, !configuration.deviceID.isEmpty else {
            throw ChatHistoryError.invalidScope
        }
        let scope = try JSONEncoder().encode([configuration.baseURL.absoluteString,
                                              configuration.userID, configuration.deviceID])
        try self.init(scopedData: scope, namespace: "chatHistory.v1", folder: "EncryptedChatHistory")
    }

    /// Separate Keychain namespace and directory for each local protocol.
    convenience init(scopedData scope: Data, namespace: String, folder: String) throws {
        guard !scope.isEmpty, scope.count <= 8192,
              [( "chatHistory.v1", "EncryptedChatHistory"),
               ( "ticketOutbox.v1", "EncryptedTicketOutbox"),
               ( "ticketProject.v1", "EncryptedTicketProjects"),
               ( "ticketCache.v1", "EncryptedTicketCache")].contains(where: { $0.0 == namespace && $0.1 == folder })
        else { throw ChatHistoryError.invalidScope }
        let digest = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = directory
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try excluded.setResourceValues(flags)
        let path = directory.appendingPathComponent(digest + ".enc")
        let account = namespace + "." + digest
        let raw: Data
        if let existing = try KeychainStore.data(account: account) {
            raw = existing
        } else {
            guard !FileManager.default.fileExists(atPath: path.path) else { throw ChatHistoryError.missingKey }
            raw = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try KeychainStore.save(raw, account: account, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        }
        try self.init(file: path, scope: scope, keyData: raw)
    }

    // Deterministic injection for isolated tests only.
    init(file: URL, scope: Data, keyData: Data) throws {
        guard keyData.count == 32, !scope.isEmpty else { throw ChatHistoryError.invalidArchive }
        url = file
        key = SymmetricKey(data: keyData)
        aad = Self.magic + Data([0]) + scope
    }

    func load<T: Decodable>(_ type: T.Type) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maxBytes, size >= Self.magic.count + 28 else {
            throw ChatHistoryError.invalidArchive
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maxBytes, data.starts(with: Self.magic) else {
            throw ChatHistoryError.invalidArchive
        }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
            let plain = try AES.GCM.open(box, using: key, authenticating: aad)
            return try JSONDecoder().decode(type, from: plain)
        } catch { throw ChatHistoryError.invalidArchive }
    }

    func save<T: Encodable>(_ value: T) throws {
        let plain = try JSONEncoder().encode(value)
        guard plain.count <= Self.maxBytes - Self.magic.count - 28 else { throw ChatHistoryError.capacity }
        let box = try AES.GCM.seal(plain, using: key, authenticating: aad)
        guard let combined = box.combined else { throw ChatHistoryError.invalidArchive }
        try (Self.magic + combined).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

/// Synchronous transaction boundary for a verified received fragment. The
/// previous state must be a value snapshot, not a mutable shared reference.
@MainActor
enum ChatHistoryCheckpoint {
    static func commit<State>(previous: State, mutate: () throws -> Void,
                              persist: () throws -> Void, restore: (State) -> Void) throws {
        do {
            try mutate()
            try persist()
        } catch {
            restore(previous)
            throw error
        }
    }
}
