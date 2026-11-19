import Foundation
import XCTest
@testable import IOSNext

final class DurableChatOutboxTests:XCTestCase {
    func testReceiptContractMustBeExplicitAndPersistent() throws {
        let decoder=JSONDecoder()
        func contract(_ value:String) throws -> ChatDeliveryContract {
            try decoder.decode(ChatDeliveryContract.self,from:Data(value.utf8))
        }
        XCTAssertFalse(try contract(#"{"mode":"ack_v1","max_batch":64,"ttl_seconds":120,"persistent":true}"#).supportsIdempotentSender)
        XCTAssertFalse(try contract(#"{"mode":"ack_v1","max_batch":64,"ttl_seconds":120,"persistent":false,"send_receipt_version":1,"send_max_age_seconds":90}"#).supportsIdempotentSender)
        XCTAssertTrue(try contract(#"{"mode":"ack_v1","max_batch":64,"ttl_seconds":120,"persistent":true,"send_receipt_version":1,"send_max_age_seconds":90}"#).supportsIdempotentSender)
    }

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
        let replay=try XCTUnwrap(open().beginNext(currentRecipients:[peer],allowIdempotentReplay:true))
        XCTAssertEqual(replay,first)
        XCTAssertThrowsError(try open().beginNext(currentRecipients:[peer],allowIdempotentReplay:true,now:Date().addingTimeInterval(100)))
        func receipt(_ envelope:ChatEnvelope,replayed:Bool=false) throws -> ChatSendReceiptV1 {
            .init(id:envelope.id,state:"queued_persistent",expiresInSeconds:120,receiptVersion:1,
                  envelopeSHA256:try ChatSendReceiptV1.digest(envelope),replayed:replayed)
        }
        XCTAssertThrowsError(try open().confirm(first,receipt:receipt(entries[1])))
        XCTAssertThrowsError(try open().confirm(first,receipt:.init(id:first.id,state:"queued_persistent",
            expiresInSeconds:120,receiptVersion:1,envelopeSHA256:String(repeating:"0",count:64),replayed:true)))
        XCTAssertThrowsError(try open().finishAfterHistoryCommit(groupID:group))
        try open().confirm(first,receipt:receipt(first,replayed:true))
        let second=try XCTUnwrap(open().beginNext(currentRecipients:[peer]))
        XCTAssertEqual(second,entries[1])
        try open().confirm(second,receipt:receipt(second))
        XCTAssertNil(try open().beginNext(currentRecipients:[peer]))
        try open().finishAfterHistoryCommit(groupID:group)
        XCTAssertNil(try open().pending())
        XCTAssertThrowsError(try DurableChatOutbox(scope:scope,local:peer,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key)))
    }
}
