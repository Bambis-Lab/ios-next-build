import Foundation
import XCTest
@testable import IOSNext

final class ChatHistoryRecordMigrationTests: XCTestCase {
    @MainActor
    func testV1ArchivePreservedAcrossRecordMigration() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let source=root.appendingPathComponent("legacy.enc"), target=root.appendingPathComponent("candidate.sqlite3")
        let scope=Data("fixture-chat".utf8), key=Data(repeating:9,count:32)
        let date=Date(timeIntervalSinceReferenceDate:123456)
        let text=ChatMessage(id:"text",senderUserID:"alice",recipientUserID:"bob",kind:.text,
            contentType:"text/plain",data:Data("fixture message".utf8),createdAt:date,direction:.outgoing,delivery:.failed)
        let media=ChatMessage(id:"video",senderUserID:"bob",recipientUserID:"alice",kind:.video,
            contentType:"video/mp4",data:Data(repeating:8,count:1024*1024),createdAt:date,direction:.incoming,delivery:.received)
        let part=ChatPersistentPartial(senderUserID:"bob",conversationID:"family",kind:.image,contentType:"image/png",
            createdAt:date,chunkCount:3,chunks:[0:Data([1,2]),2:Data([3,4])],lastUpdated:date)
        let original=ChatPersistentSnapshot(version:1,messages:[text,media],partials:["bob|device|partial":part],seen:["fixture-ack":date])
        let archive=try ChatHistoryArchive(file:source,scope:scope,keyData:key)
        try archive.save(original)
        let originalBytes=try Data(contentsOf:source)
        let loaded=try XCTUnwrap(archive.load(ChatPersistentSnapshot.self))
        let store=try EncryptedChatRecordStore(file:target,scope:scope,keyData:key)
        try await ChatHistoryRecordMigration.rehearse(loaded,into:store)
        let reopened=try EncryptedChatRecordStore(file:target,scope:scope,keyData:key)
        let records=try await reopened.records()
        XCTAssertEqual(try ChatHistoryRecordMigration.assemble(records),original)
        XCTAssertEqual(try Data(contentsOf:source),originalBytes)
        XCTAssertThrowsError(try ChatHistoryRecordMigration.assemble(records.filter { $0.key.kind != .fragment }))
        XCTAssertThrowsError(try ChatHistoryRecordMigration.assemble(records+[records[0]]))
    }
}
