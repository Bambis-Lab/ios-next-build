import Foundation
import XCTest
@testable import IOSNext

final class ChatRecipientProofLedgerTests:XCTestCase {
    @MainActor
    func testEncryptedLedgerRestartAllFragmentsAndAllDevices() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("proof.enc"),aad=Data("ledger-fixture".utf8),key=Data(repeating:55,count:32)
        let sender=ChatDeviceKeys(agreement:.init(),signing:.init())
        let a=sender.publicIdentity(userID:"fixture-sender",deviceID:"ios-a")
        let kb=ChatDeviceKeys(agreement:.init(),signing:.init()),kc=ChatDeviceKeys(agreement:.init(),signing:.init())
        let b=kb.publicIdentity(userID:"fixture-peer",deviceID:"ios-b"),c=kc.publicIdentity(userID:"fixture-peer",deviceID:"ios-c")
        let scope=ChatOutboxScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),user:a.userID,device:a.deviceID,keyFingerprint:sender.safetyNumber)
        func open() throws -> ChatRecipientProofLedger {
            try ChatRecipientProofLedger(scope:scope,archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
        }
        let group=UUID().uuidString.lowercased(),stamp=ISO8601DateFormatter().string(from:Date())
        var envelopes:[ChatEnvelope]=[],proofs:[ChatRecipientProofV1]=[]
        for (peer,keys) in [(b,kb),(c,kc)] {
            for i in 0..<2 {
                let e=try sender.encrypt(Data("fixture".utf8),kind:.text,contentType:"text/plain",groupID:group,
                    chunkIndex:i,chunkCount:2,sender:a,recipient:peer,createdAt:stamp)
                envelopes.append(e)
                proofs.append(try ChatRecipientProofV1.signPersistedEnvelope(e,local:peer,keys:keys))
            }
        }
        let entries=envelopes.map{DurableChatOutbox.Entry(envelope:$0,phase:.confirmed)}
        let pending=DurableChatOutbox.Pending(scope:scope,groupID:group,recipients:[b,c],entries:entries)
        var uncertain=pending
        uncertain.entries[0].phase = .uncertain
        XCTAssertThrowsError(try open().registerConfirmed(uncertain))
        try open().registerConfirmed(pending)
        XCTAssertNil(try Data(contentsOf:file).range(of:Data(group.utf8)))
        try open().apply([proofs[0]])
        XCTAssertTrue(try open().confirmedDevices(groupID:group).isEmpty)
        try open().apply([proofs[1]])
        XCTAssertEqual(try open().confirmedDevices(groupID:group),Set([b.deviceID]))
        XCTAssertTrue(try open().confirmedUsers(groupID:group).isEmpty)
        try open().registerConfirmed(pending)
        XCTAssertEqual(try open().unconfirmedIDs(),Array(envelopes.dropFirst(2).map(\.id)))
        let p=proofs[3]
        let forged=ChatRecipientProofV1(version:p.version,id:p.id,envelopeSHA256:p.envelopeSHA256,
             senderUserID:p.senderUserID,senderDeviceID:p.senderDeviceID,recipientUserID:p.recipientUserID,
             recipientDeviceID:p.recipientDeviceID,signature:proofs[0].signature)
        XCTAssertThrowsError(try open().apply([proofs[2],forged]))
        XCTAssertEqual(try open().unconfirmedIDs().count,2)
        try open().apply(Array(proofs.dropFirst(2)))
        XCTAssertEqual(try open().confirmedUsers(groupID:group),Set([b.userID]))
        XCTAssertEqual(try open().confirmedDevices(groupID:group),Set([b.deviceID,c.deviceID]))
        XCTAssertTrue(try open().unconfirmedIDs().isEmpty)
        try open().apply([proofs[0]])
    }
}
