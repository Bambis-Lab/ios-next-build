import Foundation

private final class RunnerLivePingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func succeed() -> Bool {
        let continuation = takeContinuation()
        guard let continuation else { return false }
        continuation.resume()
        return true
    }

    @discardableResult
    func fail(_ error: Error) -> Bool {
        let continuation = takeContinuation()
        guard let continuation else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<Void, Error>? {
        lock.lock()
        let value = continuation
        continuation = nil
        lock.unlock()
        return value
    }
}

enum RunnerLiveError: LocalizedError {
    case invalidURL
    case missingLiveCredential
    case disconnected
    case timedOut
    case invalidMessage
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Die Runner-Live-Adresse ist ungültig."
        case .missingLiveCredential: "Für Runner Live ist kein read-only Live-Token eingerichtet."
        case .disconnected: "Die Runner-Live-Verbindung wurde getrennt."
        case .timedOut: "Die Runner-Live-Verbindung antwortet nicht."
        case .invalidMessage: "Der Runner-Live-Dienst hat ungültige Daten gesendet."
        case let .unsupportedSchema(schema): "Runner-Live-Schema \(schema) wird nicht unterstützt."
        }
    }
}

actor RunnerLiveClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var generation = 0

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = CommanderLiveCoding.decoder()
    }

    nonisolated static func liveURL(
        configuration: RunnerControlConfiguration,
        lastSequence: Int64?
    ) -> URL? {
        let endpoint = configuration.baseURL.appending(path: "v1/live")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        if let lastSequence {
            components.queryItems = [URLQueryItem(name: "last_seq", value: String(lastSequence))]
        }
        return components.url
    }

    func stream(
        configuration: RunnerControlConfiguration,
        lastSequence: Int64?
    ) throws -> AsyncThrowingStream<RunnerLiveEnvelope, Error> {
        disconnect()
        guard let liveToken = configuration.liveToken, !liveToken.isEmpty else {
            throw RunnerLiveError.missingLiveCredential
        }
        guard let url = Self.liveURL(configuration: configuration, lastSequence: lastSequence) else {
            throw RunnerLiveError.invalidURL
        }
        generation += 1
        let activeGeneration = generation
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(liveToken)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1024
        socket = task
        task.resume()

        let pair = AsyncThrowingStream.makeStream(
            of: RunnerLiveEnvelope.self,
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
            Task { [weak self] in
                await self?.disconnect(generation: activeGeneration)
            }
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
        continuation: AsyncThrowingStream<RunnerLiveEnvelope, Error>.Continuation
    ) async {
        do {
            while !Task.isCancelled, activeGeneration == generation {
                let message = try await task.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: throw RunnerLiveError.invalidMessage
                }
                let envelope = try decoder.decode(RunnerLiveEnvelope.self, from: data)
                // Schema support belongs to the deterministic reducer. Keeping transport
                // schema-agnostic lets the UI enter a fail-closed degraded/resync state.
                continuation.yield(envelope)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
        if activeGeneration == generation {
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    private func heartbeatLoop(task: URLSessionWebSocketTask, generation activeGeneration: Int) async {
        while !Task.isCancelled, activeGeneration == generation {
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, activeGeneration == generation else { return }
                try await sendPing(through: task, timeoutSeconds: 3)
            } catch is CancellationError {
                return
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                return
            }
        }
    }

    private func sendPing(through task: URLSessionWebSocketTask, timeoutSeconds: Double) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = RunnerLivePingCompletion(continuation: continuation)
            task.sendPing { error in
                if let error {
                    _ = completion.fail(error)
                } else {
                    _ = completion.succeed()
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if completion.fail(RunnerLiveError.timedOut) {
                    task.cancel(with: .goingAway, reason: nil)
                }
            }
        }
    }
}
