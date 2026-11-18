import CryptoKit
import XCTest
@testable import IOSNext

final class FamilyAudioCryptoTests: XCTestCase {
    @MainActor
    func testAuthenticatedBidirectionalCodecAndReplay() throws {
        let a = ["ha-gabi", "ios-fixture-a"]
        let b = ["ha-timo", "ios-fixture-b"]
        let id = String(repeating: "a", count: 32)
        let ca = try FamilyAudioContext(callID: id, caller: a, callee: b, local: a)
        let cb = try FamilyAudioContext(callID: id, caller: a, callee: b, local: b)
        let ka = ChatDeviceKeys(agreement: .init(), signing: .init())
        let kb = ChatDeviceKeys(agreement: .init(), signing: .init())
        let left = FamilyAudioHandshake(context: ca)
        let right = FamilyAudioHandshake(context: cb)
        let oa = try left.offer(signingKey: ka.signing)
        let ob = try right.offer(signingKey: kb.signing)
        let ia = ka.publicIdentity(userID: a[0], deviceID: a[1])
        let ib = kb.publicIdentity(userID: b[0], deviceID: b[1])
        let wrong = ka.publicIdentity(userID: b[0], deviceID: b[1])
        XCTAssertThrowsError(try left.establish(peerOffer: ob, verifiedPeer: wrong))
        let ac = try left.establish(peerOffer: ob, verifiedPeer: ib)
        let bc = try right.establish(peerOffer: oa, verifiedPeer: ia)
        XCTAssertThrowsError(try left.establish(peerOffer: ob, verifiedPeer: ib))
        let frame = Data("synthetic audio".utf8)
        let packet = try ac.seal(sequence: 0, frame: frame)
        XCTAssertEqual(try bc.open(sequence: 0, packet: packet), frame)
        XCTAssertThrowsError(try bc.open(sequence: 0, packet: packet))
        XCTAssertThrowsError(try ac.seal(sequence: 0, frame: frame))
        let reverse = try bc.seal(sequence: 0, frame: frame)
        XCTAssertNotEqual(reverse, packet)
        XCTAssertEqual(try ac.open(sequence: 0, packet: reverse), frame)
        let next = try ac.seal(sequence: 1, frame: frame)
        var corrupt = next
        corrupt[corrupt.startIndex] ^= 1
        XCTAssertThrowsError(try bc.open(sequence: 1, packet: corrupt))
        XCTAssertEqual(try bc.open(sequence: 1, packet: next), frame)
        XCTAssertThrowsError(try ac.seal(sequence: UInt64.max, frame: frame))
        XCTAssertThrowsError(try ac.seal(sequence: 2, frame: Data()))
        XCTAssertThrowsError(try ac.seal(sequence: 2, frame: Data(repeating: 0, count: 4081)))
    }

    func testExactPythonTranscriptAndInvalidIdentities() throws {
        let id = String(repeating: "a", count: 32)
        let caller = ["ha-gabi","ios-fixture-a"]
        let callee = ["ha-timo","ios-fixture-b"]
        let c = try FamilyAudioContext(callID: id, caller: caller, callee: callee, local: caller)
        let raw = Data(repeating: 0x01, count: 32)
        let expected = "iosnext-audio-v1\u{0}[\"\(id)\",[\"ha-gabi\",\"ios-fixture-a\"],[\"ha-timo\",\"ios-fixture-b\"],[\"ha-gabi\",\"ios-fixture-a\"],\"\(String(repeating: "01", count: 32))\"]"
        XCTAssertEqual(try c.transcript(actor: caller, ephemeral: raw), Data(expected.utf8))
        XCTAssertThrowsError(try FamilyAudioContext(callID: id, caller: caller, callee: caller, local: caller))
        XCTAssertThrowsError(try FamilyAudioContext(callID: id, caller: ["bad\"id","device"], callee: callee, local: callee))
        XCTAssertThrowsError(try c.transcript(actor: ["foreign","device"], ephemeral: raw))
    }
}
