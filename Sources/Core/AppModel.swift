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
    private(set) var searchRevision: UInt64 = 0
    var floors: [HomeAssistantFloor] = []
    var areas: [HomeAssistantArea] = []
    var devices: [HomeAssistantDevice] = [] {
        didSet { invalidateHomeAssistantLookupIndex() }
    }
    var entityRegistry: [HomeAssistantRegistryEntity] = [] {
        didSet { invalidateHomeAssistantLookupIndex() }
    }
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
    private var entityIDsByDomain: [String: [String]] = [:]
    @ObservationIgnored var registryIndexCache: HomeAssistantLookupIndex?
    private var pendingStateChanges: [String: HomeAssistantStateChange] = [:]
    private var stateFlushTask: Task<Void, Never>?
    @ObservationIgnored private let deviceCommands = EntityCommandPipeline()
    private var entityStateRevisions: [String: UInt64] = [:]
    private var connectionGeneration: UInt64 = 0
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

    /// Captured by delayed UI commands so a value queued for an old connection
    /// can never be sent after disconnect or reconnect.
    var commandGenerationToken: UInt64 { connectionGeneration }

    private var acceptsDeviceCommands: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    func isCurrentCommandGeneration(_ token: UInt64) -> Bool {
        token == connectionGeneration
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
        let trace = IOSNextPerformance.begin("HA.Connect")
        defer { IOSNextPerformance.end("HA.Connect", trace) }
        connectionGeneration &+= 1
        let connectGeneration = connectionGeneration
        deviceCommands.invalidatePending()
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
            guard connectGeneration == connectionGeneration, !Task.isCancelled else {
                return
            }
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
            guard connectGeneration == connectionGeneration, !Task.isCancelled else { return }
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
        connectionGeneration &+= 1
        deviceCommands.invalidatePending()
        entityStateRevisions.removeAll()
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
        entityIDsByDomain.removeAll()
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
        guard acceptsDeviceCommands, light.isAvailable,
              let bridge = lightSegmentBridge(for: light),
              bridge.isReady,
              !indices.isEmpty
        else { return }

        let unique = Array(Set(indices)).sorted()
        let allowed = Set(bridge.segmentIndices)
        guard Set(unique).isSubset(of: allowed) else {
            lastActionError = "Ungültige Segmentauswahl."
            return
        }

        let generation = connectionGeneration
        let entityID = light.entityID
        let commandTrace = IOSNextPerformance.begin("HA.SegmentCommand")
        defer { IOSNextPerformance.end("HA.SegmentCommand", commandTrace) }
        let commandResult = await deviceCommands.execute(entityID: entityID, coalescingKey: "light.appearance") { [self] in
            guard generation == connectionGeneration,
                  entity(withID: entityID)?.isAvailable == true,
                  lightSegmentBridge(for: entity)?.isReady == true else { return .cancelled }
            activeActionEntityIDs.insert(entityID)
            lastActionError = nil
            defer { activeActionEntityIDs.remove(entityID) }
            do {
                try await client.callService(
                    domain: "battletron_segments",
                    service: "set_segments",
                    serviceData: [
                        "entity_id": .string(entityID),
                        "indices": .array(unique.map { .number(Double($0)) }),
                        "hue": .number(min(max(hue, 0), 360)),
                        "saturation": .number(min(max(saturation, 0), 100)),
                        "brightness": .number(min(max(brightness, 0), 100))
                    ]
                )
                return generation == connectionGeneration ? .executed : .outcomeUnknown("Verbindung wechselte während der Segmentaktion.")
            } catch {
                if generation == connectionGeneration {
                    lastActionError = error.localizedDescription
                    IOSNextFeedbackCenter.shared.play(.error)
                    return .outcomeUnknown(error.localizedDescription)
                }
                return .outcomeUnknown("Verbindung wechselte während der Segmentaktion.")
            }
        }
        reportCommandResult(commandResult, entityID: entityID, generation: generation)
    }

    func callFireTVCompanionService(
        _ service: String,
        for player: HomeAssistantEntity,
        data: [String: Any] = [:]
    ) async {
        guard acceptsDeviceCommands, isFireTVCompanion(player), player.isAvailable else {
            lastActionError = "Fire TV ist nicht verbunden oder nicht verfügbar."
            return
        }
        lastActionError = nil
        var serviceData = data.compactMapValues(Self.jsonValue(from:))
        serviceData["entity_id"] = .string(player.entityID)
        let entityID = player.entityID
        let generation = connectionGeneration
        let result = await deviceCommands.execute(entityID: entityID) { [self] in
            guard generation == connectionGeneration, acceptsDeviceCommands,
                  let live = entity(withID: entityID), live.isAvailable,
                  isFireTVCompanion(live) else { return .cancelled }
            do {
                try await client.callService(
                    domain: "firetv_companion", service: service, serviceData: serviceData
                )
                guard generation == connectionGeneration else {
                    return .outcomeUnknown("Verbindung wechselte während der Fire-TV-Aktion.")
                }
                IOSNextFeedbackCenter.shared.play(.stateChanged)
                return .executed
            } catch {
                if generation == connectionGeneration {
                    lastActionError = error.localizedDescription
                    IOSNextFeedbackCenter.shared.play(.error)
                }
                return .outcomeUnknown(error.localizedDescription)
            }
        }
        reportCommandResult(result, entityID: entityID, generation: generation)
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
        if !entityIndexByID.isEmpty {
            return entityIDsByDomain[domain, default: []].compactMap(entity(withID:))
        }
        // Preview/fixture models may inject entities directly before a real HA
        // snapshot builds indexes. Keep that path correct without adding a full
        // scan to normal connected runtime reads.
        return entities.filter { $0.domain == domain }
    }

    func isFireTVCompanion(_ entity: HomeAssistantEntity) -> Bool {
        if let registry = indexedRegistryEntity(for: entity.entityID),
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
            let platform = indexedRegistryEntity(for: entity.entityID)?.platform?.lowercased()
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
        indexedResolvedAreaID(for: entityID)
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
        indexedDevices(inArea: areaID)
    }

    var unassignedDevices: [HomeAssistantDevice] {
        devices.filter { $0.areaID == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var unassignedEntities: [HomeAssistantEntity] {
        entities.filter { resolvedAreaID(for: $0.entityID) == nil }
            .sorted {
                let order = $0.displayName.localizedStandardCompare($1.displayName)
                return order == .orderedSame ? $0.entityID < $1.entityID : order == .orderedAscending
            }
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
        homeAssistantLookupIndex.entityIDsByDeviceID[deviceID, default: []]
            .compactMap(entity(withID:))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func directlyAssignedEntities(inArea areaID: String) -> [HomeAssistantEntity] {
        let entityIDs = Set(entityRegistry.filter { $0.areaID == areaID }.map(\.entityID))
        return entities.filter { entityIDs.contains($0.entityID) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Constant-time entity resolution after sortEntities builds the ID index.
    /// Avoid repeating linear array searches on every light/room redraw.
    func entity(withID entityID: String) -> HomeAssistantEntity? {
        if let index = entityIndexByID[entityID],
           entities.indices.contains(index),
           entities[index].entityID == entityID {
            return entities[index]
        }
        // A just-injected fixture or an initial restore can precede index
        // construction. Preserve correctness without caching a stale match.
        return entities.first { $0.entityID == entityID }
    }

    func entities(inArea areaID: String) -> [HomeAssistantEntity] {
        indexedEntities(inArea: areaID)
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
            connectionGeneration &+= 1
            deviceCommands.invalidatePending()
            entityStateRevisions.removeAll()
            stateFlushTask?.cancel()
            stateFlushTask = nil
            pendingStateChanges.removeAll()
            connectionState = .connecting
            // An established session drop invalidates outstanding writes before
            // reconnecting. Their server-side outcome may remain unknown.
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
        let trace = IOSNextPerformance.begin("HA.FlushStateChanges")
        defer { IOSNextPerformance.end("HA.FlushStateChanges", trace) }
        let changes = Array(pendingStateChanges.values)
        pendingStateChanges.removeAll(keepingCapacity: true)
        stateFlushTask = nil
        var requiresReindex = false
        var removedEntityIDs: Set<String> = []

        for change in changes {
            entityStateRevisions[change.entityID, default: 0] &+= 1
            if let newState = change.newState {
                if let index = entityIndexByID[change.entityID], entities.indices.contains(index) {
                    if entities[index].displayName != newState.displayName {
                        requiresReindex = true
                    }
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
        } else if !changes.isEmpty {
            // Search includes a bounded state-text field, so refresh its
            // debounced snapshot after grouped WebSocket state changes.
            searchRevision &+= 1
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
            let reconnectGeneration = connectionGeneration
            do {
                let snapshot = try await client.connect(configuration: configuration)
                guard !Task.isCancelled,
                      reconnectGeneration == connectionGeneration,
                      shouldReconnect, applicationIsActive, networkAvailable else { return }
                apply(snapshot)
                reconnectAttempt = 0
                connectionState = .connected
                observeStateChanges()
            } catch {
                guard !Task.isCancelled,
                      reconnectGeneration == connectionGeneration,
                      shouldReconnect else { return }
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
            connectionGeneration &+= 1
            deviceCommands.invalidatePending()
            entityStateRevisions.removeAll()
            stateFlushTask?.cancel()
            stateFlushTask = nil
            pendingStateChanges.removeAll()
            eventTask?.cancel()
            eventTask = nil
            guard shouldReconnect, currentConfiguration != nil else {
                Task { await client.disconnect() }
                return
            }
            connectionState = .connecting
            Task { await client.disconnect() }
        }
    }

    private func replaceEntities(with states: [HomeAssistantEntity]) {
        entityStateRevisions.removeAll()
        entities = states
        sortEntities()
    }

    private func sortEntities() {
        // A reload can briefly contain duplicate entity IDs. Deduplicate before
        // building indexes so dictionary construction can never trap at runtime.
        var byID: [String: HomeAssistantEntity] = [:]
        for entity in entities { byID[entity.entityID] = entity }
        entities = byID.values.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.entityID < $1.entityID : order == .orderedAscending
        }
        var entityIndex: [String: Int] = [:]
        var idsByDomain: [String: [String]] = [:]
        for (index, entity) in entities.enumerated() {
            entityIndex[entity.entityID] = index
            let domain = entity.domain
            guard !domain.isEmpty else { continue }
            idsByDomain[domain, default: []].append(entity.entityID)
        }
        entityIndexByID = entityIndex
        entityIDsByDomain = idsByDomain
        searchRevision &+= 1
    }

    private nonisolated static func coalescingKey(
        domain: String, service: String, data: [String: JSONValue]
    ) -> String? {
        // Only absolute, replaceable setpoints may be coalesced. In particular,
        // never deduplicate a toggle, lock, scene, app launch or relative seek.
        if domain == "light" && service == "turn_on" {
            if ["rgb_color", "color_temp_kelvin", "effect"].contains(where: { data[$0] != nil }) {
                return "light.appearance"
            }
            if data["brightness_pct"] != nil { return "light.brightness" }
        }
        if domain == "media_player" && service == "volume_set" { return "media.volume" }
        if domain == "climate" && service == "set_temperature" { return "climate.temperature" }
        if domain == "cover" && service == "set_cover_position" { return "cover.position" }
        return nil
    }

    private func performService(
        domain: String,
        service: String,
        entity: HomeAssistantEntity,
        data: [String: JSONValue] = [:],
        optimisticState: String? = nil,
        feedback: IOSNextFeedbackEvent? = nil
    ) async {
        guard acceptsDeviceCommands, entity.isAvailable else {
            lastActionError = "Home Assistant ist nicht verbunden oder das Gerät ist nicht verfügbar."
            return
        }
        let entityID = entity.entityID
        let generation = connectionGeneration
        let key = Self.coalescingKey(domain: domain, service: service, data: data)
        let commandTrace = IOSNextPerformance.begin("HA.DeviceCommand")
        defer { IOSNextPerformance.end("HA.DeviceCommand", commandTrace) }
        let commandResult = await deviceCommands.execute(entityID: entityID, coalescingKey: key) { [self] in
            guard generation == connectionGeneration,
                  entity(withID: entityID)?.isAvailable == true else { return .cancelled }
            activeActionEntityIDs.insert(entityID)
            lastActionError = nil
            defer { activeActionEntityIDs.remove(entityID) }
            let revisionAtDispatch = entityStateRevisions[entityID, default: 0]

            do {
                try await client.callService(
                    domain: domain, service: service, targetEntityID: entityID,
                    serviceData: data
                )
                guard generation == connectionGeneration else {
                    return .outcomeUnknown("Verbindung wechselte nach dem Senden; Zustand wird neu synchronisiert.")
                }
                // Never put attributes from the old button/tile snapshot back
                // over a newer HA WebSocket state change.
                if let optimisticState,
                   entityStateRevisions[entityID, default: 0] == revisionAtDispatch,
                   let index = entityIndexByID[entityID],
                   entities.indices.contains(index),
                   entities[index].entityID == entityID {
                    entities[index] = entities[index].updating(state: optimisticState)
                }
                if let feedback { IOSNextFeedbackCenter.shared.play(feedback) }
                return .executed
            } catch {
                if generation == connectionGeneration {
                    lastActionError = error.localizedDescription
                    IOSNextFeedbackCenter.shared.play(.error)
                    // A transport error does not prove the backend did not act.
                    return .outcomeUnknown(error.localizedDescription)
                }
                return .outcomeUnknown("Verbindung wechselte während der Aktion.")
            }
        }
        reportCommandResult(commandResult, entityID: entityID, generation: generation)
    }

    private func reportCommandResult(
        _ result: DeviceCommandResult,
        entityID: String,
        generation: UInt64
    ) {
        switch result {
        case .executed, .superseded:
            return
        case .cancelled:
            guard generation == connectionGeneration else { return }
            lastActionError = "Der Gerätebefehl wurde vor der Ausführung abgebrochen."
        case let .failed(message):
            guard generation == connectionGeneration else { return }
            lastActionError = message
            IOSNextFeedbackCenter.shared.play(.error)
        case let .outcomeUnknown(message):
            // The transport may have delivered the request before cancellation.
            // Never retry automatically; surface uncertainty until a later
            // authoritative Home Assistant state update resolves the device state.
            lastActionError = "Ergebnis der Aktion für \(entityID) unbekannt: \(message)"
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
