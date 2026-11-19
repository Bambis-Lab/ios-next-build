import Foundation
import XCTest
@testable import IOSNext

final class ChatRecordReceiveCheckpointTests: XCTestCase {
    @MainActor
    func testCommitPreservesFragmentsAndReplayBeforeReceiptAndRejectsStaleWriter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let source = root.appendingPathComponent("legacy.enc"), target = root.appendingPathComponent("candidate.sqlite3")
        let scope = Data("fixture-ack-transaction".utf8), key = Data(repeating:71,count:32)
        let date = Date(timeIntervalSinceReferenceDate:1234)
        let initial = ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:[:])
        let old = try ChatHistoryArchive(file:source,scope:scope,keyData:key)
        try old.save(initial)
        let bytes = try Data(contentsOf:source)
        let store = try EncryptedChatRecordStore(file:target,scope:scope,keyData:key)
        try await ChatHistoryRecordMigration.rehearse(initial,into:store)
        let checkpoint = ChatRecordReceiveCheckpoint(store:store)
        let other = ChatRecordReceiveCheckpoint(store:try EncryptedChatRecordStore(file:target,scope:scope,keyData:key))
        let fragment = ChatPersistentPartial(senderUserID:"bob",conversationID:nil,kind:.image,contentType:"image/png",
            createdAt:date,chunkCount:2,chunks:[0:Data([1,2,3])],lastUpdated:date)
        let next = ChatPersistentSnapshot(version:1,messages:[],partials:["partial-id":fragment],seen:["envelope-1":date])
        do {
            _ = try await checkpoint.commit(previous:initial,next:next,verifiedEnvelopeIDs:["missing"])
            XCTFail("unknown replay ID was accepted")
        } catch {}
        let before = try await other.load()
        XCTAssertEqual(before,initial)
        let receipt = try await checkpoint.commit(previous:initial,next:next,verifiedEnvelopeIDs:["envelope-1"])
        XCTAssertEqual(receipt.envelopeIDs,["envelope-1"])
        let reopened = try await other.load()
        XCTAssertEqual(reopened,next)
        do {
            _ = try await other.commit(previous:initial,next:next,verifiedEnvelopeIDs:["envelope-1"])
            XCTFail("stale writer was accepted")
        } catch let failure as EncryptedChatRecordStore.Failure {
            XCTAssertEqual(failure,.staleCheckpoint)
        }
        let duplicate = try await other.commit(previous:next,next:next,verifiedEnvelopeIDs:["envelope-1"])
        XCTAssertEqual(duplicate,receipt)
        XCTAssertEqual(try Data(contentsOf:source),bytes)
    }

    @MainActor
    func testRecipientClaimCheckpointAndSignatureSurviveRestart() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("proof.sqlite3"),legacy=root.appendingPathComponent("proof.enc")
        let scope=Data("recipient-claim-fixture".utf8),key=Data(repeating:64,count:32)
        let sender=ChatDeviceKeys(agreement:.init(),signing:.init())
        let receiver=ChatDeviceKeys(agreement:.init(),signing:.init())
        let a=sender.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),b=receiver.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let config=ChatConfiguration(baseURL:try XCTUnwrap(URL(string:"https://example.invalid")),
            token:"synthetic",userID:b.userID,deviceID:b.deviceID)
        let now=Date()
        let e=try sender.encrypt(Data("fragment".utf8),kind:.text,contentType:"text/plain",groupID:"fixture-group",
            chunkIndex:0,chunkCount:2,sender:a,recipient:b,createdAt:ISO8601DateFormatter().string(from:now))
        let claim=ChatPendingRecipientProof(proof:try ChatRecipientProofV1.unsignedClaim(e),
            keyFingerprint:receiver.safetyNumber,committedAt:now)
        let initial=ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:[:])
        let next=ChatPersistentSnapshot(version:1,messages:[],partials:["fixture-partial":
            ChatPersistentPartial(senderUserID:a.userID,conversationID:nil,kind:.text,contentType:"text/plain",
               createdAt:now,chunkCount:2,chunks:[0:Data("fragment".utf8)],lastUpdated:now)],
            seen:[e.id:now],pendingRecipientProofs:[e.id:claim])
        let archive=try ChatHistoryArchive(file:legacy,scope:scope,keyData:key)
        try archive.save(next)
        XCTAssertEqual(try archive.load(ChatPersistentSnapshot.self),next)
        let store=try EncryptedChatRecordStore(file:file,scope:scope,keyData:key)
        try await ChatHistoryRecordMigration.rehearse(initial,into:store)
        let checkpoint=ChatRecordReceiveCheckpoint(store:store)
        _ = try await checkpoint.commit(previous:initial,next:next,verifiedEnvelopeIDs:[e.id])
        let reopened=ChatRecordReceiveCheckpoint(store:try EncryptedChatRecordStore(file:file,scope:scope,keyData:key))
        let restored=try await reopened.load()
        XCTAssertEqual(restored,next)
        let pending=try XCTUnwrap(restored.pendingRecipientProofs?[e.id])
        XCTAssertTrue(pending.proof.signature.isEmpty)
        XCTAssertThrowsError(try pending.signed(using:sender,configuration:config))
        let signed=try pending.signed(using:receiver,configuration:config)
        var signedSnapshot=restored
        signedSnapshot.pendingRecipientProofs=[e.id:signed]
        _ = try await reopened.commit(previous:restored,next:signedSnapshot,verifiedEnvelopeIDs:[])
        let again=try await checkpoint.load()
        let persisted=try XCTUnwrap(again.pendingRecipientProofs?[e.id])
        XCTAssertEqual(try persisted.signed(using:receiver,configuration:config),signed)
        try persisted.proof.verify(expectedID:e.id,expectedDigest:ChatSendReceiptV1.digest(e),
            senderUser:a.userID,senderDevice:a.deviceID,recipient:b)
    }

    @MainActor
    func testProofBatchCrashAfterPartialRemoteSuccessPreservesExactSignatures() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("batch.enc"),scope=Data("batch-fixture".utf8),key=Data(repeating:18,count:32)
        let sender=ChatDeviceKeys(agreement:.init(),signing:.init()),receiver=ChatDeviceKeys(agreement:.init(),signing:.init())
        let a=sender.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),b=receiver.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let config=ChatConfiguration(baseURL:try XCTUnwrap(URL(string:"https://example.invalid")),token:"synthetic",userID:b.userID,deviceID:b.deviceID)
        let now=Date(),stamp=ISO8601DateFormatter().string(from:now)
        var claims:[ChatPendingRecipientProof]=[]
        for i in 0..<8 {
            let e=try sender.encrypt(Data("fragment-\(i)".utf8),kind:.text,contentType:"text/plain",groupID:"fixture-batch",
                chunkIndex:i,chunkCount:8,sender:a,recipient:b,createdAt:stamp)
            claims.append(ChatPendingRecipientProof(proof:try ChatRecipientProofV1.unsignedClaim(e),keyFingerprint:receiver.safetyNumber,committedAt:now))
        }
        func open() throws -> ChatHistoryArchive {try ChatHistoryArchive(file:file,scope:scope,keyData:key)}
        let initial=Dictionary(uniqueKeysWithValues:claims.map{($0.proof.id,$0)})
        try open().save(initial)
        XCTAssertThrowsError(try ChatRecipientProofBatch.prepare(claims,in:initial,keys:sender,configuration:config))
        XCTAssertThrowsError(try ChatRecipientProofBatch.prepare(claims+[claims[0]],in:initial,keys:receiver,configuration:config))
        XCTAssertEqual(try open().load([String:ChatPendingRecipientProof].self),initial)
        let prepared=try ChatRecipientProofBatch.prepare(claims,in:initial,keys:receiver,configuration:config)
        try open().save(prepared)
        let restored=try XCTUnwrap(open().load([String:ChatPendingRecipientProof].self))
        let signed=try claims.map{try XCTUnwrap(restored[$0.proof.id])}
        XCTAssertTrue(signed.allSatisfy{!$0.proof.signature.isEmpty})
        // Simulated crash after the first four HTTP successes: no removal yet.
        XCTAssertEqual(try ChatRecipientProofBatch.prepare(signed,in:restored,keys:receiver,configuration:config),prepared)
        XCTAssertThrowsError(try ChatRecipientProofBatch.completing([claims[0]],in:restored))
        let next=try ChatRecipientProofBatch.completing(Array(signed.prefix(4)),in:restored)
        try open().save(next)
        XCTAssertEqual(try open().load([String:ChatPendingRecipientProof].self),next)
        XCTAssertEqual(next.count,4)
        for item in signed.suffix(4) {XCTAssertEqual(next[item.proof.id],item)}
        XCTAssertThrowsError(try ChatRecipientProofBatch.completing([signed[0]],in:next))
    }
}
