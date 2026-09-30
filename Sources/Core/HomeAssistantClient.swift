import Foundation
import CoreFoundation

struct HomeAssistantConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL
    let accessToken: String

    var webSocketURL: URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/api/websocket"
        return components?.url
    }
}


struct HomeAssistantUserIdentity: Equatable, Sendable {
    let id: String
    let isOwner: Bool
}

struct HomeAssistantStateChange: Sendable {
    let entityID: String
    let newState: HomeAssistantEntity?
}

enum HomeAssistantClientError: LocalizedError {
    case invalidWebSocketURL
    case invalidResponse
    case disconnected
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidWebSocketURL: "Die Home-Assistant-URL ist ungültig."
        case .invalidResponse: "Home Assistant hat eine ungültige Antwort gesendet."
        case .disconnected: "Die Verbindung zu Home Assistant wurde getrennt."
        case .timedOut: "Home Assistant hat nicht rechtzeitig geantwortet."
        case let .server(message): message
        }
    }
}

struct HomeAssistantClientTimingPolicy: Sendable {
    let authHandshakeSeconds: Double
    let getStatesSeconds: Double
    let commandSeconds: Double
    let heartbeatIntervalSeconds: Double
    let pingTimeoutSeconds: Double

    static let production = HomeAssistantClientTimingPolicy(
        authHandshakeSeconds: 12,
        getStatesSeconds: 15,
        commandSeconds: 10,
        heartbeatIntervalSeconds: 20,
        pingTimeoutSeconds: 5
    )

    static let integrationTest = HomeAssistantClientTimingPolicy(
        authHandshakeSeconds: 4.0,
        getStatesSeconds: 4.0,
        commandSeconds: 2.0,
        heartbeatIntervalSeconds: 0.75,
        pingTimeoutSeconds: 1.5
    )

    func commandTimeoutSeconds(for type: String) -> Double {
        type == "get_states" ? getStatesSeconds : commandSeconds
    }
}

private final class PingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<Void, Error>) -> Bool {
        let continuation: CheckedContinuation<Void, Error>?

        lock.lock()
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

actor HomeAssistantClient {
    private typealias Response = [String: JSONValue]
    private typealias ResponseContinuation = CheckedContinuation<Response, Error>

    private struct PendingRequest {
        let continuation: ResponseContinuation
        let timeoutTask: Task<Void, Never>
    }

    private struct RegistryCache {
        let baseURL: URL
        let currentUserID: String
        let storedAt: Date
        let floors: [HomeAssistantFloor]
        let areas: [HomeAssistantArea]
        let devices: [HomeAssistantDevice]
        let entityRegistry: [HomeAssistantRegistryEntity]
    }

    private static let registryCacheTTL: TimeInterval = 300

    private let timing: HomeAssistantClientTimingPolicy
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var messageID = 0
    private var generation = 0
    private var stateContinuation: AsyncStream<HomeAssistantStateChange>.Continuation?
    private var stateStream: AsyncStream<HomeAssistantStateChange>?
    private var registryCache: RegistryCache?

    init(timing: HomeAssistantClientTimingPolicy = .production) {
        self.timing = timing
    }

    func connect(configuration: HomeAssistantConfiguration) async throws -> HomeAssistantSnapshot {
        resetTransport(clearRegistryCache: false)
        guard let url = configuration.webSocketURL else {
            throw HomeAssistantClientError.invalidWebSocketURL
        }

        generation += 1
        let activeGeneration = generation
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        socket = task
        task.resume()

        do {
            let required = try await receiveObject(
                from: task,
                timeoutSeconds: timing.authHandshakeSeconds
            )
            guard required["type"]?.stringValue == "auth_required" else {
                throw HomeAssistantClientError.invalidResponse
            }
            try await send([
                "type": .string("auth"),
                "access_token": .string(configuration.accessToken)
            ], through: task)

            let authenticated = try await receiveObject(
                from: task,
                timeoutSeconds: timing.authHandshakeSeconds
            )
            guard authenticated["type"]?.stringValue == "auth_ok" else {
                throw HomeAssistantClientError.server(
                    authenticated["message"]?.stringValue ?? "Anmeldung bei Home Assistant fehlgeschlagen."
                )
            }

            let streamPair = AsyncStream.makeStream(
                of: HomeAssistantStateChange.self,
                bufferingPolicy: .bufferingNewest(512)
            )
            stateStream = streamPair.stream
            stateContinuation = streamPair.continuation
            receiveTask = Task { [weak self] in
                guard let self else { return }
                await self.receiveLoop(task: task, generation: activeGeneration)
            }

            async let currentUserResponse = command(type: "auth/current_user")
            async let statesResponse = command(type: "get_states")
            let (currentUserPayload, statesPayload) = try await (currentUserResponse, statesResponse)

            func objects(from response: Response) throws -> [[String: JSONValue]] {
                guard let rows = response["result"]?.arrayValue else {
                    throw HomeAssistantClientError.invalidResponse
                }
                return rows.compactMap { value in
                    guard case let .object(object) = value else { return nil }
                    return object
                }
            }

            func optionalObjects(from response: Response?) throws -> [[String: JSONValue]] {
                guard let response else { return [] }
                return try objects(from: response)
            }

            guard let userObject = currentUserPayload["result"]?.objectValue,
                  let currentUserID = userObject["id"]?.stringValue else {
                throw HomeAssistantClientError.invalidResponse
            }
            let currentUser = HomeAssistantCurrentUser(
                id: currentUserID,
                name: userObject["name"]?.stringValue ?? currentUserID
            )

            let floors: [HomeAssistantFloor]
            let areas: [HomeAssistantArea]
            let devices: [HomeAssistantDevice]
            let entityRegistry: [HomeAssistantRegistryEntity]

            if let cached = reusableRegistryCache(baseURL: configuration.baseURL, currentUserID: currentUserID) {
                floors = cached.floors
                areas = cached.areas
                devices = cached.devices
                entityRegistry = cached.entityRegistry
            } else {
                async let floorsResponse = optionalRegistryCommand(type: "config/floor_registry/list")
                async let areasResponse = optionalRegistryCommand(type: "config/area_registry/list")
                async let devicesResponse = optionalRegistryCommand(type: "config/device_registry/list")
                async let registryResponse = optionalRegistryCommand(type: "config/entity_registry/list")
                let (floorPayload, areaPayload, devicePayload, entityPayload) = try await (
                    floorsResponse, areasResponse, devicesResponse, registryResponse
                )
                floors = try optionalObjects(from: floorPayload).compactMap(HomeAssistantFloor.init(object:))
                areas = try optionalObjects(from: areaPayload).compactMap(HomeAssistantArea.init(object:))
                devices = try optionalObjects(from: devicePayload).compactMap(HomeAssistantDevice.init(object:))
                entityRegistry = try optionalObjects(from: entityPayload).compactMap(HomeAssistantRegistryEntity.init(object:))
                registryCache = RegistryCache(
                    baseURL: configuration.baseURL,
                    currentUserID: currentUserID,
                    storedAt: Date(),
                    floors: floors,
                    areas: areas,
                    devices: devices,
                    entityRegistry: entityRegistry
                )
            }

            let snapshot = HomeAssistantSnapshot(
                currentUser: currentUser,
                states: try objects(from: statesPayload).compactMap(HomeAssistantEntity.init(object:)),
                floors: floors,
                areas: areas,
                devices: devices,
                entityRegistry: entityRegistry
            )

            _ = try await command(
                type: "subscribe_events",
                extra: ["event_type": .string("state_changed")]
            )
            heartbeatTask = Task { [weak self] in
                guard let self else { return }
                await self.heartbeatLoop(task: task, generation: activeGeneration)
            }
            return snapshot
        } catch {
            failConnection(error, generation: activeGeneration)
            throw error
        }
    }

    func currentUserIdentity() async throws -> HomeAssistantUserIdentity {
        let response = try await command(type: "auth/current_user")
        guard case let .object(result)? = response["result"],
              let id = result["id"]?.stringValue else {
            throw HomeAssistantClientError.invalidResponse
        }
        return HomeAssistantUserIdentity(id: id, isOwner: result["is_owner"]?.boolValue ?? false)
    }

    func stateChanges() -> AsyncStream<HomeAssistantStateChange> {
        stateStream ?? AsyncStream { continuation in continuation.finish() }
    }

    func disconnect() {
        resetTransport(clearRegistryCache: true)
    }

    func callService(
        domain: String,
        service: String,
        targetEntityID: String,
        serviceData: [String: JSONValue] = [:]
    ) async throws {
        _ = try await command(type: "call_service", extra: [
            "domain": .string(domain),
            "service": .string(service),
            "target": .object(["entity_id": .string(targetEntityID)]),
            "service_data": .object(serviceData)
        ])
    }

    func callService(
        domain: String,
        service: String,
        serviceData: [String: JSONValue]
    ) async throws {
        _ = try await command(type: "call_service", extra: [
            "domain": .string(domain),
            "service": .string(service),
            "service_data": .object(serviceData)
        ])
    }

    nonisolated static func commandTimeoutSeconds(for type: String) -> Double {
        HomeAssistantClientTimingPolicy.production.commandTimeoutSeconds(for: type)
    }

    private func reusableRegistryCache(baseURL: URL, currentUserID: String) -> RegistryCache? {
        guard let registryCache,
              registryCache.baseURL == baseURL,
              registryCache.currentUserID == currentUserID,
              Date().timeIntervalSince(registryCache.storedAt) <= Self.registryCacheTTL else {
            return nil
        }
        return registryCache
    }

    private func resetTransport(clearRegistryCache: Bool) {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        finishConnection(with: HomeAssistantClientError.disconnected)
        if clearRegistryCache {
            registryCache = nil
        }
    }

    private func optionalRegistryCommand(type: String) async throws -> Response? {
        do {
            return try await command(type: type)
        } catch let error as HomeAssistantClientError {
            if case .server = error {
                return nil
            }
            throw error
        }
    }

    private func command(type: String, extra: Response = [:]) async throws -> Response {
        guard let socket else { throw HomeAssistantClientError.disconnected }
        messageID += 1
        let requestID = messageID
        var payload = extra
        payload["id"] = .number(Double(requestID))
        payload["type"] = .string(type)
        let timeoutSeconds = timing.commandTimeoutSeconds(for: type)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    guard !Task.isCancelled else { return }
                    await self?.failRequest(requestID, error: HomeAssistantClientError.timedOut)
                }
                pendingRequests[requestID] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                Task { [weak self] in
                    do {
                        try await self?.send(payload, through: socket)
                    } catch {
                        await self?.failRequest(requestID, error: error)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failRequest(requestID, error: CancellationError())
            }
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation activeGeneration: Int) async {
        do {
            while !Task.isCancelled, activeGeneration == generation {
                let response = try await receiveObject(from: task)
                route(response)
            }
        } catch {
            failConnection(error, generation: activeGeneration)
        }
    }

    private func heartbeatLoop(task: URLSessionWebSocketTask, generation activeGeneration: Int) async {
        while !Task.isCancelled, activeGeneration == generation {
            do {
                try await Task.sleep(for: .seconds(timing.heartbeatIntervalSeconds))
                guard !Task.isCancelled, activeGeneration == generation else { return }
                try await sendPing(
                    through: task,
                    timeoutSeconds: timing.pingTimeoutSeconds
                )
            } catch is CancellationError {
                return
            } catch {
                failConnection(error, generation: activeGeneration)
                return
            }
        }
    }

    private func sendPing(
        through task: URLSessionWebSocketTask,
        timeoutSeconds: Double
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completion = PingCompletion(continuation: continuation)

            task.sendPing { error in
                if let error {
                    _ = completion.resume(.failure(error))
                } else {
                    _ = completion.resume(.success(()))
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if completion.resume(.failure(HomeAssistantClientError.timedOut)) {
                    task.cancel(with: .goingAway, reason: nil)
                }
            }
        }
    }

    private func failConnection(_ error: Error, generation activeGeneration: Int) {
        guard activeGeneration == generation else { return }
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        finishConnection(with: error)
    }

    private func route(_ response: Response) {
        if let id = response["id"]?.numberValue.map({ Int($0) }),
           let pending = pendingRequests.removeValue(forKey: id) {
            pending.timeoutTask.cancel()
            if response["success"]?.boolValue == false {
                pending.continuation.resume(throwing: HomeAssistantClientError.server(errorMessage(from: response)))
            } else {
                pending.continuation.resume(returning: response)
            }
            return
        }

        guard
            response["type"]?.stringValue == "event",
            case let .object(event)? = response["event"],
            case let .object(data)? = event["data"],
            let entityID = data["entity_id"]?.stringValue
        else { return }

        let newState: HomeAssistantEntity?
        if case let .object(object)? = data["new_state"] {
            newState = HomeAssistantEntity(object: object)
        } else {
            newState = nil
        }
        stateContinuation?.yield(.init(entityID: entityID, newState: newState))
    }

    private func failRequest(_ id: Int, error: Error) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: error)
    }

    private func finishConnection(with error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        requests.forEach {
            $0.timeoutTask.cancel()
            $0.continuation.resume(throwing: error)
        }
        stateContinuation?.finish()
        stateContinuation = nil
        stateStream = nil
    }

    private func errorMessage(from response: Response) -> String {
        if let message = response["error"]?.stringValue { return message }
        if case let .object(error)? = response["error"],
           let message = error["message"]?.stringValue {
            return message
        }
        return "Der Home-Assistant-Aufruf ist fehlgeschlagen."
    }

    private func send(_ object: Response, through task: URLSessionWebSocketTask) async throws {
        let foundationObject = object.mapValues(\.foundationValue)
        let data = try JSONSerialization.data(withJSONObject: foundationObject)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HomeAssistantClientError.invalidResponse
        }
        try await task.send(.string(text))
    }

    private func receiveObject(
        from task: URLSessionWebSocketTask,
        timeoutSeconds: Double? = nil
    ) async throws -> Response {
        guard let timeoutSeconds else {
            return try Self.decode(message: try await task.receive())
        }

        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try Self.decode(message: try await task.receive())
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw HomeAssistantClientError.timedOut
            }

            do {
                guard let response = try await group.next() else {
                    throw HomeAssistantClientError.disconnected
                }
                group.cancelAll()
                return response
            } catch {
                if case HomeAssistantClientError.timedOut = error {
                    task.cancel(with: .goingAway, reason: nil)
                }
                group.cancelAll()
                throw error
            }
        }
    }

    nonisolated private static func decode(
        message: URLSessionWebSocketTask.Message
    ) throws -> Response {
        let text: String
        switch message {
        case let .string(value): text = value
        case let .data(data): text = String(decoding: data, as: UTF8.self)
        @unknown default: throw HomeAssistantClientError.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw HomeAssistantClientError.invalidResponse
        }
        return object.compactMapValues(JSONValue.init(any:))
    }
}

private extension HomeAssistantEntity {
    init?(object: [String: JSONValue]) {
        guard let entityID = object["entity_id"]?.stringValue,
              let state = object["state"]?.stringValue else { return nil }
        let attributes: [String: JSONValue]
        if case let .object(value)? = object["attributes"] {
            attributes = value
        } else {
            attributes = [:]
        }
        self.init(entityID: entityID, state: state, attributes: attributes)
    }
}

extension JSONValue {
    init?(any: Any) {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as [String: Any]:
            self = .object(value.compactMapValues(JSONValue.init(any:)))
        case let value as [Any]:
            self = .array(value.compactMap(JSONValue.init(any:)))
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }
}