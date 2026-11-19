import Foundation
import CryptoKit

/// Prepared cutover only; production ChatModel must not select this store
/// until its serialized receive/send path and explicit migration gate pass.
/// No automatic activation, deletion, source overwrite or legacy fallback.
@MainActor
final class ChatV2MigrationCoordinator {
    struct Source: Equatable, Sendable {
        let snapshot: ChatPersistentSnapshot
        let ciphertextFingerprint: Data?
    }
    private struct Marker: Codable, Equatable {
        let schema: Int
        let scopeDigest: Data
        let sourceFingerprint: Data?
    }
    enum Failure: Error, Equatable {
        case busy, notPrepared, alreadyActivated, sourceChanged, missingCandidate, invalidMarker, authorizationChanged
    }

    private let file: URL
    private let scope: Data
    private let scopeDigest: Data
    private let key: Data
    private let readMarker: () throws -> Data?
    private let insertMarker: (Data) throws -> Bool
    private var busy = false

    struct Binding: Equatable {
        let scope: Data
        let digest: String
        let markerAccount: String
    }

    static func binding(configuration: ChatConfiguration, keyFingerprint: String) throws -> Binding {
        guard configuration.baseURL.scheme == "https",
              !configuration.userID.isEmpty, !configuration.deviceID.isEmpty,
              !keyFingerprint.isEmpty else { throw ChatHistoryError.invalidScope }
        let stable = try JSONEncoder().encode([configuration.baseURL.absoluteString,
            configuration.userID, configuration.deviceID])
        let scope = try JSONEncoder().encode([configuration.baseURL.absoluteString,
            configuration.userID, configuration.deviceID, keyFingerprint])
        func hex(_ value: Data) -> String {
            SHA256.hash(data:value).map { String(format:"%02x",$0) }.joined()
        }
        // Never derive the *activation marker address* from the current chat
        // key. A changed key must reach the existing marker and fail closed.
        return Binding(scope:scope,digest:hex(scope),markerAccount:"chatHistory.v2.active."+hex(stable))
    }

    static func hasActiveMarker(configuration: ChatConfiguration, keyFingerprint: String) throws -> Bool {
        let binding = try binding(configuration:configuration,keyFingerprint:keyFingerprint)
        // Read-only lookup: unactivated accounts do not create any v2 material.
        return try KeychainStore.data(account:binding.markerAccount) != nil
    }

    /// Production-compatible path/key factory. Calling this factory alone does
    /// not migrate or activate any data. Callers must first verify family scope.
    convenience init(configuration: ChatConfiguration, keyFingerprint: String) throws {
        let binding = try Self.binding(configuration:configuration,keyFingerprint:keyFingerprint)
        let scope=binding.scope, digest=binding.digest
        let marker=binding.markerAccount
        // Validate an existing marker before creating directories or keys.
        if let existing = try KeychainStore.data(account:marker) {
            guard existing.count <= 4096,
                  let decoded=try? JSONDecoder().decode(Marker.self,from:existing),
                  decoded.schema==2, decoded.scopeDigest==Data(SHA256.hash(data:scope)),
                  decoded.sourceFingerprint == nil || decoded.sourceFingerprint?.count == 32
            else { throw Failure.invalidMarker }
        }
        let directory = try FileManager.default.url(for:.applicationSupportDirectory,
            in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("EncryptedChatHistoryV2",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,
            attributes:[.protectionKey:FileProtectionType.complete])
        let info = try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw ChatHistoryError.invalidScope }
        var excluded = directory
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try excluded.setResourceValues(resource)
        let file = directory.appendingPathComponent(digest+".sqlite3")
        let account = "chatHistory.v2.key."+digest
        if try KeychainStore.data(account:account) == nil {
            guard !FileManager.default.fileExists(atPath:file.path),
                  try KeychainStore.data(account:marker) == nil else { throw ChatHistoryError.missingKey }
            let generated = SymmetricKey(size:.bits256).withUnsafeBytes { Data($0) }
            _ = try KeychainStore.insertIfAbsent(generated,account:account)
        }
        guard let key = try KeychainStore.data(account:account), key.count == 32 else { throw ChatHistoryError.missingKey }
        try self.init(file:file,scope:scope,key:key,
            readMarker:{ try KeychainStore.data(account:marker) },
            insertMarker:{ try KeychainStore.insertIfAbsent($0,account:marker) })
    }

    // Isolated tests inject local file, key and add-only marker.
    init(file: URL, scope: Data, key: Data, readMarker: @escaping () throws -> Data?,
         insertMarker: @escaping (Data) throws -> Bool) throws {
        guard file.isFileURL, !scope.isEmpty, scope.count <= 8192,key.count == 32 else {
            throw ChatHistoryError.invalidScope
        }
        self.file=file; self.scope=scope; self.key=key
        scopeDigest=Data(SHA256.hash(data:scope))
        self.readMarker=readMarker; self.insertMarker=insertMarker
    }

    static func capture(_ archive: ChatHistoryArchive) throws -> Source {
        if let source = try archive.loadAuthenticated(ChatPersistentSnapshot.self) {
            return Source(snapshot:source.value,ciphertextFingerprint:source.fingerprint)
        }
        return Source(snapshot:ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:[:]),
            ciphertextFingerprint:nil)
    }

    private func marker() throws -> Marker? {
        guard let data = try readMarker() else { return nil }
        guard data.count <= 4096,
              let marker = try? JSONDecoder().decode(Marker.self,from:data),
              marker.schema == 2, marker.scopeDigest == scopeDigest,
              marker.sourceFingerprint == nil || marker.sourceFingerprint?.count == 32
        else { throw Failure.invalidMarker }
        return marker
    }

    /// Resume a completed import after interruption only if every record
    /// still equals the exact authenticated v1 snapshot. Never recreate an
    /// existing mismatched/corrupt database.
    func prepare(_ archive: ChatHistoryArchive) async throws -> Source {
        guard !busy else { throw Failure.busy }
        busy=true; defer { busy=false }
        guard try marker() == nil else { throw Failure.alreadyActivated }
        let source = try Self.capture(archive)
        let db = try EncryptedChatRecordStore(file:file,scope:scope,keyData:key)
        let records = try await db.records()
        if records.isEmpty {
            try await ChatHistoryRecordMigration.rehearse(source.snapshot,into:db)
        } else {
            guard try ChatHistoryRecordMigration.assemble(records) == source.snapshot else { throw Failure.sourceChanged }
        }
        try Task.checkCancellation()
        guard try marker() == nil, try Self.capture(archive) == source else { throw Failure.sourceChanged }
        return source
    }

    /// Explicit one-way cutover, with source revalidation immediately before
    /// atomic add-only marker publication. Must be called while all legacy
    /// writers are quiesced by the app. No background auto-cutover.
    func activate(prepared: Source, archive: ChatHistoryArchive,
                  authorize: @MainActor () -> Bool) async throws -> ChatRecordReceiveCheckpoint {
        guard !busy else { throw Failure.busy }
        busy=true; defer { busy=false }
        guard try marker() == nil else { throw Failure.alreadyActivated }
        guard FileManager.default.fileExists(atPath:file.path) else { throw Failure.notPrepared }
        let db = try EncryptedChatRecordStore(file:file,scope:scope,keyData:key)
        let records = try await db.records()
        guard try ChatHistoryRecordMigration.assemble(records) == prepared.snapshot else { throw Failure.sourceChanged }
        try Task.checkCancellation()
        guard try Self.capture(archive) == prepared else { throw Failure.sourceChanged }
        let data = try JSONEncoder().encode(Marker(schema:2,scopeDigest:scopeDigest,sourceFingerprint:prepared.ciphertextFingerprint))
        // The caller rechecks live scope immediately before point of no return.
        // No actor suspension between the check and the add-only marker.
        guard authorize() else { throw Failure.authorizationChanged }
        guard try insertMarker(data) else { throw Failure.alreadyActivated }
        return ChatRecordReceiveCheckpoint(store:db)
    }

    /// Nil is valid only before cutover. After cutover a missing or corrupt
    /// database is a hard error; the old v1 archive cannot become active again.
    func openActive() async throws -> ChatRecordReceiveCheckpoint? {
        guard !busy else { throw Failure.busy }
        busy=true; defer { busy=false }
        guard try marker() != nil else { return nil }
        guard FileManager.default.fileExists(atPath:file.path) else { throw Failure.missingCandidate }
        let db=try EncryptedChatRecordStore(file:file,scope:scope,keyData:key)
        let checkpoint=ChatRecordReceiveCheckpoint(store:db)
        _ = try await checkpoint.load()
        try Task.checkCancellation()
        return checkpoint
    }
}
