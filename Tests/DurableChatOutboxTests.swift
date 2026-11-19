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

    @MainActor
    func testReadyTimestampRenewalPreservesCiphertextAndIDsAndRejectsUncertain() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("renew.enc"),aad=Data("renew-fixture".utf8),key=Data(repeating:44,count:32)
        let keys=ChatDeviceKeys(agreement:.init(),signing:.init()),peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=keys.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),peer=peerKeys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),user:local.userID,device:local.deviceID,keyFingerprint:keys.safetyNumber)
        func open() throws -> DurableChatOutbox {
            try DurableChatOutbox(scope:scope,local:local,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
        }
        let now=Date(),group=UUID().uuidString.lowercased(),plain=Data("synthetic ready renewal".utf8)
        let original=try keys.encrypt(plain,kind:.text,contentType:"text/plain",groupID:group,
            chunkIndex:0,chunkCount:1,sender:local,recipient:peer,createdAt:ISO8601DateFormatter().string(from:now.addingTimeInterval(-100)))
        try open().enqueue(groupID:group,recipients:[peer],envelopes:[original])
        XCTAssertThrowsError(try open().refreshReadyHead(groupID:group,currentRecipients:[],keys:keys,now:now))
        XCTAssertThrowsError(try open().refreshReadyHead(groupID:group,currentRecipients:[peer],keys:peerKeys,now:now))
        XCTAssertEqual(try open().pending()?.entries.first?.envelope,original)
        try open().refreshReadyHead(groupID:group,currentRecipients:[peer],keys:keys,now:now)
        let renewed=try XCTUnwrap(open().pending()?.entries.first?.envelope)
        XCTAssertEqual(renewed.id,original.id)
        XCTAssertEqual(renewed.groupID,original.groupID)
        XCTAssertEqual(renewed.ciphertext,original.ciphertext)
        XCTAssertEqual(renewed.ephemeralPublicKey,original.ephemeralPublicKey)
        XCTAssertNotEqual(renewed.createdAt,original.createdAt)
        XCTAssertNotEqual(renewed.signature,original.signature)
        XCTAssertEqual(try peerKeys.decrypt(renewed,sender:local),plain)
        XCTAssertEqual(try open().beginNext(currentRecipients:[peer],now:now),renewed)
        XCTAssertThrowsError(try open().refreshReadyHead(groupID:group,currentRecipients:[peer],keys:keys,now:now.addingTimeInterval(100)))
        XCTAssertEqual(try open().pending()?.entries.first?.envelope,renewed)
        XCTAssertEqual(try open().pending()?.entries.first?.phase,.uncertain)
    }

    /// Measures scoped archive/outbox primitives, not full UI submission or
    /// physical flash durability. All data and keys are disposable fixtures.
    @MainActor
    func testTextOutboxP95AndEightGroupRecovery() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let localKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=localKeys.publicIdentity(userID:"fixture-a",deviceID:"ios-a")
        let peer=peerKeys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),
            user:local.userID,device:local.deviceID,keyFingerprint:localKeys.safetyNumber)
        let aad=Data("fixture-performance".utf8), key=Data(repeating:42,count:32)
        let clock=ContinuousClock()
        func milliseconds(_ start:ContinuousClock.Instant)->Double {
            let elapsed=start.duration(to:clock.now).components
            return Double(elapsed.seconds)*1000+Double(elapsed.attoseconds)/1e15
        }
        func p95(_ values:[Double])->Double {
            let sorted=values.sorted()
            return sorted[max(0,Int(ceil(Double(sorted.count)*0.95))-1)]
        }
        var saveSamples:[Double]=[],reopenSamples:[Double]=[]
        // 20 independent archives, 160 samples including a full FIFO.
        // Each archive remains intact through all recovery samples.
        for iteration in 0..<20 {
            let file=root.appendingPathComponent("outbox-\(iteration).enc")
            func open() throws -> DurableChatOutbox {
                try DurableChatOutbox(scope:scope,local:local,
                    archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
            }
            let journal=try open()
            var expected:[ChatEnvelope]=[]
            for _ in 0..<8 {
                let group=UUID().uuidString.lowercased()
                let stamp=ISO8601DateFormatter().string(from:Date())
                let started=clock.now
                let envelope=try localKeys.encrypt(Data(repeating:65,count:512),kind:.text,
                    contentType:"text/plain",groupID:group,chunkIndex:0,chunkCount:1,
                    sender:local,recipient:peer,createdAt:stamp)
                try journal.enqueue(groupID:group,recipients:[peer],envelopes:[envelope])
                saveSamples.append(milliseconds(started))
                expected.append(envelope)
            }
            let started=clock.now
            let recovered=try open().pendingGroups()
            reopenSamples.append(milliseconds(started))
            XCTAssertEqual(recovered.count,8)
            XCTAssertEqual(recovered.flatMap(\.entries).map(\.envelope),expected)
            XCTAssertTrue(recovered.flatMap(\.entries).allSatisfy{$0.phase == .ready})
        }
        let save=p95(saveSamples),restore=p95(reopenSamples)
        print("V64_OUTBOX_PERF archive_scope=synthetic text_samples=\(saveSamples.count) restore_samples=\(reopenSamples.count) text_p95_ms=\(save) restore_p95_ms=\(restore)")
        XCTAssertLessThanOrEqual(save,150)
        XCTAssertLessThanOrEqual(restore,1000)
    }
}
