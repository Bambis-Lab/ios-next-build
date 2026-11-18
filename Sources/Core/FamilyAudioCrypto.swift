import CryptoKit
import Foundation

/// Experimental single-call audio wire protocol matching the backend's
/// iosnext-audio-v1 reference. Only independently verified contact keys may
/// be supplied. A handshake and codec are single-owner, not transferable.
enum FamilyAudioError: Error, Equatable {
    case invalidContext, invalidOffer, invalidSignature, consumedHandshake
    case invalidFrame, invalidSequence, replay
}

struct FamilyAudioOffer: Codable, Equatable, Sendable {
    let ephemeral: String
    let signature: String
}

struct FamilyAudioContext: Sendable {
    let callID: String
    let caller: [String]
    let callee: [String]
    let local: [String]

    init(callID: String, caller: [String], callee: [String], local: [String]) throws {
        let hex = Set("0123456789abcdef".utf8)
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@".utf8)
        func valid(_ identity: [String]) -> Bool {
            identity.count == 2 && identity.allSatisfy {
                (1...64).contains($0.utf8.count) && $0.utf8.allSatisfy { allowed.contains($0) }
            }
        }
        guard callID.utf8.count == 32, callID.utf8.allSatisfy({ hex.contains($0) }),
              valid(caller), valid(callee), caller != callee,
              local == caller || local == callee else { throw FamilyAudioError.invalidContext }
        self.callID = callID
        self.caller = caller
        self.callee = callee
        self.local = local
    }

    var peer: [String] { local == caller ? callee : caller }

    func transcript(actor: [String], ephemeral: Data) throws -> Data {
        guard actor == caller || actor == callee, ephemeral.count == 32 else {
            throw FamilyAudioError.invalidContext
        }
        let hex = ephemeral.map { String(format: "%02x", $0) }.joined()
        // The initializer admits only ASCII identifier characters requiring no
        // JSON escaping. Exact compact array encoding matches Python ensure_ascii.
        func pair(_ p: [String]) -> String { "[\"\(p[0])\",\"\(p[1])\"]" }
        let value = "[\"\(callID)\",\(pair(caller)),\(pair(callee)),\(pair(actor)),\"\(hex)\"]"
        return Data("iosnext-audio-v1".utf8) + Data([0]) + Data(value.utf8)
    }
}

@MainActor
final class FamilyAudioHandshake {
    private let context: FamilyAudioContext
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private var consumed = false

    init(context: FamilyAudioContext) {
        self.context = context
        self.ephemeral = .init()
    }

    /// Deterministic key injection only for the offline wire-vector tests.
    init(context: FamilyAudioContext, ephemeralForTesting: Curve25519.KeyAgreement.PrivateKey) {
        self.context = context
        self.ephemeral = ephemeralForTesting
    }

    func offer(signingKey: Curve25519.Signing.PrivateKey) throws -> FamilyAudioOffer {
        guard !consumed else { throw FamilyAudioError.consumedHandshake }
        let raw = ephemeral.publicKey.rawRepresentation
        let signature = try signingKey.signature(for: context.transcript(actor: context.local, ephemeral: raw))
        return .init(ephemeral: raw.base64EncodedString(), signature: signature.base64EncodedString())
    }

    func establish(peerOffer: FamilyAudioOffer, verifiedPeer: ChatIdentity) throws -> FamilyAudioCodec {
        guard !consumed else { throw FamilyAudioError.consumedHandshake }
        guard [verifiedPeer.userID, verifiedPeer.deviceID] == context.peer,
              let peerRaw = Data(base64Encoded: peerOffer.ephemeral), peerRaw.count == 32,
              let signature = Data(base64Encoded: peerOffer.signature), signature.count == 64,
              let pinned = Data(base64Encoded: verifiedPeer.signingPublicKey), pinned.count == 32 else {
            throw FamilyAudioError.invalidOffer
        }
        let peerKey = try Curve25519.Signing.PublicKey(rawRepresentation: pinned)
        guard peerKey.isValidSignature(signature, for: try context.transcript(actor: context.peer, ephemeral: peerRaw)) else {
            throw FamilyAudioError.invalidSignature
        }
        let localRaw = ephemeral.publicKey.rawRepresentation
        let isCaller = context.local == context.caller
        let first = isCaller ? localRaw : peerRaw
        let second = isCaller ? peerRaw : localRaw
        let wireContext = try context.transcript(actor: context.caller, ephemeral: first)
            + Data([0]) + context.transcript(actor: context.callee, ephemeral: second)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: peerRaw))
        let material = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(repeating: 0, count: 32),
            sharedInfo: wireContext, outputByteCount: 64
        ).withUnsafeBytes { Data($0) }
        let a = SymmetricKey(data: material.prefix(32))
        let b = SymmetricKey(data: material.suffix(32))
        consumed = true
        return FamilyAudioCodec(send: isCaller ? a : b, receive: isCaller ? b : a, context: wireContext)
    }
}

/// Per-direction sequence counters are retained for the lifetime of this object.
/// Never recreate the codec with the same ephemeral key pair after disconnect.
@MainActor
final class FamilyAudioCodec {
    private let send: SymmetricKey
    private let receive: SymmetricKey
    private let context: Data
    private var lastSent: UInt64?
    private var lastReceived: UInt64?

    fileprivate init(send: SymmetricKey, receive: SymmetricKey, context: Data) {
        self.send = send
        self.receive = receive
        self.context = context
    }

    private func nonceBytes(_ sequence: UInt64) throws -> Data {
        guard sequence <= UInt64(Int64.max) else { throw FamilyAudioError.invalidSequence }
        var big = sequence.bigEndian
        return Data(repeating: 0, count: 4) + withUnsafeBytes(of: &big) { Data($0) }
    }

    func seal(sequence: UInt64, frame: Data) throws -> Data {
        guard (1...4080).contains(frame.count) else { throw FamilyAudioError.invalidFrame }
        if let lastSent, sequence <= lastSent { throw FamilyAudioError.replay }
        let bytes = try nonceBytes(sequence)
        let box = try ChaChaPoly.seal(frame, using: send, nonce: .init(data: bytes),
                                      authenticating: context + bytes)
        lastSent = sequence
        return box.ciphertext + box.tag
    }

    func open(sequence: UInt64, packet: Data) throws -> Data {
        guard (17...4096).contains(packet.count) else { throw FamilyAudioError.invalidFrame }
        if let lastReceived, sequence <= lastReceived { throw FamilyAudioError.replay }
        let bytes = try nonceBytes(sequence)
        let box = try ChaChaPoly.SealedBox(nonce: .init(data: bytes), ciphertext: packet.dropLast(16),
                                          tag: packet.suffix(16))
        let plaintext = try ChaChaPoly.open(box, using: receive, authenticating: context + bytes)
        lastReceived = sequence
        return plaintext
    }
}
