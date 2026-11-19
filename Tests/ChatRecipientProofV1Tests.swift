import XCTest
import CryptoKit
@testable import IOSNext

final class ChatRecipientProofV1Tests:XCTestCase {
    func testPythonEd25519FixtureAndScope() throws {
        let keys=ChatDeviceKeys(agreement:.init(),signing:try .init(rawRepresentation:Data(repeating:7,count:32)))
        let recipient=keys.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let digest=String(repeating:"ab",count:32)
        let signature="7EXOBeZcyFZemcuxp3N80e/0l9sJ07tqOmn4WH+Iz3HoDZx5c1AuDR+oEbypc6WTeza2/dxj/2KCxqECyHneCw=="
        let proof=ChatRecipientProofV1(version:1,id:"fixture-envelope",envelopeSHA256:digest,
            senderUserID:"fixture-a",senderDeviceID:"ios-a",recipientUserID:"fixture-b",recipientDeviceID:"ios-b",signature:signature)
        XCTAssertEqual(try keys.signing.signature(for:proof.signingBytes()).base64EncodedString(),signature)
        XCTAssertNoThrow(try proof.verify(expectedID:"fixture-envelope",expectedDigest:digest,
            senderUser:"fixture-a",senderDevice:"ios-a",recipient:recipient))
        XCTAssertThrowsError(try proof.verify(expectedID:"fixture-envelope",expectedDigest:String(repeating:"0",count:64),
            senderUser:"fixture-a",senderDevice:"ios-a",recipient:recipient))
        XCTAssertThrowsError(try proof.verify(expectedID:"fixture-envelope",expectedDigest:digest,
            senderUser:"fixture-a",senderDevice:"other",recipient:recipient))
    }

    func testEnvelopeSigningBindsExactRecipientAndDigest() throws {
        let sender=ChatDeviceKeys(agreement:.init(),signing:.init())
        let recipient=ChatDeviceKeys(agreement:.init(),signing:.init())
        let a=sender.publicIdentity(userID:"fixture-a",deviceID:"ios-a")
        let b=recipient.publicIdentity(userID:"fixture-b",deviceID:"ios-b")
        let e=try sender.encrypt(Data("fixture".utf8),kind:.text,contentType:"text/plain",groupID:"group-fixture",
            chunkIndex:0,chunkCount:1,sender:a,recipient:b,createdAt:ISO8601DateFormatter().string(from:Date()))
        let proof=try ChatRecipientProofV1.signPersistedEnvelope(e,local:b,keys:recipient)
        XCTAssertNoThrow(try proof.verify(expectedID:e.id,expectedDigest:ChatSendReceiptV1.digest(e),
            senderUser:a.userID,senderDevice:a.deviceID,recipient:b))
        XCTAssertThrowsError(try ChatRecipientProofV1.signPersistedEnvelope(e,local:b,keys:sender))
        XCTAssertThrowsError(try proof.verify(expectedID:e.id,expectedDigest:ChatSendReceiptV1.digest(e),
            senderUser:a.userID,senderDevice:a.deviceID,recipient:a))
    }
}
