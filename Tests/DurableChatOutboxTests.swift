import Foundation
import XCTest
@testable import IOSNext

final class DurableChatOutboxTests:XCTestCase {
    @MainActor
    func testPersistBeforeSendAmbiguousReceiptAndScopeBinding() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("outbox.enc"),aad=Data("fixture-chat-outbox".utf8),key=Data(repeating:41,count:32)
        let keys=ChatDeviceKeys(agreement:.init(),signing:.init()),peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=keys.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),peer=peerKeys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),user:local.userID,device:local.deviceID,keyFingerprint:keys.safetyNumber)
        func open() throws -> DurableChatOutbox {
            try DurableChatOutbox(scope:scope,local:local,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
        }
        let group=UUID().uuidString.lowercased(),stamp=ISO8601DateFormatter().string(from:Date())
        let entries=try (0..<2).map {i in
            try keys.encrypt(Data("synthetic message \(i)".utf8),kind:.text,contentType:"text/plain",groupID:group,
                chunkIndex:i,chunkCount:2,sender:local,recipient:peer,createdAt:stamp)
        }
        try open().stage(groupID:group,recipients:[peer],envelopes:entries)
        XCTAssertNil(try Data(contentsOf:file).range(of:Data("synthetic message".utf8)))
        XCTAssertThrowsError(try open().beginNext(currentRecipients:[]))
        XCTAssertThrowsError(try open().beginNext(currentRecipients:[peer],now:Date().addingTimeInterval(100)))
        let first=try XCTUnwrap(open().beginNext(currentRecipients:[peer]))
        XCTAssertEqual(first,entries[0])
        XCTAssertEqual(try open().pending()?.entries.first?.phase,.uncertain)
        XCTAssertThrowsError(try open().beginNext(currentRecipients:[peer]))
        XCTAssertThrowsError(try open().confirm(first,receipt:.init(id:entries[1].id,state:"queued_persistent",expiresInSeconds:120)))
        XCTAssertThrowsError(try open().finishAfterHistoryCommit(groupID:group))
        try open().confirm(first,receipt:.init(id:first.id,state:"queued_persistent",expiresInSeconds:120))
        let second=try XCTUnwrap(open().beginNext(currentRecipients:[peer]))
        XCTAssertEqual(second,entries[1])
        try open().confirm(second,receipt:.init(id:second.id,state:"queued_persistent",expiresInSeconds:120))
        XCTAssertNil(try open().beginNext(currentRecipients:[peer]))
        try open().finishAfterHistoryCommit(groupID:group)
        XCTAssertNil(try open().pending())
        XCTAssertThrowsError(try DurableChatOutbox(scope:scope,local:peer,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key)))
    }
}
