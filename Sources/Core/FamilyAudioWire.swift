import Foundation

enum FamilyAudioWireError: Error, Equatable {
    case invalidEndpoint, invalidCredential, invalidState, invalidMessage
    case responseRejected, queueFull, transportClosed
}

/// The audio endpoint is never discovered from an untrusted server response.
/// Production WSS is restricted to the authenticated chat origin. The
/// explicitly requested loopback test route is the only cleartext exception.
enum FamilyAudioEndpoint {
    static func request(configuration: ChatConfiguration, endpoint: URL,
                        syntheticLoopback: Bool = false) throws -> URLRequest {
        let base = ChatRelayClient.transportBaseURL(for: configuration.baseURL)
        guard let c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let origin = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let host = c.host?.lowercased(), let scheme = c.scheme?.lowercased(),
              c.user == nil, c.password == nil, c.fragment == nil, c.query == nil,
              c.percentEncodedPath == "/v1/audio" else {
            throw FamilyAudioWireError.invalidEndpoint
        }
        let loopback = syntheticLoopback && scheme == "ws" && host == "127.0.0.1"
            && origin.host == "127.0.0.1" && origin.scheme == "http"
        let secure = scheme == "wss" && origin.scheme == "https"
            && host == origin.host?.lowercased()
            && (c.port ?? 443) == (origin.port ?? 443)
        guard loopback || secure else { throw FamilyAudioWireError.invalidEndpoint }
        guard !configuration.token.isEmpty, configuration.token.utf8.count <= 4096,
              configuration.token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw FamilyAudioWireError.invalidCredential
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        return request
    }
}

struct FamilyAudioPacket: Decodable, Equatable, Sendable {
    let sequence: UInt64
    let ciphertext: String

    func validatedCiphertext() throws -> Data {
        guard sequence <= UInt64(Int64.max), ciphertext.utf8.count <= 8192,
              let data = Data(base64Encoded: ciphertext), (17...4096).contains(data.count) else {
            throw FamilyAudioWireError.invalidMessage
        }
        return data
    }
}

struct FamilyAudioResult: Decodable, Sendable {
    let active: Bool?
    let published: Bool?
    let queued: Bool?
    let refreshed: Bool?
    let expiresAt: Int?
    let offer: FamilyAudioOffer?

    enum CodingKeys: String, CodingKey {
        case active, published, queued, refreshed, offer
        case expiresAt = "expires_at"
    }
}

enum FamilyAudioInbound: Sendable {
    case bound
    case response(FamilyAudioResult)
    case packets([FamilyAudioPacket])

    private struct Message: Decodable {
        let bound: Bool?
        let mode: String?
        let event: String?
        let packets: [FamilyAudioPacket]?
        let status: Int?
        let result: FamilyAudioResult?
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 128 * 1024 else { throw FamilyAudioWireError.invalidMessage }
        let value = try JSONDecoder().decode(Message.self, from: data)
        if value.bound == true, value.mode == "stream", value.event == nil,
           value.status == nil, value.result == nil, value.packets == nil {
            return .bound
        }
        if value.event == "audio", value.bound == nil, value.status == nil,
           value.result == nil, value.mode == nil, let packets = value.packets,
           (1...20).contains(packets.count) {
            for packet in packets { _ = try packet.validatedCiphertext() }
            guard zip(packets, packets.dropFirst()).allSatisfy({ $0.0.sequence < $0.1.sequence })
            else { throw FamilyAudioWireError.invalidMessage }
            return .packets(packets)
        }
        if value.bound == nil, value.event == nil, value.mode == nil, value.packets == nil,
           let status = value.status {
            guard status == 200, let result = value.result else {
                throw FamilyAudioWireError.responseRejected
            }
            return .response(result)
        }
        throw FamilyAudioWireError.invalidMessage
    }
}

enum FamilyAudioCommand: Sendable {
    case offer(FamilyAudioOffer)
    case peerOffer
    case heartbeat
    case refresh(String)
    case push(sequence: UInt64, ciphertext: Data)

    func wireData() throws -> Data {
        let object: [String: Any]
        switch self {
        case let .offer(offer):
            guard let key = Data(base64Encoded: offer.ephemeral), key.count == 32,
                  let signature = Data(base64Encoded: offer.signature), signature.count == 64 else {
                throw FamilyAudioWireError.invalidMessage
            }
            object = ["action": "offer", "ephemeral": offer.ephemeral, "signature": offer.signature]
        case .peerOffer: object = ["action": "peer_offer"]
        case .heartbeat: object = ["action": "heartbeat"]
        case let .refresh(token):
            guard !token.isEmpty, token.utf8.count <= 4096,
                  token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw FamilyAudioWireError.invalidCredential
            }
            object = ["action": "refresh", "token": token]
        case let .push(sequence, ciphertext):
            guard sequence <= UInt64(Int64.max), (17...4096).contains(ciphertext.count) else {
                throw FamilyAudioWireError.invalidMessage
            }
            object = ["action": "push", "sequence": sequence,
                      "ciphertext": ciphertext.base64EncodedString()]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func accepts(_ result: FamilyAudioResult) -> Bool {
        switch self {
        case .offer: return result.published == true
        case .peerOffer: return result.active == nil && result.published == nil
            && result.queued == nil && result.refreshed == nil && result.expiresAt == nil
        case .heartbeat: return result.active == true
        case .refresh: return result.refreshed == true && (result.expiresAt ?? 0) > 0
        case .push: return result.queued == true
        }
    }
}

/// Experimental, single-use transport. Exactly one receiver reads the socket,
/// and only one command is awaiting its response. Unsolicited audio is separate
/// from command responses. Closing cancels pending reads and discards queued
/// ciphertext. The caller owns the crypto codec and must not reset its counters.
@MainActor
final class FamilyAudioWire {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private let context: FamilyAudioContext
    private var receiveTask: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var waiter: CheckedContinuation<FamilyAudioResult?, Error>?
    private var expected: FamilyAudioCommand?
    private var binding = false
    private var started = false
    private var closed = false
    private var ready = false
    private var packets: [FamilyAudioPacket] = []
    private let maxPackets = 50

    init(configuration: ChatConfiguration, endpoint: URL, context: FamilyAudioContext,
         syntheticLoopback: Bool = false) throws {
        guard context.local == [configuration.userID, configuration.deviceID] else {
            throw FamilyAudioWireError.invalidCredential
        }
        let request = try FamilyAudioEndpoint.request(configuration: configuration,
            endpoint: endpoint, syntheticLoopback: syntheticLoopback)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: ChatRelayNoRedirects(), delegateQueue: nil)
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 128 * 1024
        self.context = context
    }

    func connect() async throws {
        guard !started, !closed else { throw FamilyAudioWireError.invalidState }
        started = true
        binding = true
        let data = try JSONSerialization.data(withJSONObject: ["call_id": context.callID, "mode": "stream"])
        task.resume()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.readLoop()
        }
        _ = try await exchange(data: data, command: nil)
    }

    func send(_ command: FamilyAudioCommand) async throws -> FamilyAudioResult {
        guard ready, !closed, waiter == nil else { throw FamilyAudioWireError.invalidState }
        guard let result = try await exchange(data: command.wireData(), command: command) else {
            throw FamilyAudioWireError.invalidMessage
        }
        return result
    }

    func takePackets() -> [FamilyAudioPacket] {
        let result = packets
        packets.removeAll(keepingCapacity: true)
        return result
    }

    private func exchange(data: Data, command: FamilyAudioCommand?) async throws -> FamilyAudioResult? {
        guard !closed, waiter == nil, let text = String(data: data, encoding: .utf8) else {
            throw FamilyAudioWireError.invalidState
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                expected = command
                deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                    catch { return }
                    self?.close()
                }
                Task { @MainActor [weak self] in
                    guard let self, !self.closed else { return }
                    do { try await self.task.send(.string(text)) }
                    catch { self.close() }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.close() }
        }
    }

    private func finish(_ result: FamilyAudioResult?) throws {
        guard let pending = waiter else { throw FamilyAudioWireError.invalidState }
        waiter = nil
        expected = nil
        deadline?.cancel()
        deadline = nil
        pending.resume(returning: result)
    }

    private func readLoop() async {
        do {
            while !closed {
                let message = try await task.receive()
                guard !closed else { return }
                guard case let .string(text) = message else { throw FamilyAudioWireError.invalidMessage }
                switch try FamilyAudioInbound.decode(Data(text.utf8)) {
                case .bound:
                    guard binding, !ready, expected == nil else { throw FamilyAudioWireError.invalidState }
                    binding = false
                    ready = true
                    try finish(nil)
                case let .response(result):
                    guard ready, let command = expected, command.accepts(result) else {
                        throw FamilyAudioWireError.invalidMessage
                    }
                    try finish(result)
                case let .packets(batch):
                    guard ready else { throw FamilyAudioWireError.invalidState }
                    packets.append(contentsOf: batch)
                    if packets.count > maxPackets { packets.removeFirst(packets.count - maxPackets) }
                }
            }
        } catch {
            close()
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        ready = false
        binding = false
        deadline?.cancel()
        deadline = nil
        receiveTask?.cancel()
        receiveTask = nil
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        let pending = waiter
        waiter = nil
        expected = nil
        packets.removeAll()
        pending?.resume(throwing: FamilyAudioWireError.transportClosed)
    }
}
