import Foundation
import SQLite3
import XCTest
@testable import IOSNext

final class EncryptedChatRecordStoreTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Data, Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("store.sqlite3"), Data("fixture-account-device".utf8), Data(repeating: 13, count: 32))
    }

    func testAtomicEncryptedRecordsRollbackAndReopen() async throws {
        let (dir, file, scope, key) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedChatRecordStore(file: file, scope: scope, keyData: key, capacity: 4096)
        let message = EncryptedChatRecordStore.Record(key: .init(kind: .message, id: "fixture-private-id"),
            bytes: Data("synthetic private content".utf8))
        let replay = EncryptedChatRecordStore.Record(key: .init(kind: .replay, id: "fixture-ack"),
            bytes: Data([1, 2, 3]))
        try await store.commit([.put(message), .put(replay)])
        let raw = try Data(contentsOf: file)
        XCTAssertNil(raw.range(of: message.bytes))
        XCTAssertNil(raw.range(of: Data(message.key.id.utf8)))
        let reopened = try EncryptedChatRecordStore(file: file, scope: scope, keyData: key, capacity: 4096)
        let actual = try await reopened.record(message.key)
        XCTAssertEqual(actual, message)
        let oversized = EncryptedChatRecordStore.Record(key: .init(kind: .fragment, id: "too-big"),
            bytes: Data(repeating: 42, count: 5000))
        do {
            try await reopened.commit([.remove(message.key), .put(oversized)])
            XCTFail("Capacity failure must roll back the earlier deletion")
        } catch EncryptedChatRecordStore.Failure.capacity {}
        let afterRollback = try await reopened.record(message.key)
        XCTAssertEqual(afterRollback, message)
        let replayAfter = try await reopened.record(replay.key)
        XCTAssertEqual(replayAfter, replay)
        XCTAssertThrowsError(try EncryptedChatRecordStore(file: file, scope: Data("other-scope".utf8), keyData: key))
        XCTAssertThrowsError(try EncryptedChatRecordStore(file: file, scope: scope, keyData: Data(repeating: 14, count: 32)))
    }

    func testInitialImportCannotOverwriteAndCorruptRowFailsClosed() async throws {
        let (dir, file, scope, key) = try fixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EncryptedChatRecordStore(file: file, scope: scope, keyData: key)
        let record = EncryptedChatRecordStore.Record(key: .init(kind: .fragment, id: "fixture-fragment"),
            bytes: Data(repeating: 5, count: 512))
        try await store.importInitial([record])
        do { try await store.importInitial([]); XCTFail("Repeated import must fail") }
        catch EncryptedChatRecordStore.Failure.alreadyImported {}
        let values = try await store.records()
        XCTAssertEqual(values, [record])
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        let external = try XCTUnwrap(db)
        XCTAssertEqual(sqlite3_exec(external, "UPDATE records SET sealed=zeroblob(length(sealed))", nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(external)
        do { _ = try await store.record(record.key); XCTFail("Corruption must be rejected") }
        catch EncryptedChatRecordStore.Failure.corrupt {}
        do { try await store.commit([.remove(record.key)]); XCTFail("Corruption must not be overwritten") }
        catch EncryptedChatRecordStore.Failure.corrupt {}
    }
}
