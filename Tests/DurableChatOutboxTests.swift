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
        let nextGroup=UUID().uuidString.lowercased()
        let next=try keys.encrypt(Data("second fixture".utf8),kind:.text,contentType:"text/plain",groupID:nextGroup,
            chunkIndex:0,chunkCount:1,sender:local,recipient:peer,createdAt:stamp)
        try open().stage(groupID:nextGroup,recipients:[peer],envelopes:[next])
        XCTAssertEqual(try open().beginNext(currentRecipients:[peer]),next)
        XCTAssertThrowsError(try open().closeExpiredAfterHistoryCommit(groupID:nextGroup))
        let future=Date().addingTimeInterval(100)
        XCTAssertEqual(try open().expiredPending(now:future)?.groupID,nextGroup)
        XCTAssertThrowsError(try open().closeExpiredAfterHistoryCommit(groupID:group,now:future))
        try open().closeExpiredAfterHistoryCommit(groupID:nextGroup,now:future)
        XCTAssertNil(try open().pending())
        let closed=try XCTUnwrap(open().expiredRecords().first)
        XCTAssertEqual(closed.groupID,nextGroup)
        XCTAssertEqual(closed.entries.first?.phase,.uncertain)
        XCTAssertEqual(closed.entries.first?.digest,try ChatSendReceiptV1.digest(next))
        XCTAssertThrowsError(try open().stage(groupID:nextGroup,recipients:[peer],envelopes:[next]))
        try open().stage(groupID:group,recipients:[peer],envelopes:entries)
        XCTAssertEqual(try open().pending()?.groupID,group)
        XCTAssertEqual(try open().expiredRecords(),[closed])
    }

    @MainActor
    func testV1MigrationFIFOAndExpiredHeadPreserveTail() throws {
        struct LegacySnapshot:Codable {
            let version:Int
            let pending:DurableChatOutbox.Pending?
            let expired:[DurableChatOutbox.ExpiredRecord]?
        }
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("outbox.enc"),aad=Data("fixture-queue".utf8),key=Data(repeating:42,count:32)
        let keys=ChatDeviceKeys(agreement:.init(),signing:.init()),peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=keys.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),peer=peerKeys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),user:local.userID,device:local.deviceID,keyFingerprint:keys.safetyNumber)
        func archive() throws -> ChatHistoryArchive {try ChatHistoryArchive(file:file,scope:aad,keyData:key)}
        func open() throws -> DurableChatOutbox {try DurableChatOutbox(scope:scope,local:local,archive:archive())}
        let now=Date(),stamp=ISO8601DateFormatter().string(from:now)
        func envelope() throws -> ChatEnvelope {
            try keys.encrypt(Data("queue fixture".utf8),kind:.text,contentType:"text/plain",groupID:UUID().uuidString.lowercased(),
                chunkIndex:0,chunkCount:1,sender:local,recipient:peer,createdAt:stamp)
        }
        let head=try envelope(),tail=try envelope(),last=try envelope()
        let legacy=DurableChatOutbox.Pending(scope:scope,groupID:head.groupID,recipients:[peer],
            entries:[.init(envelope:head,phase:.uncertain)])
        try archive().save(LegacySnapshot(version:1,pending:legacy,expired:nil))
        XCTAssertEqual(try open().pendingGroups().map(\.groupID),[head.groupID])
        try open().enqueue(groupID:tail.groupID,recipients:[peer],envelopes:[tail])
        try open().enqueue(groupID:tail.groupID,recipients:[peer],envelopes:[tail])
        try open().enqueue(groupID:last.groupID,recipients:[peer],envelopes:[last])
        XCTAssertEqual(try open().pendingGroups().map(\.groupID),[head.groupID,tail.groupID,last.groupID])
        XCTAssertThrowsError(try open().stage(groupID:last.groupID,recipients:[peer],envelopes:[last]))
        XCTAssertThrowsError(try open().beginNext(currentRecipients:[peer],now:now))
        XCTAssertEqual(try open().beginNext(currentRecipients:[peer],allowIdempotentReplay:true,now:now),head)
        let later=now.addingTimeInterval(100)
        XCTAssertThrowsError(try open().closeExpiredAfterHistoryCommit(groupID:tail.groupID,now:later))
        try open().closeExpiredAfterHistoryCommit(groupID:head.groupID,now:later)
        XCTAssertEqual(try open().pendingGroups().map(\.groupID),[tail.groupID,last.groupID])
        XCTAssertEqual(try open().expiredRecords().first?.groupID,head.groupID)
        XCTAssertThrowsError(try open().enqueue(groupID:head.groupID,recipients:[peer],envelopes:[head]))
        // Use the original valid timestamp to test transport ordering independently of expiry.
        let next=try XCTUnwrap(open().beginNext(currentRecipients:[peer],now:now))
        XCTAssertEqual(next,tail)
        let receipt=ChatSendReceiptV1(id:next.id,state:"queued_persistent",expiresInSeconds:120,receiptVersion:1,
            envelopeSHA256:try ChatSendReceiptV1.digest(next),replayed:false)
        try open().confirm(next,receipt:receipt)
        try open().finishAfterHistoryCommit(groupID:tail.groupID)
        XCTAssertEqual(try open().pendingGroups().map(\.groupID),[last.groupID])
        XCTAssertEqual(try open().pending()?.entries.first?.phase,.ready)
    }

    @MainActor
    func testQueueCapacityRejectsWithoutChangingPersistedGroups() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("queue.enc"),aad=Data("capacity-fixture".utf8),key=Data(repeating:43,count:32)
        let keys=ChatDeviceKeys(agreement:.init(),signing:.init()),peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=keys.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),peer=peerKeys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),user:local.userID,device:local.deviceID,keyFingerprint:keys.safetyNumber)
        func open() throws -> DurableChatOutbox {
            try DurableChatOutbox(scope:scope,local:local,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
        }
        let stamp=ISO8601DateFormatter().string(from:Date())
        func append() throws {
            let group=UUID().uuidString.lowercased()
            let e=try keys.encrypt(Data("bounded queue".utf8),kind:.text,contentType:"text/plain",groupID:group,
                chunkIndex:0,chunkCount:1,sender:local,recipient:peer,createdAt:stamp)
            try open().enqueue(groupID:group,recipients:[peer],envelopes:[e])
        }
        for _ in 0..<DurableChatOutbox.maximumPendingGroups {try append()}
        let before=try open().pendingGroups()
        XCTAssertThrowsError(try append())
        XCTAssertEqual(try open().pendingGroups(),before)
        XCTAssertEqual(before.count,DurableChatOutbox.maximumPendingGroups)
    }
}
