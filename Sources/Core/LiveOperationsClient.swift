import Foundation
import Observation

struct LiveOperationsConfiguration: Equatable, Sendable {
    let baseURL: URL
    let token: String
}

enum LiveOperationsError: LocalizedError {
    case invalidConfiguration
    case missingCredential
    case invalidURL
    case disconnected
    case timedOut
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Die Master-Runtime-Verbindung ist ungültig."
        case .missingCredential: "Für Master Runtime Live ist kein Runner-Live-Token verfügbar."
        case .invalidURL: "Die Master-Runtime-Adresse ist ungültig."
        case .disconnected: "Die Master-Runtime-Verbindung wurde getrennt."
        case .timedOut: "Die Master Runtime antwortet nicht."
        case .invalidMessage: "Die Master Runtime hat ungültige Daten gesendet."
        }
    }
}

private final class LiveOperationsPingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let value = continuation
        continuation = nil
        lock.unlock()
        guard let value else { return }
        switch result {
        case .success: value.resume()
        case let .failure(error): value.resume(throwing: error)
        }
    }
}

actor LiveOperationsClient {
    private let session: URLSession
    private let decoder = LiveOperationsCoding.decoder()
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var generation = 0

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated static func liveURL(
        configuration: LiveOperationsConfiguration,
        lastMCPSequence: Int64?,
        lastSentinelSequence: Int64?
    ) -> URL? {
        let endpoint = configuration.baseURL.appending(path: "v1/operations")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        var items: [URLQueryItem] = []
        if let lastMCPSequence { items.append(URLQueryItem(name: "last_mcp_seq", value: String(lastMCPSequence))) }
        if let lastSentinelSequence { items.append(URLQueryItem(name: "last_sentinelx_seq", value: String(lastSentinelSequence))) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    func stream(
        configuration: LiveOperationsConfiguration,
        lastMCPSequence: Int64?,
        lastSentinelSequence: Int64?
    ) throws -> AsyncThrowingStream<LiveOperationsEnvelope, Error> {
        disconnect()
        guard !configuration.token.isEmpty else { throw LiveOperationsError.missingCredential }
        guard let url = Self.liveURL(
            configuration: configuration,
            lastMCPSequence: lastMCPSequence,
            lastSentinelSequence: lastSentinelSequence
        ) else { throw LiveOperationsError.invalidURL }

        generation += 1
        let activeGeneration = generation
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1024
        socket = task
        task.resume()

        let pair = AsyncThrowingStream.makeStream(
            of: LiveOperationsEnvelope.self,
            throwing: Error.self,
            bufferingPolicy: .bufferingNewest(512)
        )
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task, generation: activeGeneration, continuation: pair.continuation)
        }
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            await self.heartbeatLoop(task: task, generation: activeGeneration)
        }
        pair.continuation.onTermination = { @Sendable _ in
            Task { [weak self] in await self?.disconnect(generation: activeGeneration) }
        }
        return pair.stream
    }

    func disconnect() {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func disconnect(generation activeGeneration: Int) {
        guard activeGeneration == generation else { return }
        disconnect()
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        generation activeGeneration: Int,
        continuation: AsyncThrowingStream<LiveOperationsEnvelope, Error>.Continuation
    ) async {
        do {
            while !Task.isCancelled, activeGeneration == generation {
                let message = try await task.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: throw LiveOperationsError.invalidMessage
                }
                continuation.yield(try decoder.decode(LiveOperationsEnvelope.self, from: data))
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func heartbeatLoop(task: URLSessionWebSocketTask, generation activeGeneration: Int) async {
        while !Task.isCancelled, activeGeneration == generation {
            do {
                try await Task.sleep(for: .seconds(10))
                try await sendPing(task)
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                return
            }
        }
    }

    private func sendPing(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = LiveOperationsPingCompletion(continuation)
            task.sendPing { error in
                if let error { completion.finish(.failure(error)) }
                else { completion.finish(.success(())) }
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                completion.finish(.failure(LiveOperationsError.timedOut))
            }
        }
    }
}

@MainActor
@Observable
final class LiveOperationsModel {
    var connectionState: LiveOperationsConnectionState = .unconfigured
    var mcpState = LiveOperationsSourceState(source: .mcp)
    var sentinelXState = LiveOperationsSourceState(source: .sentinelX)
    var lastError: String?
    var isPresentingConfiguration = false

    private let client = LiveOperationsClient()
    private var streamTask: Task<Void, Never>?
    private var configuration: LiveOperationsConfiguration?
    private let runnerEndpointKey = "runnerControlEndpoint"
    private let runnerLiveTokenAccount = "runnerLiveToken"

    init() {
        refreshRuntimeConfiguration()
    }

    var isConfigured: Bool { configuration != nil }

    var activeOperations: [LiveOperation] {
        let operations = Array(mcpState.activeOperations.values) + Array(sentinelXState.activeOperations.values)
        return operations.sorted { $0.startedAt < $1.startedAt }
    }

    var recentOperations: [LiveOperation] {
        Array((mcpState.recentOperations + sentinelXState.recentOperations)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(50))
    }

    var lastEventAt: Date? {
        [mcpState.lastEventAt, sentinelXState.lastEventAt].compactMap { $0 }.max()
    }

    /// Refreshes Live from the existing Runner/Master connection. No second endpoint or token is stored.
    func refreshRuntimeConfiguration() {
        guard let endpoint = UserDefaults.standard.string(forKey: runnerEndpointKey),
              let url = URL(string: endpoint),
              isAllowedScheme(url.scheme),
              let token = try? KeychainStore.value(account: runnerLiveTokenAccount),
              !token.isEmpty else {
            if configuration != nil { stop(reset: false) }
            configuration = nil
            connectionState = .unconfigured
            return
        }

        let next = LiveOperationsConfiguration(baseURL: url, token: token)
        guard configuration != next else { return }
        stop(reset: false)
        configuration = next
        connectionState = .offline
        lastError = nil
    }

    /// Compatibility entry point for tests. Production UI never persists a separate Live configuration.
    func configure(endpoint: String, token: String) throws {
        stop(reset: true)
        guard let url = URL(string: endpoint), isAllowedScheme(url.scheme), !token.isEmpty else {
            throw LiveOperationsError.invalidConfiguration
        }
        configuration = LiveOperationsConfiguration(baseURL: url, token: token)
        connectionState = .offline
        isPresentingConfiguration = false
        lastError = nil
        startIfNeeded()
    }

    func removeConfiguration() {
        stop(reset: true)
        configuration = nil
        connectionState = .unconfigured
        isPresentingConfiguration = false
        lastError = nil
    }

    func startIfNeeded() {
        refreshRuntimeConfiguration()
        guard streamTask == nil, configuration != nil else { return }
        streamTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop(reset: Bool = false) {
        streamTask?.cancel()
        streamTask = nil
        Task { [client] in await client.disconnect() }
        if reset {
            mcpState = LiveOperationsSourceState(source: .mcp)
            sentinelXState = LiveOperationsSourceState(source: .sentinelX)
        }
        if configuration != nil { connectionState = .offline }
    }

    private func runLoop() async {
        var reconnectAttempt = 0
        let backoff: [Double] = [0.5, 1, 2, 4, 8, 15]
        while !Task.isCancelled {
            guard let configuration else { return }
            connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting
            do {
                let stream = try await client.stream(
                    configuration: configuration,
                    lastMCPSequence: mcpState.needsFullResync ? nil : mcpState.lastSequence,
                    lastSentinelSequence: sentinelXState.needsFullResync ? nil : sentinelXState.lastSequence
                )
                connectionState = .syncing
                for try await event in stream {
                    if Task.isCancelled { return }
                    let result: LiveOperationsApplyResult
                    switch event.source {
                    case .mcp:
                        result = mcpState.apply(event)
                    case .sentinelX:
                        result = sentinelXState.apply(event)
                    }
                    if result == .resyncRequired {
                        connectionState = .degraded
                        break
                    }
                    if result == .applied || result == .duplicate {
                        lastError = nil
                        connectionState = .live
                        reconnectAttempt = 0
                    }
                }
                if Task.isCancelled { return }
                throw LiveOperationsError.disconnected
            } catch is CancellationError {
                return
            } catch {
                lastError = error.localizedDescription
                connectionState = reconnectAttempt >= 2 ? .degraded : .reconnecting
                let delay = backoff[min(reconnectAttempt, backoff.count - 1)]
                reconnectAttempt = min(reconnectAttempt + 1, backoff.count - 1)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func isAllowedScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
#if DEBUG
        return scheme == "http" || scheme == "https"
#else
        return scheme == "https"
#endif
    }
}
