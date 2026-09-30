import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ConnectionState: Equatable {
        case notConfigured
        case connecting
        case connected
        case reconnecting(Int)
        case failed(String)

        var statusText: String {
            switch self {
            case .notConfigured: "Nicht verbunden"
            case .connecting: "Verbinde …"
            case .connected: "Verbunden"
            case .reconnecting: "Verbindung wird wiederhergestellt …"
            case .failed: "Verbindung fehlgeschlagen"
            }
        }
    }

    var selectedProfile: HomeProfile = .nico
    var connectionState: ConnectionState = .notConfigured
    var entities: [HomeAssistantEntity] = []
    var floors: [HomeAssistantFloor] = []
    var areas: [HomeAssistantArea] = []
    var devices: [HomeAssistantDevice] = []
    var entityRegistry: [HomeAssistantRegistryEntity] = []
    var isPresentingConnection = false
    var activeActionEntityIDs: Set<String> = []
    var lastActionError: String?
    private(set) var homeAssistantCurrentUser: HomeAssistantCurrentUser?

    private let client: HomeAssistantClient
    private let oauthService = HomeAssistantOAuthService()
    private let serverURLKey = "homeAssistantServerURL"
    private let tokenAccount = "homeAssistantDeveloperToken"
    private let oauthCredentialAccount = "homeAssistantOAuthCredential"
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var currentConfiguration: HomeAssistantConfiguration?
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var entityIndexByID: [String: Int] = [:]
    private var pendingStateChanges: [String: HomeAssistantStateChange] = [:]
    private var stateFlushTask: Task<Void, Never>?
    private var networkAvailable = true
    private var applicationIsActive = true

    init(client: HomeAssistantClient = HomeAssistantClient()) {
        self.client = client
    }

    var isConnected: Bool {
        switch connectionState {
        case .connected, .reconnecting: true
        default: false
        }
    }

    var profileDefinition: ProfileDefinition {
        ProfileCatalog.definition(for: selectedProfile)
    }

    var profileFavorites: [HomeAssistantEntity] {
        let explicit = profileDefinition.favoriteEntityIDs.compactMap { requestedID in
            if let index = entityIndexByID[requestedID], entities.indices.contains(index) {
                return entities[index]
            }
            return entities.first { $0.entityID == requestedID }
        }
        guard explicit.isEmpty else { return explicit }
        let areaIDs = Set(areas.filter { area in
            profileDefinition.roomNames.contains { room in
                area.name.localizedCaseInsensitiveCompare(room) == .orderedSame
            }
        }.map(\.id))
        return areaIDs
            .flatMap(entities(inArea:))
            .filter { $0.controlKind != .readOnly }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .prefix(6)
            .map { $0 }
    }

    func restoreConnection() async {
        if let credential = try? oauthCredential() {
            do {
                let refreshed = try await oauthService.refresh(credential)
                try saveOAuthCredential(refreshed)
                await connect(
                    serverURL: refreshed.configuration.instanceURL,
                    accessToken: refreshed.accessToken,
                    persist: false,
                    failurePrefix: "WebSocket-Verbindung nach OAuth fehlgeschlagen"
                )
                return
            } catch {
                connectionState = .failed(error.localizedDescription)
                return
            }
        }
        guard
            let address = UserDefaults.standard.string(forKey: serverURLKey),
            let url = URL(string: address),
            let token = try? KeychainStore.value(account: tokenAccount),
            !token.isEmpty
        else { return }
        await connect(serverURL: url, accessToken: token, persist: false)
    }

    func connectOAuth(using configuration: HomeAssistantOAuthConfiguration) async {
        connectionState = .connecting
        do {
            let tokens = try await oauthService.authorize(using: configuration)
            let credential = HomeAssistantOAuthCredential(
                configuration: configuration,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: Date().addingTimeInterval(tokens.expiresIn)
            )
            try saveOAuthCredential(credential)
            KeychainStore.delete(account: tokenAccount)
            UserDefaults.standard.removeObject(forKey: serverURLKey)
            await connect(
                serverURL: configuration.instanceURL,
                accessToken: credential.accessToken,
                persist: false,
                failurePrefix: "WebSocket-Verbindung nach OAuth fehlgeschlagen"
            )
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func connect(
        serverURL: URL,
        accessToken: String,
        persist: Bool = true,
        failurePrefix: String? = nil
    ) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        eventTask?.cancel()
        eventTask = nil
        stateFlushTask?.cancel()
        stateFlushTask = nil
        pendingStateChanges.removeAll()
        connectionState = .connecting
        let configuration = HomeAssistantConfiguration(baseURL: serverURL, accessToken: accessToken)
        do {
            let snapshot = try await client.connect(configuration: configuration)
            currentConfiguration = configuration
            shouldReconnect = true
            reconnectAttempt = 0
            apply(snapshot)
            homeAssistantCurrentUser = snapshot.currentUser
            connectionState = .connected
            isPresentingConnection = false
            observeStateChanges()
            if persist {
                UserDefaults.standard.set(serverURL.absoluteString, forKey: serverURLKey)
                try KeychainStore.save(accessToken, account: tokenAccount)
            }
        } catch {
            let message = error.localizedDescription
            connectionState = .failed(
                failurePrefix.map { "\($0): \(message)" } ?? message
            )
        }
    }

    func chatBootstrapIdentityContext() async throws -> (baseURL: URL, accessToken: String, userID: String) {
        guard let configuration = currentConfiguration else { throw HomeAssistantClientError.disconnected }
        let identity = try await client.currentUserIdentity()
        return (configuration.baseURL, configuration.accessToken, identity.id)
    }

    func disconnect() {
        shouldReconnect = false
        currentConfiguration = nil
        eventTask?.cancel()
        eventTask = nil
        stateFlushTask?.cancel()
        stateFlushTask = nil
        pendingStateChanges.removeAll()
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await client.disconnect() }
        entities = []
        floors = []
        areas = []
        devices = []
        entityRegistry = []
        entityIndexByID.removeAll()
        homeAssistantCurrentUser = nil
        connectionState = .notConfigured
    }

    func refresh() async {
        if let credential = try? oauthCredential() {
            do {
                let refreshed = try await oauthService.refresh(credential)
                try saveOAuthCredential(refreshed)
                await connect(
                    serverURL: refreshed.configuration.instanceURL,
                    accessToken: refreshed.accessToken,
                    persist: false,
                    failurePrefix: "WebSocket-Verbindung nach OAuth fehlgeschlagen"
                )
                return
            } catch {
                connectionState = .failed(error.localizedDescription)
                return
            }
        }
        guard
            let address = UserDefaults.standard.string(forKey: serverURLKey),
            let url = URL(string: address),
            let token = try? KeychainStore.value(account: tokenAccount),
            !token.isEmpty
        else {
            connectionState = .notConfigured
            return
        }
        await connect(serverURL: url, accessToken: token, persist: false)
    }

    func forgetConnection() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: serverURLKey)
        KeychainStore.delete(account: tokenAccount)
        KeychainStore.delete(account: oauthCredentialAccount)
    }

    func chatBootstrapContext() -> ChatBootstrapContext? {
        guard let configuration = currentConfiguration, let user = homeAssistantCurrentUser else { return nil }
        return ChatBootstrapContext(
            homeAssistantBaseURL: configuration.baseURL,
            homeAssistantAccessToken: configuration.accessToken,
            homeAssistantUserID: user.id,
            displayName: user.name
        )
    }

    nonisolated static func toggleServiceDomain(for entity: HomeAssistantEntity) -> String {
        entity.domain == "group" ? "homeassistant" : entity.domain
    }

    func toggle(_ entity: HomeAssistantEntity) async {
        let service: String
        let optimisticState: String
        if entity.domain == "lock" {
            service = entity.state == "locked" ? "unlock" : "lock"
            optimisticState = service == "lock" ? "locked" : "unlocked"
        } else {
            service = entity.isOn ? "turn_off" : "turn_on"
            optimisticState = service == "turn_on" ? "on" : "off"
        }
        let serviceDomain = Self.toggleServiceDomain(for: entity)
        await performService(
            domain: serviceDomain,
            service: service,
            entity: entity,
            optimisticState: optimisticState,
            feedback: .stateChanged
        )
    }

    func activate(_ scene: HomeAssistantEntity) async {
        await performService(domain: "scene", service: "turn_on", entity: scene, feedback: .success)
    }

    func setBrightness(_ value: Double, for light: HomeAssistantEntity) async {
        await performService(
            domain: "light",
            service: "turn_on",
            entity: light,
            data: ["brightness_pct": .number((min(max(value, 0), 1) * 100).rounded())],
            optimisticState: "on"
        )
    }

    func callService(
        for entity: HomeAssistantEntity,
        service: String,
        data: [String: Any] = [:]
    ) async {
        let converted = data.compactMapValues(Self.jsonValue(from:))
        await performService(domain: entity.domain, service: service, entity: entity, data: converted)
    }

    func setRGBColor(_ color: HomeAssistantLightColor, for light: HomeAssistantEntity) async {
        let rgb = [color.red, color.green, color.blue].map { Double(Int((min(max($0, 0), 1) * 255).rounded())) }
        await performService(
            domain: "light", service: "turn_on", entity: light,
            data: ["rgb_color": .array(rgb.map(JSONValue.number))], optimisticState: "on"
        )
    }

    func setColorTemperatureKelvin(_ value: Double, for light: HomeAssistantEntity) async {
        await performService(
            domain: "light", service: "turn_on", entity: light,
            data: ["color_temp_kelvin": .number(value.rounded())], optimisticState: "on"
        )
    }

    func setEffect(_ effect: String, for light: HomeAssistantEntity) async {
        await performService(
            domain: "light", service: "turn_on", entity: light,
            data: ["effect": .string(effect)], optimisticState: "on"
        )
    }


    func lightSegmentBridge(for light: HomeAssistantEntity) -> LightSegmentBridgeSnapshot? {
        guard light.domain == "light" else { return nil }
        return entities
            .compactMap(\.lightSegmentBridgeSnapshot)
            .first { $0.sourceEntityID == light.entityID && $0.isReady }
    }

    func setLightSegments(
        indices: [Int],
        hue: Double,
        saturation: Double,
        brightness: Double,
        for light: HomeAssistantEntity
    ) async {
        guard light.isAvailable,
              let bridge = lightSegmentBridge(for: light),
              bridge.isReady,
              !indices.isEmpty,
              !activeActionEntityIDs.contains(light.entityID)
        else { return }

        let unique = Array(Set(indices)).sorted()
        let allowed = Set(bridge.segmentIndices)
        guard Set(unique).isSubset(of: allowed) else {
            lastActionError = "Ungültige Segmentauswahl."
            return
        }

        activeActionEntityIDs.insert(light.entityID)
        lastActionError = nil
        defer { activeActionEntityIDs.remove(light.entityID) }
        do {
            try await client.callService(
                domain: "battletron_segments",
                service: "set_segments",
                serviceData: [
                    "entity_id": .string(light.entityID),
                    "indices": .array(unique.map { .number(Double($0)) }),
                    "hue": .number(min(max(hue, 0), 360)),
                    "saturation": .number(min(max(saturation, 0), 100)),
                    "brightness": .number(min(max(brightness, 0), 100))
                ]
            )
        } catch {
            lastActionError = error.localizedDescription
        }
    }

    func callFireTVCompanionService(
        _ service: String,
        for player: HomeAssistantEntity,
        data: [String: Any] = [:]
    ) async {
        guard isFireTVCompanion(player), player.isAvailable else { return }
        lastActionError = nil
        var serviceData = data.compactMapValues(Self.jsonValue(from:))
        serviceData["entity_id"] = .string(player.entityID)
        do {
            try await client.callService(
                domain: "firetv_companion",
                service: service,
                serviceData: serviceData
            )
            IOSNextFeedbackCenter.shared.play(.stateChanged)
        } catch {
            lastActionError = error.localizedDescription
            IOSNextFeedbackCenter.shared.play(.error)
        }
    }

    func launchFireTVApp(packageName: String, for player: HomeAssistantEntity) async {
        await callFireTVCompanionService(
            "launch_app",
            for: player,
            data: ["package_name": packageName]
        )
    }

    func mediaCommand(_ service: String, for player: HomeAssistantEntity) async {
        await performService(domain: "media_player", service: service, entity: player, feedback: .stateChanged)
    }

    func setVolume(_ value: Double, for player: HomeAssistantEntity) async {
        await performService(
            domain: "media_player",
            service: "volume_set",
            entity: player,
            data: ["volume_level": .number(min(max(value, 0), 1))]
        )
    }

    func seek(to seconds: Double, for player: HomeAssistantEntity) async {
        await performService(
            domain: "media_player",
            service: "media_seek",
            entity: player,
            data: ["seek_position": .number(max(seconds, 0))]
        )
    }

    func seekRelative(_ offset: Double, for player: HomeAssistantEntity) async {
        let current = player.mediaPosition ?? 0
        await seek(to: max(0, current + offset), for: player)
    }

    func setLocked(_ locked: Bool, for entity: HomeAssistantEntity) async {
        await performService(domain: "lock", service: locked ? "lock" : "unlock", entity: entity, feedback: .criticalConfirmation)
    }

    func activateScript(_ script: HomeAssistantEntity) async {
        await performService(domain: "script", service: "turn_on", entity: script, feedback: .success)
    }

    func coverCommand(_ service: String, for cover: HomeAssistantEntity) async {
        await performService(domain: "cover", service: service, entity: cover, feedback: .stateChanged)
    }

    func setCoverPosition(_ value: Double, for cover: HomeAssistantEntity) async {
        await performService(
            domain: "cover",
            service: "set_cover_position",
            entity: cover,
            data: ["position": .number((min(max(value, 0), 1) * 100).rounded())]
        )
    }

    func setTemperature(_ value: Double, for climate: HomeAssistantEntity) async {
        await performService(
            domain: "climate",
            service: "set_temperature",
            entity: climate,
            data: ["temperature": .number(value)]
        )
    }

    func dismissActionError() {
        lastActionError = nil
    }

    func monitorNetworkChanges() async {
        for await available in NetworkReachability.statuses() {
            guard !Task.isCancelled else { return }
            handleNetworkAvailability(available)
        }
    }

    func setApplicationActive(_ active: Bool) {
        applicationIsActive = active
        if active {
            if shouldReconnect, currentConfiguration != nil, !isConnected {
                scheduleReconnect(immediate: true)
            }
        } else {
            reconnectTask?.cancel()
            reconnectTask = nil
        }
    }

    func entities(inDomain domain: String) -> [HomeAssistantEntity] {
        entities.filter { $0.entityID.hasPrefix("\(domain).") }
    }

    func isFireTVCompanion(_ entity: HomeAssistantEntity) -> Bool {
        if let registry = entityRegistry.first(where: { $0.entityID == entity.entityID }),
           registry.platform?.localizedCaseInsensitiveCompare("firetv_companion") == .orderedSame {
            return true
        }
        return entity.isFireTVCompanion
    }

    func mediaPlayersForPresentation(inArea areaID: String) -> [HomeAssistantEntity] {
        let candidates = entities(inArea: areaID).filter { $0.domain == "media_player" }
        let hasCompanion = candidates.contains(where: isFireTVCompanion)
        guard hasCompanion else { return candidates }
        let shadowPlatforms: Set<String> = ["androidtv", "androidtv_remote", "homekit_controller"]
        return candidates.filter { entity in
            if isFireTVCompanion(entity) { return true }
            let platform = entityRegistry.first(where: { $0.entityID == entity.entityID })?.platform?.lowercased()
            return platform.map { !shadowPlatforms.contains($0) } ?? true
        }
    }

    func fireTVCompanion(inArea areaID: String) -> HomeAssistantEntity? {
        entities(inArea: areaID)
            .first(where: isFireTVCompanion)
    }

    func isShadowedByFireTVCompanion(_ entity: HomeAssistantEntity) -> Bool {
        guard let areaID = areaID(for: entity) else { return false }
        return !mediaPlayersForPresentation(inArea: areaID).contains(where: { $0.entityID == entity.entityID })
    }

    func resolvedAreaID(for entityID: String) -> String? {
        guard let registry = entityRegistry.first(where: { $0.entityID == entityID }) else { return nil }
        if let areaID = registry.areaID, !areaID.isEmpty { return areaID }
        guard let deviceID = registry.deviceID else { return nil }
        return devices.first(where: { $0.id == deviceID })?.areaID
    }

    private func areaID(for entity: HomeAssistantEntity) -> String? {
        resolvedAreaID(for: entity.entityID)
    }

    func areas(inFloor floorID: String) -> [HomeAssistantArea] {
        areas.filter { $0.isAppRoom && $0.floorID == floorID }
            .sorted { $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending }
    }

    var appAreasWithoutFloor: [HomeAssistantArea] {
        areas.filter { $0.isAppRoom && $0.floorID == nil }
            .sorted { $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending }
    }

    func devices(inArea areaID: String) -> [HomeAssistantDevice] {
        var ids = Set(devices.filter { $0.areaID == areaID }.map(\.id))
        for registry in entityRegistry where resolvedAreaID(for: registry.entityID) == areaID {
            if let deviceID = registry.deviceID { ids.insert(deviceID) }
        }
        return devices.filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    var unassignedDevices: [HomeAssistantDevice] {
        devices.filter { $0.areaID == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var unassignedEntities: [HomeAssistantEntity] {
        let devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let registryByID = Dictionary(uniqueKeysWithValues: entityRegistry.map { ($0.entityID, $0) })
        return entities.filter { entity in
            guard let registry = registryByID[entity.entityID] else { return true }
            if registry.areaID != nil { return false }
            if let deviceID = registry.deviceID, devicesByID[deviceID]?.areaID != nil { return false }
            return true
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var serviceLikeEntities: [HomeAssistantEntity] {
        let domains: Set<String> = [
            "automation", "button", "input_boolean", "light", "lock", "media_player",
            "notify", "number", "remote", "scene", "script", "select", "switch", "tts"
        ]
        return entities.filter { domains.contains($0.domain) }
            .sorted { lhs, rhs in
                lhs.domain == rhs.domain
                    ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                    : lhs.domain < rhs.domain
            }
    }

    func entities(forDevice deviceID: String) -> [HomeAssistantEntity] {
        let entityIDs = Set(entityRegistry.filter { $0.deviceID == deviceID }.map(\.entityID))
        return entities.filter { entityIDs.contains($0.entityID) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func directlyAssignedEntities(inArea areaID: String) -> [HomeAssistantEntity] {
        let entityIDs = Set(entityRegistry.filter { $0.areaID == areaID }.map(\.entityID))
        return entities.filter { entityIDs.contains($0.entityID) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func entities(inArea areaID: String) -> [HomeAssistantEntity] {
        entities.filter { resolvedAreaID(for: $0.entityID) == areaID }
    }

    private func observeStateChanges() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await client.stateChanges()
            for await change in stream {
                guard !Task.isCancelled else { return }
                enqueue(change)
            }
            guard !Task.isCancelled else { return }
            connectionState = .connecting
            // An established session drop gets one immediate retry. If that
            // attempt fails, scheduleReconnect() applies exponential backoff.
            scheduleReconnect(immediate: true)
        }
    }

    private func enqueue(_ change: HomeAssistantStateChange) {
        pendingStateChanges[change.entityID] = change
        guard stateFlushTask == nil else { return }
        stateFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self else { return }
            flushStateChanges()
        }
    }

    private func flushStateChanges() {
        let changes = Array(pendingStateChanges.values)
        pendingStateChanges.removeAll(keepingCapacity: true)
        stateFlushTask = nil
        var requiresReindex = false
        var removedEntityIDs: Set<String> = []

        for change in changes {
            if let newState = change.newState {
                if let index = entityIndexByID[change.entityID], entities.indices.contains(index) {
                    entities[index] = newState
                } else {
                    entities.append(newState)
                    requiresReindex = true
                }
            } else {
                removedEntityIDs.insert(change.entityID)
            }
        }

        if !removedEntityIDs.isEmpty {
            entities.removeAll { removedEntityIDs.contains($0.entityID) }
            requiresReindex = true
        }

        if requiresReindex {
            sortEntities()
        }
    }

    nonisolated static func reconnectDelaySeconds(attempt: Int, jitterFraction: Double) -> Double {
        let base = min(pow(2.0, Double(max(attempt, 1) - 1)), 30)
        let boundedJitter = min(max(jitterFraction, -0.2), 0.2)
        return max(0.25, base * (1 + boundedJitter))
    }

    private func scheduleReconnect(immediate: Bool = false) {
        guard shouldReconnect,
              currentConfiguration != nil,
              applicationIsActive,
              networkAvailable else { return }

        connectionState = reconnectAttempt > 0 ? .reconnecting(reconnectAttempt) : .connecting
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            reconnectAttempt += 1
            if !immediate {
                let jitter = Double.random(in: -0.2...0.2)
                let seconds = Self.reconnectDelaySeconds(
                    attempt: reconnectAttempt,
                    jitterFraction: jitter
                )
                try? await Task.sleep(for: .seconds(seconds))
            }
            guard !Task.isCancelled,
                  shouldReconnect,
                  applicationIsActive,
                  networkAvailable,
                  let configuration = currentConfiguration else { return }
            do {
                let snapshot = try await client.connect(configuration: configuration)
                apply(snapshot)
                reconnectAttempt = 0
                connectionState = .connected
                observeStateChanges()
            } catch {
                guard !Task.isCancelled else { return }
                lastActionError = "Erneute Verbindung fehlgeschlagen: \(error.localizedDescription)"
                scheduleReconnect()
            }
        }
    }

    private func handleNetworkAvailability(_ available: Bool) {
        guard networkAvailable != available else { return }
        networkAvailable = available

        if available {
            if shouldReconnect, currentConfiguration != nil, !isConnected, applicationIsActive {
                scheduleReconnect(immediate: true)
            }
        } else {
            reconnectTask?.cancel()
            reconnectTask = nil
            guard shouldReconnect, currentConfiguration != nil else { return }
            connectionState = .connecting
            Task { await client.disconnect() }
        }
    }

    private func replaceEntities(with states: [HomeAssistantEntity]) {
        entities = states
        sortEntities()
    }

    private func sortEntities() {
        entities.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        entityIndexByID = Dictionary(uniqueKeysWithValues: entities.enumerated().map { ($0.element.entityID, $0.offset) })
    }

    private func performService(
        domain: String,
        service: String,
        entity: HomeAssistantEntity,
        data: [String: JSONValue] = [:],
        optimisticState: String? = nil,
        feedback: IOSNextFeedbackEvent? = nil
    ) async {
        guard entity.isAvailable, !activeActionEntityIDs.contains(entity.entityID) else { return }
        activeActionEntityIDs.insert(entity.entityID)
        lastActionError = nil
        defer { activeActionEntityIDs.remove(entity.entityID) }

        do {
            try await client.callService(
                domain: domain,
                service: service,
                targetEntityID: entity.entityID,
                serviceData: data
            )
            if let optimisticState,
               let index = entities.firstIndex(where: { $0.id == entity.id }) {
                entities[index] = entity.updating(state: optimisticState)
            }
            if let feedback {
                IOSNextFeedbackCenter.shared.play(feedback)
            }
        } catch {
            lastActionError = error.localizedDescription
            IOSNextFeedbackCenter.shared.play(.error)
        }
    }

    private func apply(_ snapshot: HomeAssistantSnapshot) {
        replaceEntities(with: snapshot.states)
        floors = snapshot.floors
        areas = snapshot.areas
        devices = snapshot.devices
        entityRegistry = snapshot.entityRegistry
    }

    private nonisolated static func jsonValue(from value: Any) -> JSONValue? {
        switch value {
        case let value as String: .string(value)
        case let value as Bool: .bool(value)
        case let value as Int: .number(Double(value))
        case let value as Double: .number(value)
        case let value as Float: .number(Double(value))
        case let value as [String: Any]: .object(value.compactMapValues(jsonValue(from:)))
        case let value as [Any]: .array(value.compactMap(jsonValue(from:)))
        case is NSNull: .null
        default: nil
        }
    }

    private func oauthCredential() throws -> HomeAssistantOAuthCredential? {
        guard let data = try KeychainStore.data(account: oauthCredentialAccount) else { return nil }
        return try JSONDecoder().decode(HomeAssistantOAuthCredential.self, from: data)
    }

    private func saveOAuthCredential(_ credential: HomeAssistantOAuthCredential) throws {
        try KeychainStore.save(JSONEncoder().encode(credential), account: oauthCredentialAccount)
    }
}
