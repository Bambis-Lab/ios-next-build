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
}
