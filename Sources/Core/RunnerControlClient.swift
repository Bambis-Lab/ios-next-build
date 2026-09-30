import Foundation
import LocalAuthentication
import Observation

struct RunnerSubsystemStatus: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let active: Bool
    let version: String?
    let detail: String?
    let lastSeen: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, active, version, detail
        case lastSeen = "last_seen"
    }
}

struct RunnerServiceStatus: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let active: Bool
    let detail: String?
}

struct RunnerBackupStatus: Codable, Equatable, Sendable {
    let state: String
    let lastSuccessful: Date?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case state, detail
        case lastSuccessful = "last_successful"
    }
}

struct RunnerAuditEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let timestamp: Date
    let action: String
    let result: String
}

struct RunnerInstanceStatus: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let online: Bool
    let busy: Bool
    let labels: [String]?
    let operatingSystem: String?
    let architecture: String?
    let currentJobID: String?
    let lastSeen: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, online, busy, labels, architecture
        case operatingSystem = "operating_system"
        case currentJobID = "current_job_id"
        case lastSeen = "last_seen"
    }
}

struct RunnerJobStatus: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let workflow: String?
    let repository: String?
    let branch: String?
    let runnerID: String?
    let runnerName: String?
    let state: String
    let startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, workflow, repository, branch, state
        case runnerID = "runner_id"
        case runnerName = "runner_name"
        case startedAt = "started_at"
    }
}

struct RunnerStatus: Codable, Equatable, Sendable {
    let vmOnline: Bool
    let serviceActive: Bool
    let registeredRunners: Int
    let idleRunners: Int
    let busyRunners: Int
    let cpuPercent: Double?
    let memoryPercent: Double?
    let diskPercent: Double?
    let lastHealthCheck: Date?
    let uptimeSeconds: Double?
    let maintenanceMode: Bool?
    let bridge: RunnerSubsystemStatus?
    let orchestrator: RunnerSubsystemStatus?
    let commander: CommanderSnapshot?
    let services: [RunnerServiceStatus]?
    let backup: RunnerBackupStatus?
    let recentAudit: [RunnerAuditEntry]?
    let runnerInstances: [RunnerInstanceStatus]?
    let activeJobs: [RunnerJobStatus]?

    enum CodingKeys: String, CodingKey {
        case vmOnline = "vm_online"
        case serviceActive = "service_active"
        case registeredRunners = "registered_runners"
        case idleRunners = "idle_runners"
        case busyRunners = "busy_runners"
        case cpuPercent = "cpu_percent"
        case memoryPercent = "memory_percent"
        case diskPercent = "disk_percent"
        case lastHealthCheck = "last_health_check"
        case uptimeSeconds = "uptime_seconds"
        case maintenanceMode = "maintenance_mode"
        case bridge, orchestrator, commander, services, backup
        case recentAudit = "recent_audit"
        case runnerInstances = "runner_instances"
        case activeJobs = "active_jobs"
    }
}

struct RunnerActionReceipt: Codable, Equatable, Sendable {
    let requestID: String
    let state: String
    let activeJobs: Int?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
        case activeJobs = "active_jobs"
    }
}

enum RunnerAction: String, Codable, CaseIterable, Sendable {
    case healthCheck = "health-check"
    case pause
    case resume
    case gracefulRestart = "restart-gracefully"
    case shutdown

    var title: String {
        switch self {
        case .healthCheck: "Health Check"
        case .pause: "Pausieren"
        case .resume: "Fortsetzen"
        case .gracefulRestart: "Sicher neu starten"
        case .shutdown: "VM herunterfahren"
        }
    }

    var requiresBiometrics: Bool {
        self == .gracefulRestart || self == .shutdown
    }

    var path: String {
        switch self {
        case .healthCheck: "v1/health-check"
        case .pause: "v1/runners/pause"
        case .resume: "v1/runners/resume"
        case .gracefulRestart: "v1/runners/restart-gracefully"
        case .shutdown: "v1/vm/shutdown"
        }
    }
}

struct RunnerControlConfiguration: Equatable, Sendable {
    let baseURL: URL
    let token: String
    let liveToken: String?

    init(baseURL: URL, token: String, liveToken: String? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.liveToken = liveToken
    }
}

enum RunnerControlError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case rejected(Int)
    case biometricAuthenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Die Runner-Control-Adresse oder das Token fehlt."
        case .invalidResponse: "Der Runner-Control-Dienst hat ungültige Daten gesendet."
        case let .rejected(code): "Der Runner-Control-Dienst hat die Anfrage abgelehnt (HTTP \(code))."
        case .biometricAuthenticationFailed: "Die Aktion wurde nicht biometrisch bestätigt."
        }
    }
}

actor RunnerControlClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = CommanderLiveCoding.decoder()
    }

    func status(configuration: RunnerControlConfiguration) async throws -> RunnerStatus {
        try await request(path: "v1/status", method: "GET", configuration: configuration)
    }

    func perform(_ action: RunnerAction, configuration: RunnerControlConfiguration) async throws -> RunnerActionReceipt {
        try await request(path: action.path, method: "POST", configuration: configuration)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        configuration: RunnerControlConfiguration
    ) async throws -> Response {
        let url = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RunnerControlError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw RunnerControlError.rejected(http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }
}

@MainActor
@Observable
final class RunnerControlModel {
    enum State: Equatable {
        case notConfigured
        case loading
        case ready(RunnerStatus)
        case failed(String)
    }

    var state: State = .notConfigured
    var isPresentingConfiguration = false
    var lastReceipt: RunnerActionReceipt?
    var lastError: String?
    var commanderLiveState = CommanderLiveViewState()

    private let client = RunnerControlClient()
    private let liveClient = RunnerLiveClient()
    private var commanderLiveTask: Task<Void, Never>?
    private let endpointKey = "runnerControlEndpoint"
    private let tokenAccount = "runnerControlToken"
    private let liveTokenAccount = "runnerLiveToken"
    private var configuration: RunnerControlConfiguration?

    init() {
        restoreConfiguration()
    }

    func configure(endpoint: String, token: String, liveToken: String = "") throws {
        stopCommanderLive(reset: true)
        guard let url = URL(string: endpoint), isAllowedScheme(url.scheme), !token.isEmpty else {
            throw RunnerControlError.invalidConfiguration
        }
        let normalizedLiveToken = liveToken.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration = RunnerControlConfiguration(
            baseURL: url,
            token: token,
            liveToken: normalizedLiveToken.isEmpty ? nil : normalizedLiveToken
        )
        UserDefaults.standard.set(url.absoluteString, forKey: endpointKey)
        try KeychainStore.save(token, account: tokenAccount)
        if normalizedLiveToken.isEmpty {
            KeychainStore.delete(account: liveTokenAccount)
        } else {
            try KeychainStore.save(normalizedLiveToken, account: liveTokenAccount)
        }
        state = .loading
        isPresentingConfiguration = false
    }

    private func isAllowedScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
#if DEBUG
        return ["http", "https"].contains(scheme)
#else
        return scheme == "https"
#endif
    }

    func refresh() async {
        guard let configuration else {
            state = .notConfigured
            return
        }
        if case .ready = state { } else { state = .loading }
        do {
            lastError = nil
            let status = try await client.status(configuration: configuration)
            state = .ready(status)
            if let commander = status.commander {
                if commanderLiveState.connection != .live {
                    commanderLiveState.seedSnapshot(commander)
                }
                startCommanderLiveIfNeeded()
            } else {
                stopCommanderLive(reset: true)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if case .ready = state {
                lastError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func perform(_ action: RunnerAction) async {
        guard let configuration else {
            state = .notConfigured
            return
        }
        do {
            lastError = nil
            if action.requiresBiometrics {
                try await authenticate()
            }
            lastReceipt = try await client.perform(action, configuration: configuration)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeConfiguration() {
        stopCommanderLive(reset: true)
        configuration = nil
        UserDefaults.standard.removeObject(forKey: endpointKey)
        KeychainStore.delete(account: tokenAccount)
        KeychainStore.delete(account: liveTokenAccount)
        lastError = nil
        state = .notConfigured
    }


    func stopCommanderLive(reset: Bool = false) {
        commanderLiveTask?.cancel()
        commanderLiveTask = nil
        Task { [liveClient] in
            await liveClient.disconnect()
        }
        if reset {
            commanderLiveState.resetForConfigurationRemoval()
        } else if commanderLiveState.connection != .disconnected {
            commanderLiveState.connection = .disconnected
        }
    }

    private func startCommanderLiveIfNeeded() {
        guard commanderLiveTask == nil else { return }
        guard configuration?.liveToken?.isEmpty == false else {
            commanderLiveState.connection = .unconfigured
            return
        }
        commanderLiveTask = Task { [weak self] in
            guard let self else { return }
            await self.commanderLiveLoop()
        }
    }

    private func commanderLiveLoop() async {
        var reconnectAttempt = 0
        var forceFullResync = commanderLiveState.needsFullResync
        let backoff: [Double] = [0.5, 1, 2, 4, 8, 15]

        while !Task.isCancelled {
            guard let configuration else { return }
            commanderLiveState.connection = reconnectAttempt == 0 ? .connecting : .reconnecting
            do {
                let resumeSequence = forceFullResync ? nil : commanderLiveState.lastSequence
                let stream = try await liveClient.stream(
                    configuration: configuration,
                    lastSequence: resumeSequence
                )
                commanderLiveState.connection = .syncing
                var requestedResync = false
                for try await event in stream {
                    if Task.isCancelled { return }
                    let result = commanderLiveState.apply(event)
                    if result == .resyncRequired {
                        forceFullResync = true
                        requestedResync = true
                        break
                    }
                    if event.type == "commander.snapshot" {
                        forceFullResync = false
                        reconnectAttempt = 0
                    }
                }
                if Task.isCancelled { return }
                if requestedResync {
                    reconnectAttempt = 0
                    continue
                }
                throw RunnerLiveError.disconnected
            } catch is CancellationError {
                return
            } catch {
                if commanderLiveState.needsFullResync || reconnectAttempt >= 2 {
                    commanderLiveState.connection = .degraded
                } else {
                    commanderLiveState.connection = .reconnecting
                }
                let delay = backoff[min(reconnectAttempt, backoff.count - 1)]
                reconnectAttempt = min(reconnectAttempt + 1, backoff.count - 1)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func restoreConfiguration() {
        guard let endpoint = UserDefaults.standard.string(forKey: endpointKey),
              let url = URL(string: endpoint),
              let token = try? KeychainStore.value(account: tokenAccount),
              !token.isEmpty else { return }
        let liveToken = try? KeychainStore.value(account: liveTokenAccount)
        configuration = RunnerControlConfiguration(
            baseURL: url,
            token: token,
            liveToken: liveToken?.isEmpty == false ? liveToken : nil
        )
        state = .loading
    }

    private func authenticate() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw RunnerControlError.biometricAuthenticationFailed
        }
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Kritische Runner-Aktion bestätigen"
        )
        guard success else { throw RunnerControlError.biometricAuthenticationFailed }
    }
}
