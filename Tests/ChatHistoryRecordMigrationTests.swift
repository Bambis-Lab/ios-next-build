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

    @MainActor
    func testAllMediaMigrationRetainsScopeAndInFlightProofs() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let legacy=root.appendingPathComponent("legacy.enc"),target=root.appendingPathComponent("records.sqlite3")
        let scope=Data("all-media-fixture".utf8),key=Data(repeating:32,count:32),now=Date()
        let sender=ChatDeviceKeys(agreement:.init(),signing:.init())
        let receiver=ChatDeviceKeys(agreement:.init(),signing:.init())
        let a=sender.publicIdentity(userID:"fixture-a",deviceID:"ios-a"),b=receiver.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let config=ChatConfiguration(baseURL:try XCTUnwrap(URL(string:"https://example.invalid")),
            token:"synthetic",userID:b.userID,deviceID:b.deviceID)
        let types:[(ChatMessageKind,String,Int)]=[
            (.text,"text/plain",128),(.image,"image/png",256*1024),
            (.voice,"audio/m4a",512*1024),(.video,"video/mp4",2*1024*1024)]
        var messages:[ChatMessage]=[],partials:[String:ChatPersistentPartial]=[:]
        var seen:[String:Date]=[:],queue:[String:ChatPendingRecipientProof]=[:]
        for (index,item) in types.enumerated() {
            let (kind,mime,size)=item
            // Synthetic opaque media bytes; this test verifies persistence,
            // not AVFoundation playback or image decoding.
            let content=Data(repeating:UInt8(index+32),count:size)
            let group=UUID().uuidString.lowercased()
            messages.append(ChatMessage(id:group,senderUserID:a.userID,recipientUserID:b.userID,
                kind:kind,contentType:mime,data:content,createdAt:now,direction:.incoming,delivery:.received))
            let fragmentGroup=UUID().uuidString.lowercased()
            let fragment=Data(content.prefix(4096))
            let env=try sender.encrypt(fragment,kind:kind,contentType:mime,groupID:fragmentGroup,
                chunkIndex:0,chunkCount:2,sender:a,recipient:b,createdAt:ISO8601DateFormatter().string(from:now))
            partials["\(a.userID)|\(a.deviceID)|\(fragmentGroup)"]=ChatPersistentPartial(senderUserID:a.userID,
                conversationID:nil,kind:kind,contentType:mime,createdAt:now,chunkCount:2,chunks:[0:fragment],lastUpdated:now)
            seen[env.id]=now
            let claim=ChatPendingRecipientProof(proof:try ChatRecipientProofV1.unsignedClaim(env),
                keyFingerprint:receiver.safetyNumber,committedAt:now)
            queue[env.id]=index.isMultiple(of:2) ? claim : try claim.signed(using:receiver,configuration:config)
        }
        let original=ChatPersistentSnapshot(version:1,messages:messages,partials:partials,seen:seen,pendingRecipientProofs:queue)
        let archive=try ChatHistoryArchive(file:legacy,scope:scope,keyData:key)
        try archive.save(original)
        let bytes=try Data(contentsOf:legacy)
        let source=try XCTUnwrap(archive.load(ChatPersistentSnapshot.self))
        let store=try EncryptedChatRecordStore(file:target,scope:scope,keyData:key)
        try await ChatHistoryRecordMigration.rehearse(source,into:store)
        let reopened=try EncryptedChatRecordStore(file:target,scope:scope,keyData:key)
        let checkpoint=ChatRecordReceiveCheckpoint(store:reopened)
        let loaded=try await checkpoint.load()
        XCTAssertEqual(loaded,original)
        let recovered=try XCTUnwrap(loaded.pendingRecipientProofs)
        XCTAssertEqual(recovered.count,4)
        for (id,claim) in queue {
            let recoveredClaim=try XCTUnwrap(recovered[id])
            XCTAssertEqual(recoveredClaim,claim)
            if !claim.proof.signature.isEmpty {
                XCTAssertEqual(try recoveredClaim.signed(using:receiver,configuration:config),claim)
            }
        }
        XCTAssertEqual(try Data(contentsOf:legacy),bytes)
        let foreign=try ChatHistoryArchive(file:legacy,scope:Data("foreign-scope".utf8),keyData:key)
        XCTAssertThrowsError(try foreign.load(ChatPersistentSnapshot.self))
    }
}
