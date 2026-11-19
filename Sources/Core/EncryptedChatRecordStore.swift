import Foundation
import CryptoKit
import SQLite3

/// Phase D storage primitive. Isolated until migration and ChatModel ACK
/// integration are accepted. SQLite contains only opaque IDs and ciphertext.
/// Actor isolation keeps encoding, crypto and database I/O off MainActor.
actor EncryptedChatRecordStore {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case message, fragment, assembly, replay, outbox, delivery, migration
    }
    struct Key: Codable, Hashable, Sendable {
        let kind: Kind
        let id: String
    }
    struct Record: Codable, Equatable, Sendable {
        let key: Key
        let bytes: Data
    }
    enum Change: Sendable {
        case put(Record)
        case remove(Key)
    }
    enum Failure: Error, Equatable {
        case invalidScope, unsafeFile, invalidSchema, corrupt, capacity, database, alreadyImported, staleCheckpoint
    }
    private struct Entry: Codable, Equatable {
        let digest: Data
        let bytes: Int
    }
    private struct Manifest: Codable {
        let version: Int
        var entries: [String: Entry]
        var imported: Bool
    }

    private final class Database {
        let handle: OpaquePointer
        init(_ path: String, create: Bool) throws {
            var pointer: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
            guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK,
                  let p = pointer else {
                if let pointer { sqlite3_close_v2(pointer) }
                throw Failure.database
            }
            handle = p
            sqlite3_busy_timeout(p, 2000)
        }
        deinit { sqlite3_close_v2(handle) }

        func exec(_ sql: String) throws {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.database }
        }
        func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else { throw Failure.database }
            defer { sqlite3_finalize(stmt) }
            return try body(stmt)
        }
        func transaction<T>(_ operation: () throws -> T) throws -> T {
            try exec("BEGIN IMMEDIATE")
            do {
                let result = try operation()
                try exec("COMMIT")
                return result
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let maxRecords = 30_000
    private static let maxRecord = 48 * 1024 * 1024
    private static let maxManifest = 8 * 1024 * 1024
    private static let schemaVersion = 2
    private let db: Database
    private let key: SymmetricKey
    private let indexKey: SymmetricKey
    private let scope: Data
    private let capacity: Int

    init(file: URL, scope: Data, keyData: Data, capacity: Int = 384 * 1024 * 1024) throws {
        guard file.isFileURL, !scope.isEmpty, scope.count <= 8192, keyData.count == 32,
              capacity > 0, capacity <= 384 * 1024 * 1024 else { throw Failure.invalidScope }
        let manager = FileManager.default
        let parent = try file.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parent.isDirectory == true, parent.isSymbolicLink != true else { throw Failure.unsafeFile }
        let existing = manager.fileExists(atPath: file.path)
        if let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw Failure.unsafeFile }
        }
        for suffix in ["-wal", "-shm", "-journal"] {
            let side = URL(fileURLWithPath: file.path + suffix)
            if let info = try? side.resourceValues(forKeys: [.isSymbolicLinkKey]), info.isSymbolicLink == true {
                throw Failure.unsafeFile
            }
        }
        let master = SymmetricKey(data: keyData)
        let cipher = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: scope,
            info: Data("iosnext-record-store-v2-encryption".utf8), outputByteCount: 32)
        let index = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: scope,
            info: Data("iosnext-record-store-v2-index".utf8), outputByteCount: 32)
        let database = try Database(file.path, create: !existing)
        try database.exec("PRAGMA trusted_schema=OFF")
        try database.exec("PRAGMA journal_mode=DELETE")
        try database.exec("PRAGMA synchronous=FULL")
        try database.exec("PRAGMA secure_delete=ON")
        if !existing {
            try database.transaction {
                try database.exec("CREATE TABLE records(id TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)")
                try database.exec("CREATE TABLE state(id INTEGER PRIMARY KEY CHECK(id=1), sealed BLOB NOT NULL)")
                try database.exec("PRAGMA user_version=2")
                let manifest = Manifest(version: Self.schemaVersion, entries: [:], imported: false)
                let sealed = try Self.seal(JSONEncoder().encode(manifest), key: cipher, scope: scope, label: "manifest")
                try Self.writeManifest(database, sealed)
            }
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        }
        try Self.checkSchema(database)
        let manifest = try Self.readManifest(database, key: cipher, scope: scope, capacity: capacity)
        try Self.checkInventory(database, manifest)
        self.db = database
        self.key = cipher
        self.indexKey = index
        self.scope = scope
        self.capacity = capacity
    }

    private static func checkSchema(_ db: Database) throws {
        let version = try db.statement("PRAGMA user_version") { stmt -> Int32 in
            guard sqlite3_step(stmt) == SQLITE_ROW else { throw Failure.database }
            return sqlite3_column_int(stmt, 0)
        }
        guard version == schemaVersion else { throw Failure.invalidSchema }
        let tables = try db.statement("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name") { stmt -> [String] in
            var names: [String] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { return names }
                guard rc == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { throw Failure.invalidSchema }
                names.append(String(cString: raw))
            }
        }
        guard tables == ["records", "state"] else { throw Failure.invalidSchema }
    }

    private static func aad(_ scope: Data, _ label: String) -> Data {
        Data("IOSNEXT-CHAT-RECORDS-2".utf8) + Data([0]) + scope + Data([0]) + Data(label.utf8)
    }
    private static func seal(_ data: Data, key: SymmetricKey, scope: Data, label: String) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: aad(scope, label)).combined
        else { throw Failure.corrupt }
        return combined
    }
    private static func open(_ data: Data, key: SymmetricKey, scope: Data, label: String) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad(scope, label)) }
        catch { throw Failure.corrupt }
    }
    private static func digest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }

    // Avoid Base64 encoding a large payload a second time.
    private static func pack(_ value: Record) throws -> Data {
        let header = try JSONEncoder().encode(value.key)
        guard (1...4096).contains(header.count),
              value.bytes.count <= maxRecord - header.count - 32 else { throw Failure.capacity }
        var length = UInt32(header.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + header + value.bytes
    }
    private static func unpack(_ data: Data) throws -> Record {
        guard data.count >= 5 else { throw Failure.corrupt }
        let length = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (1...4096).contains(length), length <= data.count - 4 else { throw Failure.corrupt }
        let key = try JSONDecoder().decode(Key.self, from: Data(data.dropFirst(4).prefix(length)))
        return Record(key: key, bytes: Data(data.dropFirst(4 + length)))
    }

    private func opaqueID(_ value: Key) throws -> String {
        guard (1...512).contains(value.id.utf8.count) else { throw Failure.invalidScope }
        let bytes = Data(value.kind.rawValue.utf8) + Data([0]) + Data(value.id.utf8)
        return HMAC<SHA256>.authenticationCode(for: bytes, using: indexKey).map { String(format: "%02x", $0) }.joined()
    }
    private static func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(stmt, index, value, -1, transient) == SQLITE_OK else { throw Failure.database }
    }
    private static func bind(_ value: Data, to stmt: OpaquePointer, at index: Int32) throws {
        let rc = value.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(raw.count), transient)
        }
        guard rc == SQLITE_OK else { throw Failure.database }
    }
    private static func blob(_ stmt: OpaquePointer, at index: Int32, limit: Int) throws -> Data {
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count >= 28, count <= limit, let bytes = sqlite3_column_blob(stmt, index)
        else { throw Failure.corrupt }
        return Data(bytes: bytes, count: count)
    }
    private static func done(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw Failure.database }
    }

    private static func writeManifest(_ db: Database, _ sealed: Data) throws {
        guard sealed.count <= maxManifest else { throw Failure.capacity }
        try db.statement("INSERT OR REPLACE INTO state(id,sealed) VALUES(1,?)") { stmt in
            try bind(sealed, to: stmt, at: 1)
            try done(stmt)
        }
    }
    private static func readManifest(_ db: Database, key: SymmetricKey, scope: Data, capacity: Int) throws -> Manifest {
        let sealed = try db.statement("SELECT id,sealed FROM state") { stmt -> Data in
            guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) == 1 else { throw Failure.corrupt }
            let data = try blob(stmt, at: 1, limit: maxManifest)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw Failure.corrupt }
            return data
        }
        let plain = try open(sealed, key: key, scope: scope, label: "manifest")
        let manifest = try JSONDecoder().decode(Manifest.self, from: plain)
        guard manifest.version == schemaVersion, manifest.entries.count <= maxRecords else { throw Failure.corrupt }
        var total = 0
        for (id, entry) in manifest.entries {
            guard id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  entry.digest.count == 32, (28...maxRecord).contains(entry.bytes),
                  entry.bytes <= capacity - total else { throw Failure.corrupt }
            total += entry.bytes
        }
        return manifest
    }
    private static func checkInventory(_ db: Database, _ manifest: Manifest) throws {
        let inventory = try db.statement("SELECT count(*),coalesce(sum(length(sealed)),0) FROM records") { stmt -> (Int, Int) in
            guard sqlite3_step(stmt) == SQLITE_ROW else { throw Failure.database }
            return (Int(sqlite3_column_int64(stmt, 0)), Int(sqlite3_column_int64(stmt, 1)))
        }
        guard inventory.0 == manifest.entries.count,
              inventory.1 == manifest.entries.values.reduce(0, { $0 + $1.bytes }) else { throw Failure.corrupt }
    }

    private func read(_ id: String, entry: Entry?) throws -> Record? {
        try db.statement("SELECT sealed FROM records WHERE id=?") { stmt -> Record? in
            try Self.bind(id, to: stmt, at: 1)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                guard entry == nil else { throw Failure.corrupt }
                return nil
            }
            guard rc == SQLITE_ROW, let entry else { throw Failure.corrupt }
            let sealed = try Self.blob(stmt, at: 0, limit: Self.maxRecord)
            guard sealed.count == entry.bytes, Self.digest(sealed) == entry.digest else { throw Failure.corrupt }
            let plain = try Self.open(sealed, key: key, scope: scope, label: "record:" + id)
            let value = try Self.unpack(plain)
            guard try opaqueID(value.key) == id else { throw Failure.corrupt }
            return value
        }
    }

    func record(_ key: Key) throws -> Record? {
        try db.transaction {
            let manifest = try Self.readManifest(db, key: self.key, scope: scope, capacity: capacity)
            try Self.checkInventory(db, manifest)
            let id = try opaqueID(key)
            return try read(id, entry: manifest.entries[id])
        }
    }

    func records() throws -> [Record] {
        try db.transaction {
            let manifest = try Self.readManifest(db, key: key, scope: scope, capacity: capacity)
            try Self.checkInventory(db, manifest)
            return try manifest.entries.keys.sorted().map { id in
                guard let record = try read(id, entry: manifest.entries[id]) else { throw Failure.corrupt }
                return record
            }
        }
    }

    /// All changes, the inventory and any replay/delivery record commit as
    /// one transaction. The caller may ACK only after this method returns.
    func commit(_ changes: [Change]) throws {
        try apply(changes, initialImport: false)
    }

    /// One-time migration into an empty candidate database. The source
    /// archive is owned by the caller and never removed by the store.
    func importInitial(_ records: [Record]) throws {
        try apply(records.map { .put($0) }, initialImport: true)
    }

    /// Atomic compare-and-swap. A stale receiver cannot overwrite a newer
    /// checkpoint, even if a second SQLite handle opened the same scope.
    func commitCheckpoint(expected: [Record], changes: [Change]) throws {
        try apply(changes, initialImport: false, expected: expected)
    }

    private func apply(_ changes: [Change], initialImport: Bool, expected: [Record]? = nil) throws {
        guard changes.count <= Self.maxRecords else { throw Failure.capacity }
        try db.transaction {
            try Task.checkCancellation()
            var manifest = try Self.readManifest(db, key: key, scope: scope, capacity: capacity)
            try Self.checkInventory(db, manifest)
            if initialImport {
                guard !manifest.imported, manifest.entries.isEmpty else { throw Failure.alreadyImported }
            }
            if let expected {
                guard manifest.imported, expected.count == manifest.entries.count,
                      expected.count <= Self.maxRecords else { throw Failure.staleCheckpoint }
                var checked = Set<String>()
                for record in expected {
                    try Task.checkCancellation()
                    let id = try opaqueID(record.key)
                    guard checked.insert(id).inserted,
                          let entry = manifest.entries[id],
                          try read(id, entry: entry) == record else { throw Failure.staleCheckpoint }
                }
            }
            var touched = Set<String>()
            var total = manifest.entries.values.reduce(0, { $0 + $1.bytes })
            for change in changes {
                try Task.checkCancellation()
                let recordKey: Key
                switch change { case .put(let r): recordKey = r.key; case .remove(let k): recordKey = k }
                let id = try opaqueID(recordKey)
                guard touched.insert(id).inserted else { throw Failure.invalidScope }
                let existing = manifest.entries[id]
                _ = try read(id, entry: existing) // never overwrite a corrupted row
                total -= existing?.bytes ?? 0
                switch change {
                case .put(let value):
                    guard value.bytes.count <= Self.maxRecord else { throw Failure.capacity }
                    let plain = try Self.pack(value)
                    guard plain.count <= Self.maxRecord - 28 else { throw Failure.capacity }
                    let sealed = try Self.seal(plain, key: key, scope: scope, label: "record:" + id)
                    guard sealed.count <= capacity - total else { throw Failure.capacity }
                    total += sealed.count
                    manifest.entries[id] = Entry(digest: Self.digest(sealed), bytes: sealed.count)
                    guard manifest.entries.count <= Self.maxRecords else { throw Failure.capacity }
                    try db.statement("INSERT OR REPLACE INTO records(id,sealed) VALUES(?,?)") { stmt in
                        try Self.bind(id, to: stmt, at: 1)
                        try Self.bind(sealed, to: stmt, at: 2)
                        try Self.done(stmt)
                    }
                case .remove:
                    manifest.entries.removeValue(forKey: id)
                    try db.statement("DELETE FROM records WHERE id=?") { stmt in
                        try Self.bind(id, to: stmt, at: 1)
                        try Self.done(stmt)
                    }
                }
            }
            if initialImport { manifest.imported = true }
            try Self.checkInventory(db, manifest)
            try Self.writeManifest(db, Self.seal(JSONEncoder().encode(manifest), key: key, scope: scope, label: "manifest"))
            try Task.checkCancellation()
        }
    }
}
