import Foundation
import Observation

@MainActor
protocol FamilyCallWire: AnyObject {
    var isConnected: Bool { get }
    var reconnectPermitted: Bool { get }
    func connect() async throws
    func send(_ command: FamilyAudioCommand) async throws -> FamilyAudioResult
    func sendMedia(sequence: UInt64, ciphertext: Data) async throws -> Bool
    func takePackets() -> [FamilyAudioPacket]
    func close()
}

@MainActor
protocol FamilyCallAudio: AnyObject {
    var isRunning: Bool { get }
    func start(onInterrupted: @escaping @MainActor () -> Void) async throws
    func setMuted(_ value: Bool)
    func takeCapture() -> Data?
    @discardableResult func play(_ data: Data) throws -> Bool
    func stop()
}

extension FamilyCallWire {
    var reconnectPermitted: Bool { false }
    // Deterministic adapter fixtures may implement only the request path.
    func sendMedia(sequence: UInt64, ciphertext: Data) async throws -> Bool {
        _ = try await send(.push(sequence: sequence, ciphertext: ciphertext))
        return true
    }
}

extension FamilyAudioWire: FamilyCallWire {}
extension FamilyAudioDevice: FamilyCallAudio {}

enum FamilyAudioSessionState: Equatable {
    case idle, connecting, verifying, active, reconnecting, ended, failed
}

/// An explicitly initiated foreground single call. No automatic acceptance,
/// discovery of endpoints, or trust-on-first-use of the peer's signing key.
/// The caller must supply an independently confirmed safety number and stop
/// this session on logout, account change or view disappearance.
@MainActor
@Observable
final class FamilyAudioCallSession {
    private(set) var state: FamilyAudioSessionState = .idle
    private(set) var muted = false
    private(set) var sentFrames = 0
    private(set) var droppedFrames = 0
    private(set) var receivedFrames = 0

    private let context: FamilyAudioContext
    private let keys: ChatDeviceKeys
    private let peer: ChatIdentity
    private var wire: any FamilyCallWire
    private let reconnectWire: (@MainActor (String?) throws -> any FamilyCallWire)?
    private let audio: any FamilyCallAudio
    private var generation = UUID()
    private var playoutTask: Task<Void, Never>?

    /// Supply only a newer, independently obtained family credential; nil
    /// means unchanged. The server verifies device binding and expiry.
    typealias CredentialRenewal = @MainActor () async throws -> String?

    convenience init(call: FamilyCallState, configuration: ChatConfiguration,
                     endpoint: URL, keys: ChatDeviceKeys, verifiedPeer: ChatIdentity,
                     confirmedSafetyNumber: String, syntheticLoopback: Bool = false) throws {
        let context = try Self.validate(call: call, configuration: configuration,
            peer: verifiedPeer, confirmedSafetyNumber: confirmedSafetyNumber)
        let wire = try FamilyAudioWire(configuration: configuration, endpoint: endpoint,
            context: context, syntheticLoopback: syntheticLoopback)
        self.init(context: context, keys: keys, peer: verifiedPeer,
                  wire: wire, audio: FamilyAudioDevice(), reconnectWire: { token in
            let next = ChatConfiguration(baseURL: configuration.baseURL,
                token: token ?? configuration.token, userID: configuration.userID,
                deviceID: configuration.deviceID)
            return try FamilyAudioWire(configuration: next, endpoint: endpoint,
                context: context, syntheticLoopback: syntheticLoopback)
        })
    }

    // Injectable adapters used by native deterministic integration tests.
    init(context: FamilyAudioContext, keys: ChatDeviceKeys, peer: ChatIdentity,
         wire: any FamilyCallWire, audio: any FamilyCallAudio,
         reconnectWire: (@MainActor (String?) throws -> any FamilyCallWire)? = nil) {
        self.context = context
        self.keys = keys
        self.peer = peer
        self.wire = wire
        self.reconnectWire = reconnectWire
        self.audio = audio
    }

    static func validate(call: FamilyCallState, configuration: ChatConfiguration,
                         peer: ChatIdentity, confirmedSafetyNumber: String) throws -> FamilyAudioContext {
        guard call.state == .accepted, call.isParticipant(configuration) else {
            throw FamilyAudioError.invalidContext
        }
        let context = try FamilyAudioContext(callID: call.id, caller: call.caller, callee: call.callee,
                                             local: [configuration.userID, configuration.deviceID])
        guard [peer.userID, peer.deviceID] == context.peer,
              Data(base64Encoded: peer.agreementPublicKey)?.count == 32,
              Data(base64Encoded: peer.signingPublicKey)?.count == 32,
              !confirmedSafetyNumber.isEmpty,
              ChatDeviceKeys.safetyNumber(for: peer) == confirmedSafetyNumber else {
            throw FamilyAudioError.invalidSignature
        }
        return context
    }

    func setMuted(_ value: Bool) {
        muted = value
        audio.setMuted(value)
    }

    private func requireCurrent(_ attempt: UUID) throws {
        try Task.checkCancellation()
        guard attempt == generation else { throw CancellationError() }
    }

    /// Runs until stopped or failed. All outbound commands are serialized;
    /// playout has its own monotonic clock and is independent of command RTT.
    func run(renewCredential: @escaping CredentialRenewal = { nil }) async throws {
        guard state == .idle else { throw FamilyAudioWireError.invalidState }
        let attempt = generation
        let clock = ContinuousClock()
        state = .connecting
        defer {
            if generation == attempt { finish(.ended) }
        }
        do {
            try await wire.connect()
            try requireCurrent(attempt)
            state = .verifying
            let handshake = FamilyAudioHandshake(context: context)
            let localOffer = try handshake.offer(signingKey: keys.signing)
            _ = try await wire.send(.offer(localOffer))
            let offerDeadline = clock.now.advanced(by: .seconds(20))
            var peerOffer: FamilyAudioOffer?
            while peerOffer == nil {
                try requireCurrent(attempt)
                guard clock.now < offerDeadline else { throw FamilyAudioWireError.transportClosed }
                peerOffer = try await wire.send(.peerOffer).offer
                if peerOffer == nil { try await Task.sleep(nanoseconds: 250_000_000) }
            }
            try requireCurrent(attempt)
            guard let peerOffer else { throw FamilyAudioError.invalidOffer }
            let codec = try handshake.establish(peerOffer: peerOffer, verifiedPeer: peer)
            try await audio.start { [weak self] in self?.finish(.failed) }
            try requireCurrent(attempt)
            audio.setMuted(muted)
            state = .active
            startPlayout(codec: codec, attempt: attempt)
            var sequence: UInt64 = 0
            var heartbeatAt = clock.now.advanced(by: .seconds(3))
            var renewAt = clock.now
            var latestToken: String?
            var reconnectBudget = 3
            while true {
                do {
                try requireCurrent(attempt)
                guard wire.isConnected, audio.isRunning else { throw FamilyAudioWireError.transportClosed }
                let now = clock.now
                if now >= renewAt {
                    let replacement = try await renewCredential()
                    try requireCurrent(attempt)
                    if let replacement {
                        latestToken = replacement
                        _ = try await wire.send(.refresh(replacement))
                    }
                    renewAt = clock.now.advanced(by: .seconds(30))
                }
                if clock.now >= heartbeatAt {
                    _ = try await wire.send(.heartbeat)
                    heartbeatAt = clock.now.advanced(by: .seconds(3))
                }
                if !muted, let frame = audio.takeCapture() {
                    guard sequence <= UInt64(Int64.max), frame.count == FamilyPCM.bytes else {
                        throw FamilyAudioError.invalidFrame
                    }
                    let ciphertext = try codec.seal(sequence: sequence, frame: frame)
                    sequence += 1
                    let submitted = try await wire.sendMedia(sequence: sequence - 1, ciphertext: ciphertext)
                    try requireCurrent(attempt)
                    if submitted { sentFrames += 1 } else { droppedFrames += 1 }
                }
                try await Task.sleep(nanoseconds: 5_000_000)
                } catch {
                    try requireCurrent(attempt)
                    guard wire.reconnectPermitted, let reconnectWire, audio.isRunning,
                          reconnectBudget > 0 else { throw error }
                    state = .reconnecting
                    playoutTask?.cancel()
                    playoutTask = nil
                    wire.close()
                    // Reuse exactly the established codec and sequence counters.
                    // Never retransmit ciphertext of an attempted media send.
                    while true {
                        guard reconnectBudget > 0 else { throw FamilyAudioWireError.transportClosed }
                        reconnectBudget -= 1
                        try await Task.sleep(for: .milliseconds(300))
                        try requireCurrent(attempt)
                        if let replacement = try await renewCredential() { latestToken = replacement }
                        try requireCurrent(attempt)
                        let replacement = try reconnectWire(latestToken)
                        wire = replacement
                        do {
                            try await replacement.connect()
                            try requireCurrent(attempt)
                            // The relay must still hold the original signed offer.
                            // A missing/changed offer requires a completely new call.
                            let persistedOffer = try await replacement.send(.peerOffer).offer
                            guard persistedOffer == peerOffer else { throw FamilyAudioError.invalidOffer }
                            _ = try await replacement.send(.offer(localOffer))
                            _ = try await replacement.send(.heartbeat)
                            try requireCurrent(attempt)
                            break
                        } catch {
                            let retry = replacement.reconnectPermitted || familyAudioTransientNetworkError(error)
                            replacement.close()
                            guard retry else { throw error }
                        }
                    }
                    // Discard stale captured PCM after an outage.
                    for _ in 0..<128 { if audio.takeCapture() == nil { break } }
                    state = .active
                    startPlayout(codec: codec, attempt: attempt)
                    heartbeatAt = clock.now.advanced(by: .seconds(3))
                    renewAt = clock.now.advanced(by: .seconds(30))
                }
            }
        } catch {
            if generation == attempt {
                finish(error is CancellationError ? .ended : .failed)
            }
            if state == .ended { return }
            throw error
        }
    }

    private func startPlayout(codec: FamilyAudioCodec, attempt: UUID) {
        playoutTask = Task { @MainActor [weak self] in
            var buffer = FamilyPCMPlayout()
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                guard let self, self.generation == attempt else { return }
                do {
                    guard self.audio.isRunning else { throw FamilyAudioWireError.transportClosed }
                    if !self.wire.isConnected, self.wire.reconnectPermitted, self.reconnectWire != nil {
                        // The send/control loop owns recovery. Never let playout
                        // tear down the retained codec during a transient outage.
                        try await Task.sleep(for: .milliseconds(20))
                        continue
                    }
                    guard self.wire.isConnected else { throw FamilyAudioWireError.transportClosed }
                    for packet in self.wire.takePackets() {
                        let frame = try codec.open(sequence: packet.sequence, packet: packet.validatedCiphertext())
                        try buffer.insert(sequence: packet.sequence, frame: frame)
                        self.receivedFrames += 1
                    }
                    if let frame = buffer.next() { _ = try self.audio.play(frame) }
                    next = next.advanced(by: .milliseconds(20))
                    // Don't replay accumulated timer ticks after a scheduling stall.
                    if next < clock.now { next = clock.now.advanced(by: .milliseconds(20)) }
                    try await clock.sleep(until: next)
                } catch {
                    if !Task.isCancelled, self.generation == attempt { self.finish(.failed) }
                    return
                }
            }
        }
    }

    func stop() { finish(.ended) }

    private func finish(_ terminal: FamilyAudioSessionState) {
        guard state != .ended, state != .failed else { return }
        generation = UUID()
        playoutTask?.cancel()
        playoutTask = nil
        audio.stop()
        wire.close()
        state = terminal
    }
}
