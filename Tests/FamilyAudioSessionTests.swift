import Foundation
import CryptoKit
import XCTest
@testable import IOSNext

@MainActor
private final class SessionAudioFixture: FamilyCallAudio {
    var isRunning = false
    var didStart = false
    var didStop = false
    var played: [Data] = []
    var frame: Data? = Data(repeating: 1, count: FamilyPCM.bytes)
    func start(onInterrupted: @escaping @MainActor () -> Void) async throws {
        didStart = true
        isRunning = true
    }
    func setMuted(_ value: Bool) { if value { frame = nil } }
    func takeCapture() -> Data? { defer { frame = nil }; return frame }
    func play(_ data: Data) throws -> Bool { played.append(data); return true }
    func stop() { isRunning = false; didStop = true }
}

@MainActor
private final class SessionWireFixture: FamilyCallWire {
    var isConnected = false
    var didClose = false
    var didRenew = false
    var received: Data?
    var corruptOffer = false
    var interruptFirstPush = false
    var reconnectPermitted = false
    var receivedSequences: [UInt64] = []
    private var originalOffer: FamilyAudioOffer?
    private var packets: [FamilyAudioPacket] = []
    private let handshake: FamilyAudioHandshake
    private let localIdentity: ChatIdentity
    private let signing: Curve25519.Signing.PrivateKey
    private var codec: FamilyAudioCodec?

    init(peerContext: FamilyAudioContext, peerKeys: ChatDeviceKeys, localIdentity: ChatIdentity) {
        handshake = FamilyAudioHandshake(context: peerContext)
        signing = peerKeys.signing
        self.localIdentity = localIdentity
    }
    func connect() async throws { isConnected = true; reconnectPermitted = false }
    func send(_ command: FamilyAudioCommand) async throws -> FamilyAudioResult {
        guard isConnected else { throw FamilyAudioWireError.transportClosed }
        func result(active: Bool? = nil, published: Bool? = nil, queued: Bool? = nil,
                    refreshed: Bool? = nil, expiresAt: Int? = nil, offer: FamilyAudioOffer? = nil) -> FamilyAudioResult {
            .init(active: active, published: published, queued: queued,
                  refreshed: refreshed, expiresAt: expiresAt, offer: offer)
        }
        switch command {
        case .offer(let offer):
            if let originalOffer {
                guard originalOffer == offer else { throw FamilyAudioError.invalidOffer }
                return result(published: true)
            }
            originalOffer = offer
            // Generate our offer before consuming our one-use handshake.
            ownOffer = try handshake.offer(signingKey: signing)
            codec = try handshake.establish(peerOffer: offer, verifiedPeer: localIdentity)
            return result(published: true)
        case .peerOffer:
            if corruptOffer, let ownOffer {
                return result(offer: .init(ephemeral: ownOffer.ephemeral,
                    signature: Data(repeating: 0, count: 64).base64EncodedString()))
            }
            return result(offer: ownOffer)
        case .heartbeat: return result(active: true)
        case .refresh(let token):
            didRenew = token == "renewed-fixture"
            return result(refreshed: true, expiresAt: 123456)
        case .push(let sequence, let ciphertext):
            let codec = try XCTUnwrap(codec)
            received = try codec.open(sequence: sequence, packet: ciphertext)
            receivedSequences.append(sequence)
            if interruptFirstPush {
                interruptFirstPush = false
                reconnectPermitted = true
                isConnected = false
                throw FamilyAudioWireError.transportClosed
            }
            for i in 0..<3 {
                let data = try codec.seal(sequence: UInt64(i), frame: Data(repeating: 2, count: FamilyPCM.bytes))
                packets.append(.init(sequence: UInt64(i), ciphertext: data.base64EncodedString()))
            }
            return result(queued: true)
        }
    }
    private var ownOffer: FamilyAudioOffer?
    func takePackets() -> [FamilyAudioPacket] { defer { packets.removeAll() }; return packets }
    func close() { isConnected = false; didClose = true; packets.removeAll() }
}

@MainActor
private final class ResumedSessionWireFixture: FamilyCallWire {
    let peer: SessionWireFixture
    init(peer: SessionWireFixture) { self.peer = peer }
    var isConnected: Bool { peer.isConnected }
    func connect() async throws { try await peer.connect() }
    func send(_ command: FamilyAudioCommand) async throws -> FamilyAudioResult { try await peer.send(command) }
    func takePackets() -> [FamilyAudioPacket] { peer.takePackets() }
    func close() { peer.close() }
}

final class FamilyAudioSessionTests: XCTestCase {
    @MainActor
    func testReconnectRetainsCodecAndNeverRetriesAttemptedSequence() async throws {
        let a = ["ha-gabi", "ios-a"], b = ["ha-timo", "ios-b"]
        let id = String(repeating: "c", count: 32)
        let ca = try FamilyAudioContext(callID: id, caller: a, callee: b, local: a)
        let cb = try FamilyAudioContext(callID: id, caller: a, callee: b, local: b)
        let ka = ChatDeviceKeys(agreement: .init(), signing: .init())
        let kb = ChatDeviceKeys(agreement: .init(), signing: .init())
        let wire = SessionWireFixture(peerContext: cb, peerKeys: kb,
            localIdentity: ka.publicIdentity(userID: a[0], deviceID: a[1]))
        wire.interruptFirstPush = true
        let audio = SessionAudioFixture()
        var reconnects = 0
        let session = FamilyAudioCallSession(context: ca, keys: ka,
            peer: kb.publicIdentity(userID: b[0], deviceID: b[1]), wire: wire, audio: audio,
            reconnectWire: { _ in
                reconnects += 1
                return ResumedSessionWireFixture(peer: wire)
            })
        let run = Task { @MainActor in try await session.run() }
        defer { session.stop(); run.cancel() }
        for _ in 0..<200 {
            if reconnects == 1 && session.state == .active { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(reconnects, 1)
        XCTAssertEqual(session.state, .active)
        audio.frame = Data(repeating: 3, count: FamilyPCM.bytes)
        for _ in 0..<200 {
            if wire.receivedSequences.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(wire.receivedSequences, [0, 1])
        XCTAssertEqual(wire.received, Data(repeating: 3, count: FamilyPCM.bytes))
        session.stop()
        try await run.value
    }

    @MainActor
    func testIntegratedEncryptedCaptureAndPlayoutWithAdapterFixtures() async throws {
        let a = ["ha-gabi", "ios-a"]
        let b = ["ha-timo", "ios-b"]
        let id = String(repeating: "b", count: 32)
        let ca = try FamilyAudioContext(callID: id, caller: a, callee: b, local: a)
        let cb = try FamilyAudioContext(callID: id, caller: a, callee: b, local: b)
        let ka = ChatDeviceKeys(agreement: .init(), signing: .init())
        let kb = ChatDeviceKeys(agreement: .init(), signing: .init())
        let wire = SessionWireFixture(peerContext: cb, peerKeys: kb, localIdentity: ka.publicIdentity(userID: a[0], deviceID: a[1]))
        let audio = SessionAudioFixture()
        let session = FamilyAudioCallSession(context: ca, keys: ka,
            peer: kb.publicIdentity(userID: b[0], deviceID: b[1]), wire: wire, audio: audio)
        let run = Task { @MainActor in try await session.run { "renewed-fixture" } }
        defer { session.stop(); run.cancel() }
        for _ in 0..<200 {
            if audio.played.count >= 3 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(session.state, .active)
        XCTAssertEqual(wire.received, Data(repeating: 1, count: FamilyPCM.bytes))
        XCTAssertEqual(audio.played.first, Data(repeating: 2, count: FamilyPCM.bytes))
        XCTAssertEqual(session.sentFrames, 1)
        XCTAssertEqual(session.receivedFrames, 3)
        XCTAssertTrue(wire.didRenew)
        session.stop()
        try await run.value
        XCTAssertEqual(session.state, .ended)
        XCTAssertTrue(audio.didStop)
        XCTAssertTrue(wire.didClose)
    }

    @MainActor
    func testInvalidPeerOfferNeverStartsMicrophone() async throws {
        let a = ["ha-gabi", "ios-a"], b = ["ha-timo", "ios-b"]
        let id = String(repeating: "b", count: 32)
        let ca = try FamilyAudioContext(callID: id, caller: a, callee: b, local: a)
        let cb = try FamilyAudioContext(callID: id, caller: a, callee: b, local: b)
        let ka = ChatDeviceKeys(agreement: .init(), signing: .init())
        let kb = ChatDeviceKeys(agreement: .init(), signing: .init())
        let wire = SessionWireFixture(peerContext: cb, peerKeys: kb, localIdentity: ka.publicIdentity(userID: a[0], deviceID: a[1]))
        wire.corruptOffer = true
        let audio = SessionAudioFixture()
        let session = FamilyAudioCallSession(context: ca, keys: ka,
            peer: kb.publicIdentity(userID: b[0], deviceID: b[1]), wire: wire, audio: audio)
        do {
            try await session.run()
            XCTFail("Invalid signature must stop setup")
        } catch {}
        XCTAssertEqual(session.state, .failed)
        XCTAssertFalse(audio.didStart)
        XCTAssertTrue(wire.didClose)
    }
}
