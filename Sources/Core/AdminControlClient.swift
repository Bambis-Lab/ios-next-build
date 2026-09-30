import Foundation
import LocalAuthentication
import Observation

struct AdminIdentity: Codable, Equatable, Sendable {
    let subject: String
    let displayName: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case subject
        case displayName = "display_name"
        case role
    }
}

struct AdminBackendStatus: Codable, Equatable, Sendable {
    let version: String
    let environment: String
    let healthy: Bool
    let maintenanceMode: Bool
    let uptimeSeconds: Double
    let activeWebSocketSessions: Int
    let queueDepth: Int
    let cacheEntries: Int
    let databaseHealthy: Bool
    let lastBackup: Date?
    let chatQueuedChunks: Int?
    let chatQueuedBytes: Int?
    let chatDeviceQueues: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case environment
        case healthy
        case maintenanceMode = "maintenance_mode"
        case uptimeSeconds = "uptime_seconds"
        case activeWebSocketSessions = "active_websocket_sessions"
        case queueDepth = "queue_depth"
        case cacheEntries = "cache_entries"
        case databaseHealthy = "database_healthy"
        case lastBackup = "last_backup"
        case chatQueuedChunks = "chat_queued_chunks"
        case chatQueuedBytes = "chat_queued_bytes"
        case chatDeviceQueues = "chat_device_queues"
    }
}

struct AdminAuditEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let actor: String
    let action: String
    let result: String
}

struct AdminActionReceipt: Codable, Equatable, Sendable {
    let requestID: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
    }
}

enum AdminAction: String, CaseIterable, Identifiable, Sendable {
    case healthCheck = "health-check"
    case enableMaintenance = "maintenance-enable"
    case disableMaintenance = "maintenance-disable"
    case reconnectSessions = "reconnect-sessions"
    case clearCache = "clear-cache"
    case rotateLogs = "rotate-logs"
    case createBackup = "create-backup"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthCheck: "Vollständiger Health Check"
        case .enableMaintenance: "Wartungsmodus aktivieren"
        case .disableMaintenance: "Wartungsmodus beenden"
        case .reconnectSessions: "Verbindungen neu aufbauen"
        case .clearCache: "Cache sicher leeren"
        case .rotateLogs: "Logs rotieren"
        case .createBackup: "Backend-Backup erstellen"
        }
    }

    var symbol: String {
        switch self {
        case .healthCheck: "stethoscope"
        case .enableMaintenance, .disableMaintenance: "wrench.and.screwdriver.fill"
        case .reconnectSessions: "arrow.triangle.2.circlepath"
        case .clearCache: "trash.slash.fill"
        case .rotateLogs: "doc.text.fill"
        case .createBackup: "externaldrive.fill.badge.plus"
        }
    }

    var requiresFreshBiometrics: Bool { self != .healthCheck }
}

struct AdminControlConfiguration: Equatable, Sendable {
    static let suggestedEndpoint = "https://iosnext-owner.tailff745a.ts.net/"

    let baseURL: URL
    let ownerToken: String
}

enum AdminControlError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case forbidden
    case rejected(Int)
    case biometricAuthenticationFailed
    case deviceBindingFailed
    case breakGlassRequired
    case actionUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Admin-Backend-Adresse oder Owner-Token fehlt."
        case .invalidResponse: "Das Admin-Backend hat ungültige Daten gesendet."
        case .forbidden: "Dieses Konto besitzt keine Owner-Berechtigung."
        case let .rejected(code): "Das Admin-Backend hat die Anfrage abgelehnt (HTTP \(code))."
        case .biometricAuthenticationFailed: "Die Owner-Authentifizierung wurde nicht bestätigt."
        case .deviceBindingFailed: "Die gerätegebundene Owner-Sitzung konnte nicht bestätigt werden."
        case .breakGlassRequired: "Für diese kritische Aktion ist eine aktive Break-Glass-Sitzung erforderlich."
        case .actionUnavailable: "Diese Aktion ist im aktuellen Owner-Modus nicht verfügbar."
        }
    }
}

enum OwnerDeviceBindingPhase: Equatable {
    case unavailable
    case enrolling
    case verifying
    case trusted(Date)
    case failed(String)
}

actor AdminControlClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func identity(configuration: AdminControlConfiguration) async throws -> AdminIdentity {
        try await request(path: "v1/admin/session", method: "GET", configuration: configuration)
    }

    func status(configuration: AdminControlConfiguration) async throws -> AdminBackendStatus {
        try await request(path: "v1/admin/status", method: "GET", configuration: configuration)
    }

    func audit(configuration: AdminControlConfiguration) async throws -> [AdminAuditEvent] {
        try await request(path: "v1/admin/audit?limit=50", method: "GET", configuration: configuration)
    }

    func tickets(configuration: AdminControlConfiguration) async throws -> [SupportTicket] {
        try await request(path: "v1/admin/tickets?limit=100", method: "GET", configuration: configuration)
    }

    func projectRoutes(configuration: AdminControlConfiguration) async throws -> [ProjectRoute] {
        try await request(path: "v1/admin/projects", method: "GET", configuration: configuration)
    }

    func approveTicket(
        ticketID: String,
        projectID: String,
        configuration: AdminControlConfiguration
    ) async throws -> ProjectDispatch {
        try await request(
            path: "v1/admin/tickets/\(ticketID)/approve",
            method: "POST",
            body: SupportTicketApprovalRequest(projectID: projectID),
            configuration: configuration
        )
    }

    func ticket(id: String, configuration: AdminControlConfiguration) async throws -> SupportTicket {
        try await request(path: "v1/admin/tickets/\(id)", method: "GET", configuration: configuration)
    }

    func reply(
        ticketID: String,
        message: String,
        configuration: AdminControlConfiguration
    ) async throws -> SupportTicket {
        try await request(
            path: "v1/admin/tickets/\(ticketID)/messages",
            method: "POST",
            body: SupportTicketMessageRequest(message: message),
            configuration: configuration
        )
    }

    func updateTicketStatus(
        ticketID: String,
        status: String,
        configuration: AdminControlConfiguration
    ) async throws -> SupportTicket {
        try await request(
            path: "v1/admin/tickets/\(ticketID)/status",
            method: "POST",
            body: SupportTicketStatusRequest(status: status),
            configuration: configuration
        )
    }

    func perform(_ action: AdminAction, configuration: AdminControlConfiguration) async throws -> AdminActionReceipt {
        try await request(path: "v1/admin/actions/\(action.rawValue)", method: "POST", configuration: configuration)
    }

    func capabilitiesV2(configuration: AdminControlConfiguration) async throws -> AdminCapabilitiesResponse {
        try await request(path: "v2/admin/capabilities", method: "GET", configuration: configuration)
    }

    func systemsV2(configuration: AdminControlConfiguration) async throws -> [AdminSystemStatusV2] {
        try await request(path: "v2/admin/systems", method: "GET", configuration: configuration)
    }

    func backupsV2(configuration: AdminControlConfiguration) async throws -> [AdminBackupRecordV2] {
        try await request(path: "v2/admin/backups", method: "GET", configuration: configuration)
    }

    func diagnosticsV2(configuration: AdminControlConfiguration) async throws -> AdminDiagnosticResponseV2 {
        try await request(path: "v2/admin/diagnostics", method: "GET", configuration: configuration)
    }

    func logsV2(configuration: AdminControlConfiguration) async throws -> [AdminLogEntryV2] {
        try await request(path: "v2/admin/logs?limit=200", method: "GET", configuration: configuration)
    }

    func workflowsV2(configuration: AdminControlConfiguration) async throws -> [AdminWorkflowSummaryV2] {
        try await request(path: "v2/admin/workflows", method: "GET", configuration: configuration)
    }

    func addonsV2(configuration: AdminControlConfiguration) async throws -> [AdminAddonStatusV2] {
        try await request(path: "v2/admin/addons", method: "GET", configuration: configuration)
    }

    func addonInventoryStatusV2(configuration: AdminControlConfiguration) async throws -> AdminAddonInventoryStatusV2 {
        try await request(path: "v2/admin/addons/status", method: "GET", configuration: configuration)
    }

    func projectsV2(configuration: AdminControlConfiguration) async throws -> [AdminProjectStatusV2] {
        try await request(path: "v2/admin/projects", method: "GET", configuration: configuration)
    }

    func jobsV2(configuration: AdminControlConfiguration) async throws -> [AdminJobStatusV2] {
        try await request(path: "v2/admin/jobs", method: "GET", configuration: configuration)
    }

    func securityV2(configuration: AdminControlConfiguration) async throws -> AdminSecuritySummaryV2 {
        try await request(path: "v2/admin/security", method: "GET", configuration: configuration)
    }

    func credentialsV2(configuration: AdminControlConfiguration) async throws -> [AdminCredentialMetadataV2] {
        try await request(path: "v2/admin/credentials", method: "GET", configuration: configuration)
    }

    func usersV2(configuration: AdminControlConfiguration) async throws -> [AdminUserSummaryV2] {
        try await request(path: "v2/admin/users", method: "GET", configuration: configuration)
    }

    func devicesV2(configuration: AdminControlConfiguration) async throws -> [AdminDeviceSummaryV2] {
        try await request(path: "v2/admin/devices", method: "GET", configuration: configuration)
    }

    func sessionsV2(configuration: AdminControlConfiguration) async throws -> [AdminSessionSummaryV2] {
        try await request(path: "v2/admin/sessions", method: "GET", configuration: configuration)
    }

    func releasesV2(configuration: AdminControlConfiguration) async throws -> [AdminReleaseItemV2] {
        try await request(path: "v2/admin/releases", method: "GET", configuration: configuration)
    }

    func chatStatusV2(configuration: AdminControlConfiguration) async throws -> AdminChatStatusV2 {
        try await request(path: "v2/admin/chat/status", method: "GET", configuration: configuration)
    }

    func chatDevicesV2(configuration: AdminControlConfiguration) async throws -> [AdminChatDeviceV2] {
        try await request(path: "v2/admin/chat/devices", method: "GET", configuration: configuration)
    }

    func eventsV2(since: Int, configuration: AdminControlConfiguration) async throws -> AdminEventFeedV2 {
        try await request(path: "v2/admin/events?since=\(max(0, since))", method: "GET", configuration: configuration)
    }

    func verifyBackupV2(id: String, configuration: AdminControlConfiguration) async throws -> AdminBackupRecordV2 {
        try await request(path: "v2/admin/backups/\(id)/verify", method: "POST", configuration: configuration)
    }

    func runWorkflowV2(
        id: String,
        configuration: AdminControlConfiguration,
        deviceSession: String?
    ) async throws -> AdminWorkflowReceiptV2 {
        var headers: [String: String] = [:]
        if let deviceSession { headers["X-Owner-Device-Session"] = deviceSession }
        return try await request(
            path: "v2/admin/workflows/\(id)/run",
            method: "POST",
            configuration: configuration,
            extraHeaders: headers
        )
    }

    func performV2(
        actionID: String,
        parameters: [String: String] = [:],
        configuration: AdminControlConfiguration,
        deviceSession: String?,
        breakGlassSession: String?
    ) async throws -> AdminActionReceipt {
        var headers: [String: String] = [:]
        if let deviceSession { headers["X-Owner-Device-Session"] = deviceSession }
        if let breakGlassSession { headers["X-Break-Glass-Session"] = breakGlassSession }
        return try await request(
            path: "v2/admin/actions/\(actionID)",
            method: "POST",
            body: parameters,
            configuration: configuration,
            extraHeaders: headers
        )
    }

    func enrollDeviceV2(
        identity: OwnerDeviceIdentity,
        enrollmentSecret: String?,
        configuration: AdminControlConfiguration
    ) async throws -> AdminDeviceEnrollmentV2 {
        var headers: [String: String] = [:]
        if let enrollmentSecret, !enrollmentSecret.isEmpty {
            headers["X-Owner-Enrollment-Secret"] = enrollmentSecret
        }
        return try await request(
            path: "v2/admin/devices/enroll",
            method: "POST",
            body: AdminDeviceEnrollRequestV2(deviceID: identity.deviceID, publicKey: identity.publicKey),
            configuration: configuration,
            extraHeaders: headers
        )
    }

    func deviceChallengeV2(
        deviceID: String,
        purpose: String,
        configuration: AdminControlConfiguration
    ) async throws -> AdminDeviceChallengeV2 {
        try await request(
            path: "v2/admin/devices/challenge",
            method: "POST",
            body: AdminDeviceChallengeRequestV2(deviceID: deviceID, purpose: purpose),
            configuration: configuration
        )
    }

    func verifyDeviceV2(
        deviceID: String,
        challengeID: String,
        signature: String,
        configuration: AdminControlConfiguration
    ) async throws -> AdminDeviceSessionV2 {
        try await request(
            path: "v2/admin/devices/verify",
            method: "POST",
            body: AdminDeviceVerifyRequestV2(deviceID: deviceID, challengeID: challengeID, signature: signature),
            configuration: configuration
        )
    }

    func breakGlassV2(
        deviceID: String,
        challengeID: String,
        signature: String,
        reason: String,
        deviceSession: String,
        configuration: AdminControlConfiguration
    ) async throws -> AdminBreakGlassSessionV2 {
        try await request(
            path: "v2/admin/break-glass/session",
            method: "POST",
            body: AdminBreakGlassRequestV2(
                deviceID: deviceID,
                challengeID: challengeID,
                signature: signature,
                reason: reason
            ),
            configuration: configuration,
            extraHeaders: ["X-Owner-Device-Session": deviceSession]
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        configuration: AdminControlConfiguration,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw AdminControlError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(configuration.ownerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdminControlError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw AdminControlError.forbidden }
        guard (200..<300).contains(http.statusCode) else { throw AdminControlError.rejected(http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        configuration: AdminControlConfiguration,
        extraHeaders: [String: String] = [:]
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw AdminControlError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(configuration.ownerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdminControlError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw AdminControlError.forbidden }
        guard (200..<300).contains(http.statusCode) else { throw AdminControlError.rejected(http.statusCode) }
        return try decoder.decode(Response.self, from: data)
    }
}

@MainActor
@Observable
final class AdminControlModel {
    enum State: Equatable {
        case notConfigured
        case locked
        case unlocking
        case unlocked(AdminIdentity)
        case failed(String)
    }

    var state: State = .notConfigured
    var backendStatus: AdminBackendStatus?
    var auditEvents: [AdminAuditEvent] = []
    var supportTickets: [SupportTicket] = []
    var ticketDetails: [String: SupportTicket] = [:]
    var projectRoutes: [ProjectRoute] = []
    var lastDispatch: ProjectDispatch?
    var isLoading = false
    var lastReceipt: AdminActionReceipt?
    var lastError: String?
    var ownerV2Error: String?
    var v2Capabilities: AdminCapabilitiesResponse?
    var systemStatusesV2: [AdminSystemStatusV2] = []
    var backupsV2: [AdminBackupRecordV2] = []
    var diagnosticsV2: AdminDiagnosticResponseV2?
    var logsV2: [AdminLogEntryV2] = []
    var workflowsV2: [AdminWorkflowSummaryV2] = []
    var addonsV2: [AdminAddonStatusV2] = []
    var addonInventoryStatusV2: AdminAddonInventoryStatusV2?
    var projectsV2: [AdminProjectStatusV2] = []
    var jobsV2: [AdminJobStatusV2] = []
    var securityV2: AdminSecuritySummaryV2?
    var credentialsV2: [AdminCredentialMetadataV2] = []
    var usersV2: [AdminUserSummaryV2] = []
    var devicesV2: [AdminDeviceSummaryV2] = []
    var sessionsV2: [AdminSessionSummaryV2] = []
    var releasesV2: [AdminReleaseItemV2] = []
    var chatStatusV2: AdminChatStatusV2?
    var chatDevicesV2: [AdminChatDeviceV2] = []
    var eventsV2: [AdminEventV2] = []
    var lastWorkflowV2: AdminWorkflowReceiptV2?
    var deviceSessionExpiresAt: Date?
    var deviceBindingPhase: OwnerDeviceBindingPhase = .unavailable
    var breakGlassExpiresAt: Date?

    private let client = AdminControlClient()
    private let endpointKey = "ownerAdminEndpoint"
    private let tokenAccount = "ownerAdminToken"
    private let enrollmentSecretAccount = "ownerDeviceEnrollmentSecret"
    private var configuration: AdminControlConfiguration?
    private var deviceSessionToken: String?
    private var breakGlassSessionToken: String?
    private var lastEventSequence = 0
    private var eventPollingTask: Task<Void, Never>?
    private var statusPollingTask: Task<Void, Never>?
    private var pollingActive = true

    init() {
        restoreConfiguration()
    }

    func configure(endpoint: String, ownerToken: String, enrollmentSecret: String = "") throws {
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", !ownerToken.isEmpty else {
            throw AdminControlError.invalidConfiguration
        }
        if !enrollmentSecret.isEmpty && enrollmentSecret.count < 32 {
            throw AdminControlError.invalidConfiguration
        }
        configuration = .init(baseURL: url, ownerToken: ownerToken)
        UserDefaults.standard.set(url.absoluteString, forKey: endpointKey)
        try KeychainStore.save(ownerToken, account: tokenAccount)
        if enrollmentSecret.isEmpty {
            KeychainStore.delete(account: enrollmentSecretAccount)
        } else {
            try KeychainStore.save(enrollmentSecret, account: enrollmentSecretAccount)
        }
        state = .locked
    }

    func unlock() async {
        guard let configuration else {
            state = .notConfigured
            return
        }
        state = .unlocking
        do {
            try await authenticateOwner(reason: "Geheimen Owner-Bereich öffnen")
            let identity = try await client.identity(configuration: configuration)
            guard identity.role == "owner" else { throw AdminControlError.forbidden }
            state = .unlocked(identity)
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func lock() {
        backendStatus = nil
        auditEvents = []
        supportTickets = []
        ticketDetails = [:]
        projectRoutes = []
        lastDispatch = nil
        resetV2State()
        state = configuration == nil ? .notConfigured : .locked
    }

    func refresh() async {
        guard case .unlocked = state, let configuration else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lastError = nil
            async let status = client.status(configuration: configuration)
            async let audit = client.audit(configuration: configuration)
            async let tickets = client.tickets(configuration: configuration)
            async let routes = client.projectRoutes(configuration: configuration)
            backendStatus = try await status
            auditEvents = try await audit
            supportTickets = try await tickets
            projectRoutes = try await routes
            await refreshV2()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadTicket(_ id: String) async {
        guard case .unlocked = state, let configuration else { return }
        do {
            lastError = nil
            ticketDetails[id] = try await client.ticket(id: id, configuration: configuration)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func replyToTicket(_ id: String, message: String) async -> Bool {
        guard case .unlocked = state, let configuration else { return false }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 4000 else {
            lastError = "Die Antwort muss zwischen 1 und 4.000 Zeichen enthalten."
            return false
        }
        do {
            lastError = nil
            ticketDetails[id] = try await client.reply(
                ticketID: id,
                message: normalized,
                configuration: configuration
            )
            supportTickets = try await client.tickets(configuration: configuration)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func approveTicket(_ id: String, projectID: String) async -> Bool {
        guard case .unlocked = state, let configuration else { return false }
        guard projectRoutes.contains(where: { $0.id == projectID }) else {
            lastError = "Ungültiges Zielprojekt."
            return false
        }
        do {
            lastError = nil
            try await authenticateOwner(reason: "Ticket an \(projectID) freigeben")
            lastDispatch = try await client.approveTicket(
                ticketID: id,
                projectID: projectID,
                configuration: configuration
            )
            ticketDetails[id] = try await client.ticket(id: id, configuration: configuration)
            supportTickets = try await client.tickets(configuration: configuration)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func setTicketStatus(_ id: String, status: String) async {
        guard case .unlocked = state, let configuration else { return }
        do {
            lastError = nil
            ticketDetails[id] = try await client.updateTicketStatus(
                ticketID: id,
                status: status,
                configuration: configuration
            )
            supportTickets = try await client.tickets(configuration: configuration)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func perform(_ action: AdminAction) async {
        guard case .unlocked = state, let configuration else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lastError = nil
            if let capabilities = v2Capabilities,
               let remote = capabilities.actions.first(where: { $0.id == action.rawValue }) {
                guard remote.available else { throw AdminControlError.actionUnavailable }
                if remote.requiresBiometrics { try await authenticateOwner(reason: remote.title) }
                if remote.risk == "sensitive" || remote.requiresBreakGlass {
                    try await ensureDeviceSession()
                }
                if remote.requiresBreakGlass && !hasActiveBreakGlassSession {
                    throw AdminControlError.breakGlassRequired
                }
                lastReceipt = try await client.performV2(
                    actionID: remote.id,
                    configuration: configuration,
                    deviceSession: deviceSessionToken,
                    breakGlassSession: breakGlassSessionToken
                )
            } else {
                if action.requiresFreshBiometrics {
                    try await authenticateOwner(reason: action.title)
                }
                lastReceipt = try await client.perform(action, configuration: configuration)
            }
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshV2() async {
        guard case .unlocked = state, let configuration else { return }
        do {
            let capabilities = try await client.capabilitiesV2(configuration: configuration)
            v2Capabilities = capabilities
            ownerV2Error = nil
            async let systems = client.systemsV2(configuration: configuration)
            async let backups = client.backupsV2(configuration: configuration)
            async let diagnostics = client.diagnosticsV2(configuration: configuration)
            async let logs = client.logsV2(configuration: configuration)
            async let workflows = client.workflowsV2(configuration: configuration)
            async let addons = client.addonsV2(configuration: configuration)
            async let addonInventoryStatus = client.addonInventoryStatusV2(configuration: configuration)
            async let projects = client.projectsV2(configuration: configuration)
            async let jobs = client.jobsV2(configuration: configuration)
            async let security = client.securityV2(configuration: configuration)
            async let credentials = client.credentialsV2(configuration: configuration)
            async let users = client.usersV2(configuration: configuration)
            async let devices = client.devicesV2(configuration: configuration)
            async let sessions = client.sessionsV2(configuration: configuration)
            async let releases = client.releasesV2(configuration: configuration)
            async let chatStatus = client.chatStatusV2(configuration: configuration)
            async let chatDevices = client.chatDevicesV2(configuration: configuration)
            async let events = client.eventsV2(since: lastEventSequence, configuration: configuration)
            systemStatusesV2 = try await systems
            backupsV2 = try await backups
            diagnosticsV2 = try await diagnostics
            logsV2 = try await logs
            workflowsV2 = try await workflows
            addonsV2 = try await addons
            addonInventoryStatusV2 = try await addonInventoryStatus
            projectsV2 = try await projects
            jobsV2 = try await jobs
            securityV2 = try await security
            credentialsV2 = try await credentials
            usersV2 = try await users
            devicesV2 = try await devices
            sessionsV2 = try await sessions
            releasesV2 = try await releases
            chatStatusV2 = try await chatStatus
            chatDevicesV2 = try await chatDevices
            let eventFeed = try await events
            if !eventFeed.events.isEmpty {
                eventsV2.append(contentsOf: eventFeed.events)
                eventsV2 = Array(eventsV2.suffix(200))
            }
            lastEventSequence = eventFeed.lastSequence
            if capabilities.capabilities.contains("events.read") {
                startEventPolling()
            }
            startStatusPolling()
            if capabilities.capabilities.contains("device_binding") {
                do {
                    try await ensureDeviceSession()
                } catch {
                    deviceBindingPhase = .failed(error.localizedDescription)
                }
            } else {
                deviceBindingPhase = .unavailable
            }
        } catch {
            ownerV2Error = error.localizedDescription
            if v2Capabilities == nil {
                resetV2State(preserveError: true)
            }
        }
    }

    func verifyBackupV2(_ id: String) async {
        guard case .unlocked = state, let configuration else { return }
        do {
            lastError = nil
            _ = try await client.verifyBackupV2(id: id, configuration: configuration)
            backupsV2 = try await client.backupsV2(configuration: configuration)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runWorkflowV2(_ workflow: AdminWorkflowSummaryV2) async {
        guard case .unlocked = state, let configuration else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lastError = nil
            if workflow.risk != "safe" { try await authenticateOwner(reason: workflow.title) }
            if workflow.risk == "sensitive" || workflow.risk == "critical" { try await ensureDeviceSession() }
            if workflow.risk == "critical" && !hasActiveBreakGlassSession { throw AdminControlError.breakGlassRequired }
            lastWorkflowV2 = try await client.runWorkflowV2(
                id: workflow.id,
                configuration: configuration,
                deviceSession: deviceSessionToken
            )
            await refreshV2()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func performRemoteActionV2(_ action: AdminRemoteAction, parameters: [String: String] = [:]) async {
        guard case .unlocked = state, let configuration, action.available else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            lastError = nil
            if action.requiresBiometrics { try await authenticateOwner(reason: action.title) }
            if action.risk == "sensitive" || action.requiresBreakGlass { try await ensureDeviceSession() }
            if action.requiresBreakGlass && !hasActiveBreakGlassSession { throw AdminControlError.breakGlassRequired }
            lastReceipt = try await client.performV2(
                actionID: action.id,
                parameters: parameters,
                configuration: configuration,
                deviceSession: deviceSessionToken,
                breakGlassSession: breakGlassSessionToken
            )
            await refreshV2()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openBreakGlass(reason: String) async {
        guard case .unlocked = state, let configuration else { return }
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3 else {
            lastError = "Bitte einen kurzen Grund für Break-Glass angeben."
            return
        }
        do {
            lastError = nil
            try await authenticateOwner(reason: "Break-Glass für 5 Minuten öffnen")
            try await ensureDeviceSession()
            guard let deviceSessionToken else { throw AdminControlError.deviceBindingFailed }
            let identity = try OwnerDeviceBindingStore.identity()
            let challenge = try await client.deviceChallengeV2(
                deviceID: identity.deviceID,
                purpose: "break_glass",
                configuration: configuration
            )
            let signature = try OwnerDeviceBindingStore.sign(challengeBase64: challenge.challenge)
            let session = try await client.breakGlassV2(
                deviceID: identity.deviceID,
                challengeID: challenge.challengeID,
                signature: signature,
                reason: normalized,
                deviceSession: deviceSessionToken,
                configuration: configuration
            )
            breakGlassSessionToken = session.breakGlassSession
            breakGlassExpiresAt = session.expiresAt
            await refreshV2()
        } catch {
            lastError = error.localizedDescription
        }
    }

    var hasActiveBreakGlassSession: Bool {
        guard let breakGlassExpiresAt, breakGlassSessionToken != nil else { return false }
        return breakGlassExpiresAt.timeIntervalSinceNow > 5
    }

    private func ensureDeviceSession() async throws {
        guard let configuration else { throw AdminControlError.invalidConfiguration }
        if let deviceSessionExpiresAt, deviceSessionToken != nil, deviceSessionExpiresAt.timeIntervalSinceNow > 30 {
            deviceBindingPhase = .trusted(deviceSessionExpiresAt)
            return
        }
        guard v2Capabilities?.capabilities.contains("device_binding") == true else {
            deviceBindingPhase = .unavailable
            throw AdminControlError.deviceBindingFailed
        }
        do {
            deviceBindingPhase = .enrolling
            let identity = try OwnerDeviceBindingStore.identity()
            let enrollmentSecret = try? KeychainStore.value(account: enrollmentSecretAccount)
            _ = try await client.enrollDeviceV2(
                identity: identity,
                enrollmentSecret: enrollmentSecret ?? nil,
                configuration: configuration
            )
            KeychainStore.delete(account: enrollmentSecretAccount)
            deviceBindingPhase = .verifying
            let challenge = try await client.deviceChallengeV2(
                deviceID: identity.deviceID,
                purpose: "session",
                configuration: configuration
            )
            let signature = try OwnerDeviceBindingStore.sign(challengeBase64: challenge.challenge)
            let session = try await client.verifyDeviceV2(
                deviceID: identity.deviceID,
                challengeID: challenge.challengeID,
                signature: signature,
                configuration: configuration
            )
            deviceSessionToken = session.deviceSession
            deviceSessionExpiresAt = session.expiresAt
            deviceBindingPhase = .trusted(session.expiresAt)
        } catch {
            deviceSessionToken = nil
            deviceSessionExpiresAt = nil
            deviceBindingPhase = .failed(error.localizedDescription)
            throw error
        }
    }

    func isActionAvailable(_ action: AdminAction) -> Bool {
        guard let capabilities = v2Capabilities,
              let remote = capabilities.actions.first(where: { $0.id == action.rawValue }) else { return true }
        return remote.available
    }

    var canVerifyBackups: Bool {
        v2Capabilities?.capabilities.contains("backups.verify") ?? false
    }

    func setPollingActive(_ active: Bool) {
        pollingActive = active
        if active {
            startEventPolling()
            startStatusPolling()
        } else {
            eventPollingTask?.cancel()
            eventPollingTask = nil
            statusPollingTask?.cancel()
            statusPollingTask = nil
        }
    }

    func refreshStatusV2() async {
        guard case .unlocked = state, let configuration, v2Capabilities != nil else { return }
        do {
            async let status = client.status(configuration: configuration)
            async let systems = client.systemsV2(configuration: configuration)
            async let diagnostics = client.diagnosticsV2(configuration: configuration)
            async let addons = client.addonsV2(configuration: configuration)
            async let addonInventoryStatus = client.addonInventoryStatusV2(configuration: configuration)
            async let projects = client.projectsV2(configuration: configuration)
            async let jobs = client.jobsV2(configuration: configuration)
            async let security = client.securityV2(configuration: configuration)
            async let devices = client.devicesV2(configuration: configuration)
            async let sessions = client.sessionsV2(configuration: configuration)
            async let releases = client.releasesV2(configuration: configuration)
            backendStatus = try await status
            systemStatusesV2 = try await systems
            diagnosticsV2 = try await diagnostics
            addonsV2 = try await addons
            addonInventoryStatusV2 = try await addonInventoryStatus
            projectsV2 = try await projects
            jobsV2 = try await jobs
            securityV2 = try await security
            devicesV2 = try await devices
            sessionsV2 = try await sessions
            releasesV2 = try await releases
            ownerV2Error = nil
        } catch {
            ownerV2Error = error.localizedDescription
        }
    }

    private func startStatusPolling() {
        guard pollingActive, statusPollingTask == nil, v2Capabilities != nil else { return }
        statusPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.refreshStatusV2()
            }
        }
    }

    private func startEventPolling() {
        guard pollingActive, eventPollingTask == nil else { return }
        eventPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.pollEventsV2()
            }
        }
    }

    private func pollEventsV2() async {
        guard case .unlocked = state,
              let configuration,
              v2Capabilities?.capabilities.contains("events.read") == true else { return }
        do {
            let feed = try await client.eventsV2(since: lastEventSequence, configuration: configuration)
            if !feed.events.isEmpty {
                eventsV2.append(contentsOf: feed.events)
                eventsV2 = Array(eventsV2.suffix(200))
            }
            lastEventSequence = feed.lastSequence
        } catch {
            ownerV2Error = error.localizedDescription
        }
    }

    private func resetV2State(preserveError: Bool = false) {
        eventPollingTask?.cancel()
        eventPollingTask = nil
        statusPollingTask?.cancel()
        statusPollingTask = nil
        if !preserveError { ownerV2Error = nil }
        v2Capabilities = nil
        systemStatusesV2 = []
        backupsV2 = []
        diagnosticsV2 = nil
        logsV2 = []
        workflowsV2 = []
        addonsV2 = []
        addonInventoryStatusV2 = nil
        projectsV2 = []
        jobsV2 = []
        securityV2 = nil
        credentialsV2 = []
        usersV2 = []
        devicesV2 = []
        sessionsV2 = []
        releasesV2 = []
        chatStatusV2 = nil
        chatDevicesV2 = []
        eventsV2 = []
        lastWorkflowV2 = nil
        deviceSessionToken = nil
        deviceSessionExpiresAt = nil
        deviceBindingPhase = .unavailable
        breakGlassSessionToken = nil
        breakGlassExpiresAt = nil
        lastEventSequence = 0
    }

    func removeConfiguration() {
        configuration = nil
        UserDefaults.standard.removeObject(forKey: endpointKey)
        KeychainStore.delete(account: tokenAccount)
        KeychainStore.delete(account: enrollmentSecretAccount)
        backendStatus = nil
        auditEvents = []
        supportTickets = []
        ticketDetails = [:]
        projectRoutes = []
        lastDispatch = nil
        lastError = nil
        resetV2State()
        state = .notConfigured
    }

    private func restoreConfiguration() {
        guard let endpoint = UserDefaults.standard.string(forKey: endpointKey),
              let url = URL(string: endpoint),
              let token = try? KeychainStore.value(account: tokenAccount),
              !token.isEmpty else { return }
        configuration = .init(baseURL: url, ownerToken: token)
        state = .locked
    }

    private func authenticateOwner(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AdminControlError.biometricAuthenticationFailed
        }
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
        guard success else { throw AdminControlError.biometricAuthenticationFailed }
    }
}
