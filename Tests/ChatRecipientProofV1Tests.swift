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
        // CryptoKit can produce a different valid Ed25519 signature for the
        // same key/message. Compare canonical bytes and verify signatures,
        // not byte equality of newly generated signatures.
        let bytes=try proof.signingBytes()
        XCTAssertEqual(SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),
            "32a57b9336e693762168569593a143f56cd23b943846282ab32ea99c14a46101")
        let nativeSignature=try keys.signing.signature(for:bytes)
        XCTAssertTrue(keys.signing.publicKey.isValidSignature(nativeSignature,for:bytes))
        // Observed native CI signature independently verified by Python.
        let observed=try XCTUnwrap(Data(base64Encoded:"iKUt7azlG0bGrQreJf1Y5cz/GluHoPS97MTnddOdg7UZQxHg4FwsQqgwnHdKGF4zHXfe9qrzlsqlODZhScYlAw=="))
        XCTAssertTrue(keys.signing.publicKey.isValidSignature(observed,for:bytes))
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
