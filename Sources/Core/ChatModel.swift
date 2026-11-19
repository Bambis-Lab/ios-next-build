import Foundation
import LocalAuthentication
import Observation
import UIKit

/// A verified Family Broker must never be substituted with a locally
/// remembered or self-asserted contact when its discovery route fails.
enum ChatContactDiscoveryPolicy {
    static func mayUseLegacyRecipient(statusCode: Int, familyCredentialActive: Bool) -> Bool {
        statusCode == 404 && !familyCredentialActive
    }
}

@MainActor
@Observable
final class ChatModel {
    enum State: Equatable {
        case notConfigured
        case connecting
        case online
        case offline(String)
    }

    private typealias PartialMessage = ChatPersistentPartial

    static let chunkSize = 384 * 1024
    static let maximumBytes: [ChatMessageKind: Int] = [
        .text: 16 * 1024,
        .image: 12 * 1024 * 1024,
        .voice: 24 * 1024 * 1024,
        .video: 30 * 1024 * 1024,
    ]

    var state: State = .notConfigured
    var messages: [ChatMessage] = []
    var draft = ""
    var recipientUserID = ""
    var showingFamilyGroup = false
    var familyGroup: ChatFamilyGroup?
    private var draftsByPeer: [String: String] = [:]

    var visibleMessages: [ChatMessage] {
        if showingFamilyGroup {
            return messages.filter { $0.conversationID == "family" }
        }
        guard !recipientUserID.isEmpty else { return [] }
        return messages.filter {
            $0.conversationID == nil && $0.peerUserID == recipientUserID
        }
    }
    var contacts: [ChatContact] = []
    var lastError: String?
    var ownSafetyNumber = ""
    var recipientSafetyNumbers: [String] = []
    var isSending = false
    private(set) var pendingChatSendID:String?
    private(set) var chatOutboxBlocked=false
    private(set) var pendingChatExpiresAt:Date?
    private(set) var pendingChatAllConfirmed=false
    var accessRole: ChatAccessRole?
    var lastCreatedTicketID: String?
    var memberTickets: [SupportTicket] = []
    var memberTicketDetails: [String: SupportTicket] = [:]

    private let relay = ChatRelayClient()
    private var configuration: ChatConfiguration?
    private var isFamilyCredentialActive = false
    private var familyRenewalTask: Task<Void, Never>?
    private var keys: ChatDeviceKeys?
    private var receiveTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startupToken: UUID?
    private var startupEpoch: UInt64 = 0
    private var configurationGeneration: UInt64 = 0
    private var ticketReadLease: TicketOfflineLease?
    private var ticketCacheReady = false
    private var ticketReadOffline = false
    private typealias HistorySnapshot = ChatPersistentSnapshot
    private var historyArchive: ChatHistoryArchive?
    private var historyRecordCheckpoint: ChatRecordReceiveCheckpoint?
    private(set) var historyMigrationInProgress=false
    private(set) var historyMigrationNotice:String?
    var historyUsesV2:Bool { historyRecordCheckpoint != nil }
    @ObservationIgnored private let historyMutationGate = ChatHistoryMutationGate()
    private var partialMessages: [String: PartialMessage] = [:]

    private func openChatOutbox(configuration:ChatConfiguration,keys:ChatDeviceKeys) throws -> DurableChatOutbox {
        let scope=ChatOutboxScope(endpoint:configuration.baseURL,user:configuration.userID,
            device:configuration.deviceID,keyFingerprint:keys.safetyNumber)
        return try DurableChatOutbox(scope:scope,local:keys.publicIdentity(
            userID:configuration.userID,deviceID:configuration.deviceID))
    }

    private func refreshChatOutboxState(configuration:ChatConfiguration,keys:ChatDeviceKeys) {
        pendingChatSendID=nil
        pendingChatExpiresAt=nil
        pendingChatAllConfirmed=false
        chatOutboxBlocked=false
        do {
            let pending=try openChatOutbox(configuration:configuration,keys:keys).pending()
            applyPendingChatState(pending)
        } catch {
            chatOutboxBlocked=true
        }
    }

    private func applyPendingChatState(_ pending:DurableChatOutbox.Pending?) {
        pendingChatSendID=pending?.groupID
        pendingChatExpiresAt=pending?.entries.first.flatMap {
            ISO8601DateFormatter().date(from:$0.envelope.createdAt)?.addingTimeInterval(90)
        }
        pendingChatAllConfirmed=pending?.entries.allSatisfy({$0.phase == .confirmed}) ?? false
    }

    private func loadFamilyHistory(configuration: ChatConfiguration) async throws {
        let generation=configurationGeneration
        try await historyMutationGate.withExclusive(isCurrent:{generation == self.configurationGeneration}) {
            try await loadFamilyHistoryLocked(configuration:configuration,generation:generation)
        }
    }

    private func loadFamilyHistoryLocked(configuration:ChatConfiguration,generation:UInt64) async throws {
        guard self.configuration == configuration, let keys else { throw CancellationError() }
        historyArchive=nil
        historyRecordCheckpoint=nil
        // Clear decrypted state before even the marker/key lookup can throw.
        restoreCheckpoint(HistorySnapshot(version:1,messages:[],partials:[:],seen:[:]))
        // A marker, once published by the separately authorized migration,
        // is the authority. Missing/corrupt v2 must never reactivate v1.
        if try ChatV2MigrationCoordinator.hasActiveMarker(configuration:configuration,keyFingerprint:keys.safetyNumber) {
            restoreCheckpoint(HistorySnapshot(version:1,messages:[],partials:[:],seen:[:]))
            let coordinator=try ChatV2MigrationCoordinator(configuration:configuration,keyFingerprint:keys.safetyNumber)
            guard let active=try await coordinator.openActive() else { throw ChatHistoryError.invalidArchive }
            let original=try await active.load()
            try Task.checkCancellation()
            guard generation == configurationGeneration, self.configuration == configuration else { throw CancellationError() }
            let normalized=HistorySnapshot(version:1,messages:original.messages.map { message in
                var record=message
                if record.delivery == .sending { record.delivery = .failed }
                return record
            },partials:original.partials,seen:original.seen)
            if normalized != original {
                _ = try await active.commit(previous:original,next:normalized,verifiedEnvelopeIDs:[])
            }
            try Task.checkCancellation()
            guard generation == configurationGeneration, self.configuration == configuration else { throw CancellationError() }
            restoreCheckpoint(normalized)
            historyRecordCheckpoint=active
            return
        }
        let archive = try ChatHistoryArchive(configuration: configuration)
        if let snapshot = try archive.load(HistorySnapshot.self) {
            guard snapshot.version == 1, snapshot.messages.count <= 200,
                  snapshot.partials.count <= 256, snapshot.seen.count <= 20_000 else {
                throw ChatHistoryError.invalidArchive
            }
            messages = snapshot.messages.map { message in
                var record = message
                if record.delivery == .sending { record.delivery = .failed }
                return record
            }
            partialMessages = snapshot.partials
            seenEnvelopeIDs = snapshot.seen
        } else {
            messages = []
            partialMessages = [:]
            seenEnvelopeIDs = [:]
        }
        historyArchive = archive
    }

    // Only this interactive path can publish a new marker. It is never called
    // automatically at login or by a background task.
    func canActivateHistoryV2(_ app:AppModel) -> Bool {
        guard isFamilyCredentialActive, state == .online, !historyMigrationInProgress,
              !isSending, pendingChatSendID==nil, !chatOutboxBlocked,
              !callBusy, !audioPreparing, audioSession==nil,
              startupTask==nil, historyArchive != nil, historyRecordCheckpoint==nil,
              let configuration,let family=app.familyChatContext(),
              family.haUserID==configuration.userID,family.deviceID==configuration.deviceID,
              family.endpoint==configuration.baseURL,family.grant.accessToken==configuration.token
        else {return false}
        return !(callListing?.calls.contains(where:{$0.state == .accepted || $0.state == .ringing}) ?? false)
    }

    func activateHistoryV2(using app:AppModel) async {
        guard canActivateHistoryV2(app),let configuration,let keys else {return}
        historyMigrationNotice=nil
        historyMigrationInProgress=true
        defer {historyMigrationInProgress=false}
        let originalGeneration=configurationGeneration
        var migrationGeneration=originalGeneration
        func matches() -> Bool {
            guard !Task.isCancelled,configurationGeneration==migrationGeneration,
                  self.configuration==configuration,isFamilyCredentialActive,
                  let family=app.familyChatContext(),family.haUserID==configuration.userID,
                  family.deviceID==configuration.deviceID,family.endpoint==configuration.baseURL,
                  family.grant.accessToken==configuration.token,
                  self.keys?.safetyNumber==keys.safetyNumber
            else {return false}
            return true
        }
        // Device authentication is local; it does not mint an owner privilege.
        // Recheck after the interactive prompt because the account may change.
        var paused=false
        do {
            let auth=LAContext()
            var policyError:NSError?
            guard auth.canEvaluatePolicy(.deviceOwnerAuthentication,error:&policyError),
                  try await auth.evaluatePolicy(.deviceOwnerAuthentication,
                    localizedReason:"Verschlüsselten Chatverlauf einmalig auf V2 umstellen"),
                  matches(),state == .online,!isSending,!callBusy,!audioPreparing,
                  audioSession==nil,startupTask==nil,
                  !(callListing?.calls.contains(where:{$0.state == .accepted || $0.state == .ringing}) ?? false)
            else {throw ChatError.authenticationFailed}
            // Stop new sends/calls, cancel receive and renew, then wait for
            // any already-admitted durable transaction to finish.
            state = .connecting
            paused=true
            receiveTask?.cancel()
            receiveTask=nil
            familyRenewalTask?.cancel()
            familyRenewalTask=nil
            try await historyMutationGate.withExclusive(isCurrent:{matches()}) {
                guard matches(),let archive=historyArchive,historyRecordCheckpoint==nil else {
                    throw ChatError.authenticationFailed
                }
                configurationGeneration &+= 1
                resetTicketReadAccess()
                migrationGeneration=configurationGeneration
                let coordinator=try ChatV2MigrationCoordinator(configuration:configuration,keyFingerprint:keys.safetyNumber)
                let source=try await coordinator.prepare(archive)
                guard matches() else {throw ChatError.authenticationFailed}
                // Read-only broker identity/delivery check after import.
                let session=try await relay.session(configuration:configuration)
                guard session.userID==configuration.userID else {throw ChatError.authenticationFailed}
                try await relay.requireAcknowledgedDelivery(configuration:configuration)
                let active=try await coordinator.activate(prepared:source,archive:archive,authorize:{matches()})
                // Marker publication is irreversible even if the account
                // changes while the async call returns. Never reattach V1.
                guard matches() else {throw CancellationError()}
                historyArchive=nil
                historyRecordCheckpoint=active
            }
            if matches() {historyMigrationNotice="V2 aktiviert. Das ursprüngliche Archiv bleibt unverändert erhalten."}
        } catch {
            if configurationGeneration==migrationGeneration,self.configuration==configuration {
                historyMigrationNotice="Umstellung nicht abgeschlossen. Der Speicherzustand wird beim erneuten Verbinden sicher geprüft."
            }
        }
        guard paused,configurationGeneration==migrationGeneration,self.configuration==configuration,
              !Task.isCancelled else {return}
        // Reopen exclusively through marker-aware startup, including after a
        // failure near marker publication. Never resume an old writer directly.
        historyArchive=nil
        historyRecordCheckpoint=nil
        historyMigrationInProgress=false
        await start(using:app)
    }

    private func historySnapshot() -> HistorySnapshot {
        HistorySnapshot(version: 1, messages: messages, partials: partialMessages, seen: seenEnvelopeIDs)
    }

    private func restoreCheckpoint(_ snapshot: HistorySnapshot) {
        messages = snapshot.messages
        partialMessages = snapshot.partials
        seenEnvelopeIDs = snapshot.seen
    }

    private func commitHistoryMutation(generation:UInt64, verifiedEnvelopeIDs:[String]=[],
                                       _ mutation: () throws -> Void) async throws {
        guard generation == configurationGeneration else { throw CancellationError() }
        if !isFamilyCredentialActive {
            try mutation()
            return
        }
        try await historyMutationGate.commit(isCurrent:{ generation == self.configurationGeneration },
            read:{ historySnapshot() }, apply:{ restoreCheckpoint($0) }, mutate:mutation,
            persist:{ previous,next in
                if let checkpoint=historyRecordCheckpoint {
                    let receipt=try await checkpoint.commit(previous:previous,next:next,verifiedEnvelopeIDs:verifiedEnvelopeIDs)
                    guard receipt.envelopeIDs == verifiedEnvelopeIDs else { throw ChatHistoryError.invalidArchive }
                } else {
                    guard let historyArchive else { throw ChatHistoryError.missingKey }
                    try historyArchive.save(next)
                }
            })
    }
    private var seenEnvelopeIDs: [String: Date] = [:]
    private let endpointKey = "chatRelayEndpoint"
    private let userKey = "chatUserID"
    private let deviceKey = "chatDeviceID"
    private let recipientKey = "chatRecipientUserID"
    private let tokenAccount = "chatRelayToken"
    private let haUserKey = "chatHomeAssistantUserID"

    init() {
        restoreConfiguration()
    }

    private(set) var callListing: FamilyCallListing?
    private(set) var callError: String?
    private(set) var callBusy = false
    private var callGeneration: UInt64 = 0
    private var audioAttempt = UUID()
    private(set) var audioSession: FamilyAudioCallSession?
    private(set) var audioCallID: String?
    private(set) var audioPreparing = false
    private(set) var audioError: String?

    var canStartAudio: Bool { canSignalCalls && callListing?.audioTransport == true }

    func stopAudio() {
        audioAttempt = UUID()
        audioSession?.stop()
        audioSession = nil
        audioCallID = nil
        audioPreparing = false
    }

    private func reconcileAudio(_ listing: FamilyCallListing?) {
        guard let id = audioCallID else { return }
        guard listing?.audioTransport == true,
              listing?.calls.contains(where: { $0.id == id && $0.state == .accepted }) == true else {
            stopAudio()
            return
        }
    }

    /// Explicit foreground action only. A safety number entered from an
    /// independent channel must match the exact currently registered device.
    func startAudio(callID: String, confirmedSafetyNumber: String) async {
        guard canStartAudio, !audioPreparing, audioSession == nil,
              let configuration, let keys,
              let call = callListing?.calls.first(where: { $0.id == callID && $0.state == .accepted }),
              call.isParticipant(configuration) else { return }
        let attempt = UUID()
        audioAttempt = attempt
        audioCallID = callID
        audioPreparing = true
        audioError = nil
        defer {
            if audioAttempt == attempt {
                stopAudio()
            }
        }
        do {
            let context = try FamilyAudioContext(callID: call.id, caller: call.caller, callee: call.callee,
                local: [configuration.userID, configuration.deviceID])
            let identities = try await relay.identities(for: context.peer[0], configuration: configuration)
            guard audioAttempt == attempt, canStartAudio, !Task.isCancelled,
                  callListing?.calls.contains(where: { $0.id == callID && $0.state == .accepted }) == true,
                  self.configuration == configuration else { return }
            let matches = identities.filter { [$0.userID, $0.deviceID] == context.peer }
            guard matches.count == 1, let peer = matches.first else { throw ChatError.noRecipientDevice }
            let confirmed = confirmedSafetyNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            _ = try FamilyAudioCallSession.validate(call: call, configuration: configuration,
                peer: peer, confirmedSafetyNumber: confirmed)
            // Existing chat pin must also agree. Never silently replace it.
            try ChatDeviceKeys.pin(peer)
            let base = ChatRelayClient.transportBaseURL(for: configuration.baseURL)
            guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
                  components.scheme == "https" else { throw FamilyAudioWireError.invalidEndpoint }
            components.scheme = "wss"
            components.path = "/v1/audio"
            components.query = nil
            components.fragment = nil
            guard let endpoint = components.url else { throw FamilyAudioWireError.invalidEndpoint }
            let session = try FamilyAudioCallSession(call: call, configuration: configuration,
                endpoint: endpoint, keys: keys, verifiedPeer: peer, confirmedSafetyNumber: confirmed)
            audioSession = session
            audioPreparing = false
            audioCallID = callID
            var sentToken = configuration.token
            try await session.run { [weak self] in
                guard let self, self.audioAttempt == attempt, self.isFamilyCredentialActive,
                      let current = self.configuration,
                      current.userID == configuration.userID, current.deviceID == configuration.deviceID,
                      current.baseURL == configuration.baseURL else { throw CancellationError() }
                guard current.token != sentToken else { return nil }
                sentToken = current.token
                return current.token
            }
            if audioAttempt == attempt, session.state == .failed {
                audioError = "Audioverbindung wurde sicher beendet."
            }
        } catch {
            if audioAttempt == attempt, !Task.isCancelled {
                audioError = "Audio konnte nicht sicher gestartet oder fortgesetzt werden."
            }
        }
    }
    var canSignalCalls: Bool { isFamilyCredentialActive && state == .online && !historyMigrationInProgress }
    var canShowCallPanel: Bool { canSignalCalls || (isFamilyCredentialActive && audioSession != nil) }

    private func resetCalls() {
        stopAudio()
        audioError = nil
        callGeneration &+= 1
        callListing = nil
        callError = nil
        callBusy = false
    }

    // View-scoped polling only; cancellation never starts a new request.
    func pollCallsWhileVisible() async {
        let generation = callGeneration
        while !Task.isCancelled && canShowCallPanel && generation == callGeneration {
            if canSignalCalls { await refreshCalls() }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
        }
    }

    func refreshCalls() async {
        guard canSignalCalls, let configuration, !callBusy else { return }
        let generation = callGeneration
        callBusy = true
        defer { if generation == callGeneration { callBusy = false } }
        do {
            let listing = try await relay.callStates(configuration: configuration)
            guard generation == callGeneration, canSignalCalls, !Task.isCancelled else { return }
            callListing = listing
            reconcileAudio(listing)
            callError = nil
        } catch {
            guard generation == callGeneration, !Task.isCancelled else { return }
            if familyAudioTransientNetworkError(error),
               let session = audioSession,
               session.state == .active || session.state == .reconnecting {
                // Existing audio must reauthenticate against the relay; this
                // grace path does not grant new calls or Owner privileges.
                callError = "Anrufstatus vorübergehend nicht erreichbar."
                return
            }
            callListing = nil
            reconcileAudio(nil)
            callError = "Anrufsignalisierung nicht verfügbar."
        }
    }

    func signalCall(_ signal: FamilyCallSignal) async {
        guard canSignalCalls, let configuration, !callBusy else { return }
        let generation = callGeneration
        if signal.action == .hangup && signal.callID == audioCallID { stopAudio() }
        callBusy = true
        defer { if generation == callGeneration { callBusy = false } }
        do {
            _ = try await relay.signalCall(signal, configuration: configuration)
            guard generation == callGeneration, canSignalCalls, !Task.isCancelled else { return }
            let listing = try await relay.callStates(configuration: configuration)
            guard generation == callGeneration, canSignalCalls, !Task.isCancelled else { return }
            callListing = listing
            reconcileAudio(listing)
            callError = nil
        } catch {
            guard generation == callGeneration, !Task.isCancelled else { return }
            callListing = nil
            reconcileAudio(nil)
            callError = "Anrufaktion konnte nicht bestätigt werden."
        }
    }

    func isOwnCaller(_ call: FamilyCallState) -> Bool {
        guard let configuration else { return false }
        return call.caller == [configuration.userID, configuration.deviceID]
    }

    func inviteSelectedContact() async {
        guard canSignalCalls, !showingFamilyGroup, let configuration,
              contacts.contains(where: { $0.userID == recipientUserID }), !callBusy else { return }
        let generation = callGeneration
        let peer = recipientUserID
        callBusy = true
        defer { if generation == callGeneration { callBusy = false } }
        do {
            let devices = try await relay.identities(for: peer, configuration: configuration)
            guard generation == callGeneration, canSignalCalls, !Task.isCancelled else { return }
            callBusy = false
            guard peer == recipientUserID, !showingFamilyGroup,
                  devices.count == 1, let target = devices.first, target.userID == peer else {
                callError = "Ein eindeutig registriertes Empfängergerät ist erforderlich."
                return
            }
            await signalCall(.invite(userID: peer, deviceID: target.deviceID))
        } catch {
            guard generation == callGeneration else { return }
            callBusy = false
            callError = "Empfängergerät konnte nicht bestätigt werden."
        }
    }

    var canSend: Bool {
        state == .online && (showingFamilyGroup ? familyGroup?.isReady == true : !recipientUserID.isEmpty)
    }

    func start(using appModel: AppModel) async {
        guard !historyMigrationInProgress else {return}
        if let existingStartupTask = startupTask {
            let observedToken = startupToken
            await existingStartupTask.value
            if startupToken == observedToken {
                startupTask = nil
                startupToken = nil
            }
            if receiveTask != nil { return }
            // A bare start() can finish without configuration. If the HA
            // bootstrap context is ready, let this caller own the bootstrap.
            if configuration == nil, appModel.chatBootstrapContext() != nil {
                await start(using: appModel)
            }
            return
        }
        guard receiveTask == nil else { return }
        startupEpoch &+= 1
        let epoch = startupEpoch
        let token = UUID()
        startupToken = token
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStart(using: appModel, epoch: epoch)
        }
        startupTask = task
        await task.value
        if startupToken == token {
            startupTask = nil
            startupToken = nil
        }
    }

    private func performStart(using appModel: AppModel, epoch: UInt64) async {
        if appModel.familyBrokerConfigured {
            // Do not fall back to an insecure legacy chat-bootstrap route while
            // the registered family device identity is still being verified.
            guard appModel.registeredFamilyProfile != nil else {
                state = .offline("Familienregistrierung wird überprüft.")
                return
            }
            await appModel.refreshFamilyChatGrantIfNeeded()
            guard epoch == startupEpoch, !Task.isCancelled,
                  let family = appModel.familyChatContext() else {
                state = .offline("Familien-Chat-Berechtigung konnte nicht bestätigt werden.")
                return
            }
            let previouslyBoundHAUser = UserDefaults.standard.string(forKey: haUserKey)
            if let previouslyBoundHAUser, previouslyBoundHAUser != family.haUserID {
                forgetConfiguration(preservingStartup: true)
            }
            let existing = configuration
            if existing?.token != family.grant.accessToken ||
               existing?.userID != family.haUserID ||
               existing?.baseURL != family.endpoint ||
               existing?.deviceID != family.deviceID ||
               !isFamilyCredentialActive {
                let recipient = previouslyBoundHAUser == family.haUserID && !recipientUserID.isEmpty
                    ? recipientUserID : family.haUserID
                do {
                    if ChatDeviceKeys.mayMigrateLegacyKeys(
                        previouslyBoundHAUserID: previouslyBoundHAUser,
                        verifiedHAUserID: family.haUserID,
                        hasOldChatConfiguration: existing != nil,
                        alreadyUsingFamilyCredential: isFamilyCredentialActive
                    ) {
                        // Never import old keys after an HA account switch.
                        // Preserve old key material for rollback / original chats.
                        try ChatDeviceKeys.migrateLegacyKeysForVerifiedAccount(family.haUserID)
                    }
                    try configure(
                        endpoint: family.endpoint.absoluteString,
                        token: family.grant.accessToken,
                        userID: family.haUserID,
                        recipientUserID: recipient,
                        deviceID: family.deviceID,
                        preservingStartup: true
                    )
                    UserDefaults.standard.set(family.haUserID, forKey: haUserKey)
                    isFamilyCredentialActive = true
                } catch {
                    state = .offline("Familien-Chat-Konfiguration fehlgeschlagen.")
                    return
                }
            }
            await performRelayStart(epoch: epoch)
            if case .online = state {
                scheduleFamilyRenewal(using: appModel, grant: family.grant)
            }
            return
        }
        if let context = appModel.chatBootstrapContext() {
            let boundHAUser = UserDefaults.standard.string(forKey: haUserKey)
            if let boundHAUser, boundHAUser != context.homeAssistantUserID {
                forgetConfiguration(preservingStartup: true)
                guard epoch == startupEpoch, !Task.isCancelled else { return }
            }
            if configuration == nil {
                do {
                    try await automaticConfigure(using: context)
                    guard epoch == startupEpoch, !Task.isCancelled else { return }
                } catch {
                    guard epoch == startupEpoch, !Task.isCancelled else { return }
                    state = .offline("Automatische Chat-Einrichtung fehlgeschlagen: \(error.localizedDescription)")
                    return
                }
            } else if boundHAUser == nil, let configuration {
                if Self.legacyIdentityMatchesHomeAssistant(
                    chatUserID: configuration.userID,
                    displayName: context.displayName
                ) {
                    if (try? await relay.linkHomeAssistant(
                        accessToken: context.homeAssistantAccessToken,
                        configuration: configuration
                    )) != nil {
                        guard epoch == startupEpoch, !Task.isCancelled else { return }
                        UserDefaults.standard.set(context.homeAssistantUserID, forKey: haUserKey)
                    }
                } else {
                    forgetConfiguration(preservingStartup: true)
                    guard epoch == startupEpoch, !Task.isCancelled else { return }
                    do {
                        try await automaticConfigure(using: context)
                        guard epoch == startupEpoch, !Task.isCancelled else { return }
                    } catch {
                        guard epoch == startupEpoch, !Task.isCancelled else { return }
                        state = .offline("Automatische Chat-Einrichtung fehlgeschlagen: \(error.localizedDescription)")
                        return
                    }
                }
            }
        }
        await performRelayStart(epoch: epoch)
    }

    func configure(
        endpoint: String, token: String, userID: String, recipientUserID: String,
        deviceID explicitDeviceID: String? = nil,
        preservingStartup: Bool = false
    ) throws {
        guard let url = URL(string: endpoint), isAllowedEndpoint(url),
              Self.validIdentifier(userID), Self.validIdentifier(recipientUserID), token.count >= 32 else {
            throw ChatError.invalidConfiguration
        }
        let deviceID = explicitDeviceID ??
            UserDefaults.standard.string(forKey: deviceKey) ??
            "ios-\(UUID().uuidString.lowercased())"
        let replacesIdentity = configuration.map {
            $0.userID != userID || $0.baseURL != url || $0.deviceID != deviceID
        } ?? false
        if preservingStartup {
            receiveTask?.cancel()
            receiveTask = nil
        } else {
            stop()
        }
        configurationGeneration &+= 1
        resetTicketReadAccess()
        resetCalls()
        historyArchive = nil
        historyRecordCheckpoint = nil
        if replacesIdentity {
            draft = ""
            showingFamilyGroup = false
            familyGroup = nil
            draftsByPeer.removeAll(keepingCapacity: false)
            messages.removeAll(keepingCapacity: false)
            memberTickets.removeAll(keepingCapacity: false)
            memberTicketDetails.removeAll(keepingCapacity: false)
            partialMessages.removeAll(keepingCapacity: false)
            seenEnvelopeIDs.removeAll(keepingCapacity: false)
            ChatMediaThumbnailCache.shared.clear()
        }
        // Persist the credential first. A failed Keychain write must not leave
        // new account metadata paired with an unrelated previous account token.
        try KeychainStore.save(token, account: tokenAccount)
        UserDefaults.standard.set(deviceID, forKey: deviceKey)
        UserDefaults.standard.set(url.absoluteString, forKey: endpointKey)
        UserDefaults.standard.set(userID, forKey: userKey)
        UserDefaults.standard.set(recipientUserID, forKey: recipientKey)
        self.recipientUserID = recipientUserID
        configuration = ChatConfiguration(baseURL: url, token: token, userID: userID, deviceID: deviceID)
        state = .connecting
    }

    func start() async {
        guard !historyMigrationInProgress else {return}
        // Pre-HA standalone chat cannot reuse a stale legacy credential when
        // authenticated family enrollment is mandatory.
        guard FamilyBootstrapClient.configuredURL() == nil || isFamilyCredentialActive else {
            state = .offline("Zuerst mit deinem Home-Assistant-Familienkonto anmelden.")
            return
        }
        if let existingStartupTask = startupTask {
            await existingStartupTask.value
            return
        }
        guard receiveTask == nil else { return }
        startupEpoch &+= 1
        let epoch = startupEpoch
        let token = UUID()
        startupToken = token
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRelayStart(epoch: epoch)
        }
        startupTask = task
        await task.value
        if startupToken == token {
            startupTask = nil
            startupToken = nil
        }
    }

    private func performRelayStart(epoch: UInt64) async {
        guard epoch == startupEpoch, !Task.isCancelled,
              receiveTask == nil, let configuration else { return }
        do {
            let keys = try ChatDeviceKeys.loadOrCreate(
                forUserID: isFamilyCredentialActive ? configuration.userID : nil
            )
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            self.keys = keys
            ownSafetyNumber = keys.safetyNumber
            try await relay.register(
                identity: keys.publicIdentity(userID: configuration.userID, deviceID: configuration.deviceID),
                configuration: configuration
            )
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            let session = try await relay.session(configuration: configuration)
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            guard session.userID == configuration.userID else { throw ChatError.invalidResponse }
            if isFamilyCredentialActive {
                // Must negotiate *before* reading messages. Old brokers delete
                // ciphertext on GET and cannot guarantee safe replay.
                try await relay.requireAcknowledgedDelivery(configuration: configuration)
            }
            guard epoch == startupEpoch, !Task.isCancelled, self.configuration == configuration else { return }
            if isFamilyCredentialActive { try await loadFamilyHistory(configuration: configuration) }
            guard epoch == startupEpoch, !Task.isCancelled, self.configuration == configuration else { return }
            if isFamilyCredentialActive {refreshChatOutboxState(configuration:configuration,keys:keys)}
            accessRole = session.role
            do {
                let loadedContacts = try await relay.contacts(configuration: configuration)
                guard epoch == startupEpoch, !Task.isCancelled else { return }
                contacts = loadedContacts
                    .filter { $0.userID != configuration.userID }
                    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            } catch ChatError.rejected(let status) {
                // Legacy installations may have a preconfigured private peer.
                // A *verified* family session must never create a plausible
                // contact from a saved user ID when broker discovery failed.
                guard ChatContactDiscoveryPolicy.mayUseLegacyRecipient(
                    statusCode: status, familyCredentialActive: isFamilyCredentialActive
                ) else {
                    throw ChatError.rejected(status)
                }
                guard epoch == startupEpoch, !Task.isCancelled else { return }
                contacts = recipientUserID.isEmpty
                    ? []
                    : [ChatContact(userID: recipientUserID, displayName: recipientUserID)]
            }
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            if !recipientUserID.isEmpty, !contacts.contains(where: { $0.userID == recipientUserID }) {
                recipientUserID = ""
                UserDefaults.standard.removeObject(forKey: recipientKey)
            }
            if recipientUserID.isEmpty, contacts.count == 1, let onlyContact = contacts.first {
                recipientUserID = onlyContact.userID
                UserDefaults.standard.set(onlyContact.userID, forKey: recipientKey)
            }
            try await updateRecipientSafetyNumbers()
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            if isFamilyCredentialActive {
                // The group does not exist until the family broker confirms its
                // five verified HA identities and active device enrollment.
                familyGroup = try? await relay.familyGroup(configuration: configuration)
            } else {
                familyGroup = nil
            }
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            if showingFamilyGroup && familyGroup == nil {
                showingFamilyGroup = false
                draft = draftsByPeer[recipientUserID] ?? ""
            }
            state = .online
            receiveTask = Task { [weak self] in await self?.receiveLoop() }
        } catch {
            guard epoch == startupEpoch, !Task.isCancelled else { return }
            state = .offline(error.localizedDescription)
        }
    }

    func stop() {
        applyPendingChatState(nil)
        chatOutboxBlocked=false
        resetCalls()
        configurationGeneration &+= 1
        resetTicketReadAccess()
        historyArchive = nil
        historyRecordCheckpoint = nil
        startupEpoch &+= 1
        startupTask?.cancel()
        startupTask = nil
        startupToken = nil
        receiveTask?.cancel()
        receiveTask = nil
        familyRenewalTask?.cancel()
        familyRenewalTask = nil
        // Decrypted previews must not outlive an app/chat lifecycle stop.
        ChatMediaThumbnailCache.shared.clear()
        if configuration != nil { state = .offline("Empfang pausiert") }
    }

    func forgetConfiguration(preservingStartup: Bool = false) {
        applyPendingChatState(nil)
        chatOutboxBlocked=false
        historyArchive = nil
        historyRecordCheckpoint = nil
        configurationGeneration &+= 1
        resetTicketReadAccess()
        resetCalls()
        draft = ""
        showingFamilyGroup = false
        familyGroup = nil
        draftsByPeer.removeAll(keepingCapacity: false)
        if preservingStartup {
            receiveTask?.cancel()
            receiveTask = nil
        } else {
            stop()
        }
        messages.removeAll(keepingCapacity: false)
        memberTickets.removeAll(keepingCapacity: false)
        memberTicketDetails.removeAll(keepingCapacity: false)
        ChatMediaThumbnailCache.shared.clear()
        partialMessages.removeAll(keepingCapacity: false)
        seenEnvelopeIDs.removeAll(keepingCapacity: false)
        configuration = nil
        isFamilyCredentialActive = false
        familyRenewalTask?.cancel()
        familyRenewalTask = nil
        keys = nil
        ownSafetyNumber = ""
        recipientSafetyNumbers = []
        lastError = nil
        contacts = []
        recipientUserID = ""
        accessRole = nil
        lastCreatedTicketID = nil
        KeychainStore.delete(account: tokenAccount)
        UserDefaults.standard.removeObject(forKey: endpointKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: recipientKey)
        UserDefaults.standard.removeObject(forKey: haUserKey)
        state = .notConfigured
    }

    func selectContact(_ contact: ChatContact) {
        guard showingFamilyGroup || recipientUserID != contact.userID else { return }
        let previousConversation = showingFamilyGroup ? "family" : recipientUserID
        if !previousConversation.isEmpty { draftsByPeer[previousConversation] = draft }
        showingFamilyGroup = false
        recipientUserID = contact.userID
        draft = draftsByPeer[contact.userID] ?? ""
        UserDefaults.standard.set(contact.userID, forKey: recipientKey)
        recipientSafetyNumbers = []
        Task { try? await updateRecipientSafetyNumbers() }
    }

    func selectFamilyGroup() {
        guard familyGroup != nil, !showingFamilyGroup else { return }
        if !recipientUserID.isEmpty { draftsByPeer[recipientUserID] = draft }
        showingFamilyGroup = true
        draft = draftsByPeer["family"] ?? ""
        recipientSafetyNumbers = []
    }

    nonisolated static func legacyIdentityMatchesHomeAssistant(
        chatUserID: String,
        displayName: String
    ) -> Bool {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }
        return chatUserID.caseInsensitiveCompare(normalizedName) == .orderedSame
    }

    nonisolated static func automaticRelayEndpoint(for homeAssistantURL: URL) -> URL? {
        if let host = homeAssistantURL.host?.lowercased(), host.hasSuffix(".ts.net") {
            let labels = host.split(separator: ".")
            if labels.count >= 3 {
                let tailnet = labels.dropFirst().joined(separator: ".")
                return URL(string: "https://iosnext-chat.\(tailnet)/")
            }
        }
        return URL(string: "https://iosnext-chat.tailff745a.ts.net/")
    }

    private func automaticConfigure(using context: ChatBootstrapContext) async throws {
        guard let endpoint = Self.automaticRelayEndpoint(for: context.homeAssistantBaseURL),
              isAllowedEndpoint(endpoint) else {
            throw ChatError.invalidConfiguration
        }
        // Do not cancel the startup Task that owns this automatic bootstrap.
        receiveTask?.cancel()
        receiveTask = nil
        state = .connecting
        let deviceID = UserDefaults.standard.string(forKey: deviceKey) ?? "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(deviceID, forKey: deviceKey)
        let keys = try ChatDeviceKeys.loadOrCreate()
        self.keys = keys
        ownSafetyNumber = keys.safetyNumber
        // The relay derives the canonical chat identity from the authenticated
        // Home Assistant token. The bootstrap user ID is never trusted.
        let provisionalIdentity = keys.publicIdentity(
            userID: "bootstrap",
            deviceID: deviceID
        )
        let bootstrap = try await relay.bootstrap(
            endpoint: endpoint,
            homeAssistantAccessToken: context.homeAssistantAccessToken,
            identity: provisionalIdentity
        )
        guard Self.validIdentifier(bootstrap.userID), bootstrap.token.count >= 32 else {
            throw ChatError.invalidResponse
        }
        UserDefaults.standard.set(endpoint.absoluteString, forKey: endpointKey)
        UserDefaults.standard.set(bootstrap.userID, forKey: userKey)
        UserDefaults.standard.set(context.homeAssistantUserID, forKey: haUserKey)
        try KeychainStore.save(bootstrap.token, account: tokenAccount)
        configuration = ChatConfiguration(
            baseURL: endpoint,
            token: bootstrap.token,
            userID: bootstrap.userID,
            deviceID: deviceID
        )
    }

    private func scheduleFamilyRenewal(using appModel: AppModel, grant: FamilyChatGrant) {
        familyRenewalTask?.cancel()
        let remaining = grant.expiresAt - Int(Date().timeIntervalSince1970)
        let delay = max(20, remaining - 120)
        familyRenewalTask = Task { [weak self, weak appModel] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let appModel else { return }
            self.familyRenewalTask = nil
            let generation = self.configurationGeneration
            await appModel.refreshFamilyChatGrantIfNeeded(minimumValidity: 180)
            guard !Task.isCancelled, generation == self.configurationGeneration,
                  let family = appModel.familyChatContext() else { return }
            // During an active foreground call the existing audio codec and
            // call ownership must survive a token-only rotation.
            if self.audioSession != nil, self.isFamilyCredentialActive,
               let current = self.configuration, current.userID == family.haUserID,
               current.deviceID == family.deviceID, current.baseURL == family.endpoint,
               family.grant.expiresAt > grant.expiresAt,
               family.grant.accessToken != current.token {
                do {
                    self.receiveTask?.cancel()
                    try await self.historyMutationGate.withExclusive(isCurrent:{generation == self.configurationGeneration}) {
                        try KeychainStore.save(family.grant.accessToken, account:self.tokenAccount)
                        self.configurationGeneration &+= 1
                        self.resetTicketReadAccess()
                        self.configuration=ChatConfiguration(baseURL:current.baseURL,
                            token:family.grant.accessToken,userID:current.userID,deviceID:current.deviceID)
                        self.receiveTask=Task { [weak self] in await self?.receiveLoop() }
                        self.scheduleFamilyRenewal(using:appModel,grant:family.grant)
                    }
                    return
                } catch {
                    guard generation == self.configurationGeneration, !Task.isCancelled else { return }
                    self.stopAudio()
                }
            }
            self.receiveTask?.cancel()
            self.receiveTask = nil
            await self.start(using: appModel)
        }
    }

    func sendDraft() async {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let originalDraft = draft
        let generation=configurationGeneration
        let selectedPeer = recipientUserID
        let selectedGroup = showingFamilyGroup
        let accepted = await send(Data(value.utf8), kind: .text, contentType: "text/plain; charset=utf-8")
        // A failed preflight/relay request must not erase text the user typed.
        // Never erase edits made while the send was in flight.
        if accepted && generation==configurationGeneration && recipientUserID == selectedPeer &&
            showingFamilyGroup == selectedGroup && draft == originalDraft { draft = "" }
    }

    func sendImage(_ originalData: Data) async {
        do {
            let data = try Self.preparedImageData(originalData)
            await send(data, kind: .image, contentType: "image/jpeg")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendVideo(_ data: Data, contentType: String = "video/mp4") async {
        await send(data, kind: .video, contentType: contentType)
    }

    func sendVoice(_ data: Data) async {
        await send(data, kind: .voice, contentType: "audio/wav")
    }

    @discardableResult
    func send(_ data: Data, kind: ChatMessageKind, contentType: String) async -> Bool {
        let trace = IOSNextPerformance.begin("Chat.Send")
        defer { IOSNextPerformance.end("Chat.Send", trace) }
        guard let configuration, let keys, state == .online, !isSending, !historyMigrationInProgress,
              showingFamilyGroup || !recipientUserID.isEmpty else {
            lastError = "Bitte zuerst einen Chat-Kontakt auswählen."
            return false
        }
        guard data.count <= (Self.maximumBytes[kind] ?? 0) else {
            lastError = ChatError.contentTooLarge.localizedDescription
            return false
        }
        isSending = true
        defer { isSending = false }
        let sendGeneration = configurationGeneration
        // Capture the actual target before the first asynchronous preflight.
        let selectedPeer = recipientUserID
        let selectedGroup = showingFamilyGroup
        let selectedMembers = familyGroup?.members.map(\.userID)
        if isFamilyCredentialActive {
            do {
                let outbox=try openChatOutbox(configuration:configuration,keys:keys)
                pendingChatSendID=try outbox.pending()?.groupID
                chatOutboxBlocked=false
                guard pendingChatSendID==nil else {throw ChatHistoryError.busy}
                try await relay.requireIdempotentSender(configuration:configuration)
                guard sendGeneration==configurationGeneration,self.configuration==configuration,!Task.isCancelled,
                      selectedPeer==recipientUserID,selectedGroup==showingFamilyGroup else {return false}
            } catch {
                guard sendGeneration==configurationGeneration else {return false}
                lastError="Sicherer Versand nicht verfügbar oder ein früherer Versand ist noch offen."
                return false
            }
        }
        if selectedGroup {
            guard let familyGroup, familyGroup.isReady,
                  familyGroup.members.contains(where: { $0.userID == configuration.userID }) else {
                lastError = "Alle fünf Familienmitglieder müssen sichere Chatgeräte registriert haben."
                return false
            }
        }
        let groupID = UUID().uuidString.lowercased()
        var localMessage = ChatMessage(
            id: groupID,
            senderUserID: configuration.userID,
            recipientUserID: selectedGroup ? "family" : selectedPeer,
            kind: kind,
            contentType: contentType,
            data: data,
            createdAt: .now,
            direction: .outgoing,
            delivery: .sending
        )
        localMessage.conversationID = selectedGroup ? "family" : nil
        do {
            try await commitHistoryMutation(generation:sendGeneration) { appendMessage(localMessage) }
        } catch {
            guard sendGeneration == configurationGeneration else { return false }
            lastError = error.localizedDescription
            return false
        }
        do {
            let targetUsers: [String] = selectedGroup
                ? (selectedMembers?.filter { $0 != configuration.userID } ?? [])
                : [selectedPeer]
            guard !targetUsers.isEmpty else { throw ChatError.noRecipientDevice }
            var recipients: [ChatIdentity] = []
            for userID in targetUsers {
                let devices = try await relay.identities(for: userID, configuration: configuration)
                guard !devices.isEmpty else { throw ChatError.noRecipientDevice }
                recipients.append(contentsOf: devices)
            }
            guard sendGeneration == configurationGeneration else { return false }
            let safetyNumbers = try recipients.map { identity in
                try ChatDeviceKeys.pin(identity)
                guard let number = ChatDeviceKeys.safetyNumber(for: identity) else { throw ChatError.invalidEnvelope }
                return number
            }
            recipientSafetyNumbers = selectedGroup ? [] : safetyNumbers
            let chunks = Self.chunks(of: data)
            let sender = keys.publicIdentity(userID: configuration.userID, deviceID: configuration.deviceID)
            let createdAt = ISO8601DateFormatter().string(from: localMessage.createdAt)
            var staged:[ChatEnvelope]=[]
            for recipient in recipients {
                for (index, chunk) in chunks.enumerated() {
                    let envelope = try keys.encrypt(
                        chunk,
                        kind: kind,
                        contentType: contentType,
                        groupID: groupID,
                        chunkIndex: index,
                        chunkCount: chunks.count,
                        sender: sender,
                        recipient: recipient,
                        createdAt: createdAt,
                        conversationID: selectedGroup ? "family" : nil
                    )
                    try Task.checkCancellation()
                    guard sendGeneration == configurationGeneration else { return false }
                    if isFamilyCredentialActive {
                        staged.append(envelope)
                        guard staged.count<=1024 else {throw ChatHistoryError.capacity}
                    } else {
                        _ = try await relay.send(envelope, configuration: configuration)
                        guard sendGeneration == configurationGeneration else { return false }
                    }
                }
            }
            guard sendGeneration == configurationGeneration else { return false }
            if isFamilyCredentialActive {
                let outbox=try openChatOutbox(configuration:configuration,keys:keys)
                guard messages.contains(where:{$0.id==groupID && $0.direction == .outgoing}) else {
                    throw ChatHistoryError.invalidArchive
                }
                try outbox.stage(groupID:groupID,recipients:recipients,envelopes:staged)
                applyPendingChatState(try outbox.pending())
                try await flushChatOutbox(outbox,configuration:configuration,generation:sendGeneration)
                return true
            }
            do {
                try await commitHistoryMutation(generation:sendGeneration) { updateDelivery(id:groupID,to:.queued) }
            } catch {
                guard sendGeneration == configurationGeneration else { return false }
                lastError = "Nachricht übertragen, lokaler Versandstatus konnte nicht gespeichert werden."
            }
            return true
        } catch {
            guard sendGeneration == configurationGeneration else { return false }
            try? await commitHistoryMutation(generation:sendGeneration) { updateDelivery(id:groupID,to:.failed) }
            guard sendGeneration == configurationGeneration else { return false }
            lastError = error.localizedDescription
            // Once this exact group is durable, the composer has handed it
            // off to the journal, even if the network outcome is uncertain.
            // Do not invite the user to resend the same draft as a new ID.
            return pendingChatSendID==groupID && isFamilyCredentialActive
        }
    }

    // Only explicit user action retries an ambiguous submission after a
    // restart. The same signed envelopes are reused, never encrypted again.
    /// Explicit, local-only closure of an expired uncertain send. A queued
    /// fragment may already have arrived: never claim non-delivery or resend.
    func closeExpiredChatSend() async {
        guard isFamilyCredentialActive,state == .online,!isSending,!historyMigrationInProgress,
              let configuration,let keys else {return}
        let generation=configurationGeneration
        isSending=true
        defer {isSending=false}
        do {
            let outbox=try openChatOutbox(configuration:configuration,keys:keys)
            guard let pending=try outbox.expiredPending() else {throw ChatHistoryError.busy}
            try await commitHistoryMutation(generation:generation) {
                guard messages.contains(where:{$0.id==pending.groupID && $0.direction == .outgoing &&
                    $0.senderUserID==configuration.userID}) else {throw ChatHistoryError.invalidArchive}
                updateDelivery(id:pending.groupID,to:.unconfirmedExpired)
            }
            try Task.checkCancellation()
            guard generation==configurationGeneration,self.configuration==configuration else {return}
            try outbox.closeExpiredAfterHistoryCommit(groupID:pending.groupID)
            applyPendingChatState(nil)
            lastError="Versandauftrag abgeschlossen. Eine frühere Zustellung kann nicht ausgeschlossen werden."
        } catch {
            guard generation==configurationGeneration else {return}
            lastError="Abschluss nicht möglich. Der gesicherte Versandauftrag bleibt erhalten."
        }
    }

    func retryPendingChatSend() async {
        guard isFamilyCredentialActive,state == .online,!isSending,!historyMigrationInProgress,
              let configuration,let keys else {return}
        let generation=configurationGeneration
        isSending=true
        defer {isSending=false}
        do {
            let outbox=try openChatOutbox(configuration:configuration,keys:keys)
            applyPendingChatState(try outbox.pending())
            guard pendingChatSendID != nil else {return}
            try await flushChatOutbox(outbox,configuration:configuration,generation:generation)
            if generation==configurationGeneration {lastError=nil}
        } catch {
            guard generation==configurationGeneration else {return}
            lastError="Ausstehender Versand bleibt gesichert. Erneute Zustellung nicht bestätigt; Schlüssel und Zeitfenster beachten."
        }
    }

    private func flushChatOutbox(_ outbox:DurableChatOutbox,configuration:ChatConfiguration,generation:UInt64) async throws {
        func requireCurrent() throws {
            try Task.checkCancellation()
            guard generation==configurationGeneration,self.configuration==configuration,
                  isFamilyCredentialActive,state == .online,!historyMigrationInProgress else {throw CancellationError()}
        }
        try requireCurrent()
        guard let pending=try outbox.pending(),
              let first=pending.entries.first?.envelope,
              messages.contains(where:{$0.id==pending.groupID && $0.direction == .outgoing &&
                $0.senderUserID==configuration.userID &&
                $0.recipientUserID==(first.conversationID=="family" ? "family" : first.recipientUserID) &&
                $0.conversationID==first.conversationID && $0.kind==first.messageType &&
                $0.contentType==first.contentType})
        else {throw ChatHistoryError.invalidArchive}

        if pending.entries.contains(where:{$0.phase != .confirmed}) {
            try await relay.requireIdempotentSender(configuration:configuration)
            try requireCurrent()
            let targets:Set<String>
            if first.conversationID=="family" {
                let group=try await relay.familyGroup(configuration:configuration)
                try requireCurrent()
                guard group.isReady,group.members.contains(where:{$0.userID==configuration.userID}) else {
                    throw ChatError.authenticationFailed
                }
                targets=Set(group.members.map(\.userID).filter{$0 != configuration.userID})
            } else {
                targets=[first.recipientUserID]
            }
            guard targets==Set(pending.recipients.map(\.userID)) else {throw ChatError.identityChanged}
            var recipients:[ChatIdentity]=[]
            for target in targets.sorted() {
                let devices=try await relay.identities(for:target,configuration:configuration)
                try requireCurrent()
                guard !devices.isEmpty,devices.allSatisfy({$0.userID==target}) else {throw ChatError.noRecipientDevice}
                for device in devices {try ChatDeviceKeys.pin(device)}
                recipients+=devices
            }
            while true {
                try requireCurrent()
                guard let envelope=try outbox.beginNext(currentRecipients:recipients,allowIdempotentReplay:true) else {break}
                let receipt=try await relay.sendWithReceipt(envelope,configuration:configuration)
                try requireCurrent()
                try outbox.confirm(envelope,receipt:receipt)
                applyPendingChatState(try outbox.pending())
            }
        }
        try await commitHistoryMutation(generation:generation) {
            guard messages.contains(where:{$0.id==pending.groupID && $0.direction == .outgoing}) else {
                throw ChatHistoryError.invalidArchive
            }
            updateDelivery(id:pending.groupID,to:.queued)
        }
        try requireCurrent()
        try outbox.finishAfterHistoryCommit(groupID:pending.groupID)
        applyPendingChatState(nil)
    }

    func loadMemberTickets() async {
        guard FamilyBootstrapClient.configuredURL() == nil, let configuration, accessRole == .member else { return }
        let generation = configurationGeneration
        do {
            let items = try await relay.memberTickets(configuration: configuration)
            guard generation == configurationGeneration else { return }
            memberTickets = items
        } catch {
            guard generation == configurationGeneration else { return }
            lastError = error.localizedDescription
        }
    }

    func loadMemberTicket(_ id: String) async {
        guard FamilyBootstrapClient.configuredURL() == nil, let configuration, accessRole == .member else { return }
        let generation = configurationGeneration
        do {
            let item = try await relay.memberTicket(id, configuration: configuration)
            guard generation == configurationGeneration else { return }
            memberTicketDetails[id] = item
        } catch {
            guard generation == configurationGeneration else { return }
            lastError = error.localizedDescription
        }
    }

    func replyMemberTicket(_ id: String, message: String) async -> Bool {
        guard FamilyBootstrapClient.configuredURL() == nil, let configuration, accessRole == .member else { return false }
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 4000 else {
            lastError = "Die Antwort muss zwischen 1 und 4.000 Zeichen enthalten."
            return false
        }
        let generation = configurationGeneration
        do {
            let ticket = try await relay.replyMemberTicket(id, text: body, configuration: configuration)
            guard generation == configurationGeneration else { return false }
            memberTicketDetails[id] = ticket
            await loadMemberTickets()
            return true
        } catch {
            guard generation == configurationGeneration else { return false }
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createSupportTicket(message: String) async -> String? {
        guard FamilyBootstrapClient.configuredURL() == nil, let configuration else { return nil }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 4000 else {
            lastError = "Das Ticket muss zwischen 1 und 4.000 Zeichen enthalten."
            return nil
        }
        do {
            lastError = nil
            let ticket = try await relay.createSupportTicket(
                message: normalized,
                configuration: configuration
            )
            lastCreatedTicketID = ticket.id
            memberTicketDetails[ticket.id] = ticket
            await loadMemberTickets()
            return ticket.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func updateRecipientSafetyNumbers() async throws {
        guard let configuration, !recipientUserID.isEmpty else { return }
        let recipients = try await relay.identities(for: recipientUserID, configuration: configuration)
        recipientSafetyNumbers = recipients.compactMap(ChatDeviceKeys.safetyNumber(for:))
    }

    func approveCurrentRecipientKeys() async {
        guard let configuration else { return }
        do {
            let context = LAContext()
            context.localizedCancelTitle = "Abbrechen"
            var policyError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError),
                  try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Neue Chat-Sicherheitsnummern bestätigen"
                  ) else { throw ChatError.authenticationFailed }
            let identities = try await relay.identities(for: recipientUserID, configuration: configuration)
            guard !identities.isEmpty else { throw ChatError.noRecipientDevice }
            try identities.forEach { try ChatDeviceKeys.replacePin(with: $0) }
            recipientSafetyNumbers = identities.compactMap(ChatDeviceKeys.safetyNumber(for:))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The backend dequeues each ciphertext batch on read. Rejecting one
    /// malformed/replayed envelope must not discard later valid ciphertexts
    /// from that *same* already-dequeued batch. Transport failures and task
    /// cancellation remain fatal; decryption/identity failures stay fail-closed.
    static func processReceivedBatch(
        _ envelopes: [ChatEnvelope],
        accepting: (ChatEnvelope) async throws -> Void
    ) async throws -> Int {
        var rejected = 0
        for envelope in envelopes {
            try Task.checkCancellation()
            do {
                try await accepting(envelope)
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as ChatError {
                // Invalid ciphertext is a per-message failure. HTTP/auth
                // failures are *transport* failures and must not be masked.
                switch failure {
                case .invalidEnvelope, .invalidSignature, .identityChanged, .contentTooLarge:
                    rejected += 1
                default:
                    throw failure
                }
            } catch {
                throw error
            }
        }
        return rejected
    }

    private func receiveLoop() async {
        var retryNanoseconds: UInt64 = 500_000_000
        while !Task.isCancelled, let configuration {
            do {
                let ackMode = isFamilyCredentialActive
                let envelopes = try await relay.receive(
                    configuration: configuration, requiresAcknowledgement: ackMode
                )
                try Task.checkCancellation()
                guard self.configuration == configuration else { return }
                let invalidCount = try await Self.processReceivedBatch(envelopes) { envelope in
                    try await self.accept(envelope, configuration: configuration)
                }
                try Task.checkCancellation()
                guard self.configuration == configuration else { return }
                if ackMode && !envelopes.isEmpty {
                    // Verified envelopes are individually checkpointed before
                    // returning from accept(). Previously committed replays
                    // and explicitly rejected ciphertext need no new write.
                    guard historyArchive != nil || historyRecordCheckpoint != nil else { throw ChatHistoryError.missingKey }
                    try await relay.acknowledge(
                        envelopes.map(\.id), configuration: configuration
                    )
                    try Task.checkCancellation()
                    guard self.configuration == configuration else { return }
                }
                if invalidCount > 0 {
                    // Do not report or persist attacker-controlled ciphertext,
                    // decrypted content or detailed crypto errors in UI/logs.
                    lastError = "\(invalidCount) ungültige oder nicht verifizierte Chat-Nachrichten verworfen."
                }
                state = .online
                retryNanoseconds = 500_000_000
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if !familyAudioTransientNetworkError(error) || audioSession == nil {
                    stopAudio()
                }
                state = .offline(error.localizedDescription)
                try? await Task.sleep(nanoseconds: retryNanoseconds)
                retryNanoseconds = min(retryNanoseconds * 2, 8_000_000_000)
            }
        }
        receiveTask = nil
    }

    private func accept(_ envelope: ChatEnvelope, configuration: ChatConfiguration) async throws {
        let generation=configurationGeneration
        let now = Date.now
        guard let envelopeDate = ISO8601DateFormatter().date(from: envelope.createdAt),
              abs(now.timeIntervalSince(envelopeDate)) < 600 else {
            throw ChatError.invalidEnvelope
        }
        guard envelope.recipientUserID == configuration.userID,
              envelope.recipientDeviceID == configuration.deviceID,
              (1...256).contains(envelope.chunkCount),
              envelope.chunkIndex >= 0,
              envelope.chunkIndex < envelope.chunkCount,
              let keys else { throw ChatError.invalidEnvelope }
        // A replay of a checkpointed ID is idempotent. Never infer durability
        // merely from a partially mutated in-memory assembly.
        if let seen = seenEnvelopeIDs[envelope.id], now.timeIntervalSince(seen) < 600 { return }
        let identities = try await relay.identities(for: envelope.senderUserID, configuration: configuration)
        try Task.checkCancellation()
        guard self.configuration == configuration else { throw CancellationError() }
        guard let sender = identities.first(where: { $0.deviceID == envelope.senderDeviceID }) else {
            throw ChatError.invalidEnvelope
        }
        if let conversationID = envelope.conversationID {
            guard conversationID == "family",
                  let familyGroup, familyGroup.isReady,
                  familyGroup.members.contains(where: { $0.userID == envelope.senderUserID }),
                  familyGroup.members.contains(where: { $0.userID == configuration.userID }) else {
                throw ChatError.invalidEnvelope
            }
        }
        try ChatDeviceKeys.pin(sender)
        let plaintext: Data
        do {
            plaintext = try keys.decrypt(envelope, sender: sender)
        } catch let cryptoFailure as ChatError {
            throw cryptoFailure
        } catch {
            // CryptoKit invalid sealed-box/public-key errors must not leak
            // implementation details and must never be mistaken for HTTP
            // relay availability failures.
            throw ChatError.invalidEnvelope
        }
        try await commitHistoryMutation(generation:generation,verifiedEnvelopeIDs:[envelope.id]) {
            try storeVerifiedFragment(envelope, plaintext: plaintext, configuration: configuration,
                                     envelopeDate: envelopeDate, now: now)
        }
    }

    private func storeVerifiedFragment(_ envelope: ChatEnvelope, plaintext: Data,
                                       configuration: ChatConfiguration, envelopeDate: Date, now: Date) throws {
        seenEnvelopeIDs = seenEnvelopeIDs.filter { now.timeIntervalSince($0.value) < 600 }
        if seenEnvelopeIDs[envelope.id] != nil { return }
        if !isFamilyCredentialActive {
            partialMessages = partialMessages.filter { now.timeIntervalSince($0.value.lastUpdated) < 120 }
        }
        // Previously acknowledged partial chunks cannot be silently expired.
        let bufferedBytes = partialMessages.values.reduce(0) { total, partial in
            total + partial.chunks.values.reduce(0) { $0 + $1.count }
        }
        guard plaintext.count <= Self.chunkSize,
              plaintext.count <= (Self.maximumBytes[envelope.messageType] ?? 0) else {
            throw ChatError.contentTooLarge
        }
        let assemblyID = "\(envelope.senderUserID)|\(envelope.senderDeviceID)|\(envelope.groupID)"
        if partialMessages[assemblyID] == nil, partialMessages.count >= 256 {
            if isFamilyCredentialActive { throw ChatHistoryError.capacity }
            throw ChatError.contentTooLarge
        }
        var partial = partialMessages[assemblyID] ?? PartialMessage(
            senderUserID: envelope.senderUserID,
            conversationID: envelope.conversationID,
            kind: envelope.messageType,
            contentType: envelope.contentType,
            createdAt: envelopeDate,
            chunkCount: envelope.chunkCount,
            chunks: [:],
            lastUpdated: now
        )
        guard partial.senderUserID == envelope.senderUserID,
              partial.conversationID == envelope.conversationID,
              partial.kind == envelope.messageType,
              partial.contentType == envelope.contentType,
              partial.createdAt == envelopeDate,
              partial.chunkCount == envelope.chunkCount else { throw ChatError.invalidEnvelope }
        let previous = partial.chunks[envelope.chunkIndex]
        if let previous, previous != plaintext { throw ChatError.invalidEnvelope }
        let additional = previous == nil ? plaintext.count : 0
        let assemblyBytes = partial.chunks.values.reduce(0) { $0 + $1.count }
        guard assemblyBytes + additional <= (Self.maximumBytes[partial.kind] ?? 0) else {
            throw ChatError.contentTooLarge
        }
        guard bufferedBytes + additional < 96 * 1024 * 1024,
              seenEnvelopeIDs.count < 20_000 else {
            if isFamilyCredentialActive { throw ChatHistoryError.capacity }
            throw ChatError.contentTooLarge
        }
        partial.chunks[envelope.chunkIndex] = plaintext
        partial.lastUpdated = now
        partialMessages[assemblyID] = partial
        guard partial.chunks.count == partial.chunkCount else {
            seenEnvelopeIDs[envelope.id] = now
            return
        }
        var complete = Data()
        for index in 0..<partial.chunkCount {
            guard let chunk = partial.chunks[index] else { throw ChatError.invalidEnvelope }
            complete.append(chunk)
        }
        partialMessages.removeValue(forKey: assemblyID)
        guard complete.count <= (Self.maximumBytes[partial.kind] ?? 0) else { throw ChatError.contentTooLarge }
        var receivedMessage = ChatMessage(
            id: envelope.groupID,
            senderUserID: partial.senderUserID,
            recipientUserID: configuration.userID,
            kind: partial.kind,
            contentType: partial.contentType,
            data: complete,
            createdAt: partial.createdAt,
            direction: .incoming,
            delivery: .received
        )
        receivedMessage.conversationID = partial.conversationID
        appendMessage(receivedMessage)
        seenEnvelopeIDs[envelope.id] = now
    }

    private func updateDelivery(id: String, to delivery: ChatMessage.Delivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].delivery = delivery
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        var totalBytes = messages.reduce(0) { $0 + $1.data.count }
        while messages.count > 200 || totalBytes > 160 * 1024 * 1024 {
            guard !messages.isEmpty else { break }
            guard let evict=messages.firstIndex(where:{$0.id != pendingChatSendID}) else {break}
            totalBytes -= messages.remove(at:evict).data.count
        }
    }

    private func restoreConfiguration() {
        // Family deployments must never restore a stale legacy chat bearer
        // before a verified HA user and registered device are established.
        guard FamilyBootstrapClient.configuredURL() == nil else { return }
        guard let endpoint = UserDefaults.standard.string(forKey: endpointKey),
              let url = URL(string: endpoint), isAllowedEndpoint(url),
              let userID = UserDefaults.standard.string(forKey: userKey),
              let recipient = UserDefaults.standard.string(forKey: recipientKey),
              let deviceID = UserDefaults.standard.string(forKey: deviceKey),
              let token = try? KeychainStore.value(account: tokenAccount) else { return }
        recipientUserID = recipient
        configuration = ChatConfiguration(baseURL: url, token: token, userID: userID, deviceID: deviceID)
        state = .connecting
    }

    private func isAllowedEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), url.host != nil else { return false }
#if DEBUG
        return scheme == "https" || scheme == "http"
#else
        return scheme == "https"
#endif
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.allSatisfy { $0.isLetter || $0.isNumber || "-_.@".contains($0) }
    }

    private static func chunks(of data: Data) -> [Data] {
        if data.isEmpty { return [Data()] }
        return stride(from: 0, to: data.count, by: chunkSize).map { offset in
            data.subdata(in: offset..<min(offset + chunkSize, data.count))
        }
    }

    private static func preparedImageData(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw ChatError.unsupportedMedia }
        let maximumDimension: CGFloat = 2_560
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let result = resized.jpegData(compressionQuality: 0.82) else { throw ChatError.unsupportedMedia }
        guard result.count <= (maximumBytes[.image] ?? 0) else { throw ChatError.contentTooLarge }
        return result
    }
}

@MainActor
extension ChatModel {
    func secureTicketScope(_ app: AppModel) -> TicketScreenScope? {
        guard isFamilyCredentialActive, let config = configuration, let keys,
              let family = app.familyChatContext(), let profile = app.registeredFamilyProfile,
              config.userID == family.haUserID, config.deviceID == family.deviceID,
              config.baseURL == family.endpoint,
              app.homeAssistantCurrentUser?.id == config.userID
        else { return nil }
        return TicketScreenScope(endpoint: config.baseURL, user: config.userID,
            device: config.deviceID, owner: profile == .nico, keyFingerprint: keys.safetyNumber)
    }

    private func checkTicketScope(_ scope: TicketScreenScope, _ app: AppModel) throws {
        try Task.checkCancellation()
        guard secureTicketScope(app) == scope else { throw ChatError.authenticationFailed }
    }

    private func ticketAuthorization(_ scope: TicketScreenScope, _ app: AppModel) async throws -> EncryptedTicketAuthorization {
        let (auth,_)=try await ticketAuthorizationWithExpiry(scope,app)
        return auth
    }

    private func ticketAuthorizationWithExpiry(_ scope: TicketScreenScope, _ app: AppModel) async throws -> (EncryptedTicketAuthorization,Date) {
        try checkTicketScope(scope, app)
        let generation=configurationGeneration
        guard let configuration,let family=app.familyChatContext(),
              family.grant.accessToken==configuration.token else { throw ChatError.authenticationFailed }
        if scope.owner {
            let approved = try await app.requestApprovedFamilyOwnerSession()
            try checkTicketScope(scope, app)
            guard generation==configurationGeneration, approved.isValid(haUserID: scope.user, deviceID: scope.device)
            else { throw ChatError.authenticationFailed }
            return (.owner(AdminControlConfiguration(baseURL: scope.endpoint,
                ownerToken: approved.accessToken, ownerDeviceSession: approved.deviceSession),
                userID: scope.user, deviceID: scope.device),
                Date(timeIntervalSince1970:TimeInterval(min(approved.expiresAt,family.grant.expiresAt))))
        }
        return (.member(configuration),Date(timeIntervalSince1970:TimeInterval(family.grant.expiresAt)))
    }

    private func resetTicketReadAccess() {
        ticketReadLease=nil
        ticketCacheReady=false
        ticketReadOffline=false
    }

    func invalidateSecureTicketRead(_ scope:TicketScreenScope) {
        if ticketReadLease?.scope==scope { resetTicketReadAccess() }
    }

    func secureTicketCanRead(_ scope:TicketScreenScope,app:AppModel) -> Bool {
        guard secureTicketScope(app)==scope,let lease=ticketReadLease else {return false}
        return (try? lease.require(scope,generation:configurationGeneration)) != nil
    }

    func secureTicketIsOffline(_ scope:TicketScreenScope,app:AppModel) -> Bool {
        secureTicketCanRead(scope,app:app) && ticketReadOffline
    }

    private func ticketLocalIdentity(_ scope:TicketScreenScope,app:AppModel) throws -> ChatIdentity {
        try checkTicketScope(scope,app)
        guard let keys else {throw ChatError.authenticationFailed}
        return keys.publicIdentity(userID:scope.user,deviceID:scope.device)
    }

    private func fetchSecureTicketList(_ scope:TicketScreenScope,app:AppModel,
                                       auth:EncryptedTicketAuthorization,generation:UInt64) async throws -> [EncryptedTicketSummary] {
        let client = EncryptedTicketClient()
        var result: [EncryptedTicketSummary] = []
        var cursor: String?
        for _ in 0..<21 {
            let page = try await client.list(using: auth, after: cursor)
            try checkTicketScope(scope, app)
            guard generation==configurationGeneration else {throw CancellationError()}
            let local=try ticketLocalIdentity(scope,app:app)
            guard page.tickets.allSatisfy({ (cursor == nil || $0.ticketID > cursor!) &&
                TicketIdentityBinding.matches(local,scope.owner ? $0.owner : $0.requester) }),
                  Set(result.map(\.id)).isDisjoint(with: Set(page.tickets.map(\.id)))
            else { throw ChatError.invalidResponse }
            result.append(contentsOf: page.tickets)
            guard result.count <= 1000 else { throw ChatError.contentTooLarge }
            guard let next = page.nextAfter else { return result }
            guard cursor == nil || next > cursor! else { throw ChatError.invalidResponse }
            cursor = next
        }
        throw ChatError.invalidResponse
    }

    func secureTicketList(_ scope:TicketScreenScope,app:AppModel) async throws -> [EncryptedTicketSummary] {
        let generation=configurationGeneration
        do {
            let (auth,expiry)=try await ticketAuthorizationWithExpiry(scope,app)
            let result=try await fetchSecureTicketList(scope,app:app,auth:auth,generation:generation)
            guard generation==configurationGeneration else {throw CancellationError()}
            let local=try ticketLocalIdentity(scope,app:app)
            let lease=try TicketOfflineLease(scope:scope,verifiedGrantExpiry:expiry,generation:generation)
            ticketCacheReady=false
            do {
                try SecureTicketCache(scope:scope,local:local).replaceList(result,lease:lease)
                ticketCacheReady=true
            } catch {}
            ticketReadLease=lease
            ticketReadOffline=false
            return result
        } catch {
            guard generation==configurationGeneration,!Task.isCancelled else {throw CancellationError()}
            guard TicketOfflineFallbackPolicy.allows(error),ticketCacheReady,
                  secureTicketCanRead(scope,app:app),let lease=ticketReadLease else {
                invalidateSecureTicketRead(scope)
                throw error
            }
            do {
                let local=try ticketLocalIdentity(scope,app:app)
                let result=try SecureTicketCache(scope:scope,local:local).list(lease:lease)
                ticketReadOffline=true
                return result
            } catch {
                invalidateSecureTicketRead(scope)
                throw error
            }
        }
    }

    func readSecureTicketDetail(_ id:String,scope:TicketScreenScope,app:AppModel) async throws -> EncryptedTicketDetail {
        let generation=configurationGeneration
        do {
            let (auth,expiry)=try await ticketAuthorizationWithExpiry(scope,app)
            let result=try await EncryptedTicketClient().detail(id,using:auth)
            guard generation==configurationGeneration else {throw CancellationError()}
            let local=try ticketLocalIdentity(scope,app:app)
            guard TicketIdentityBinding.matches(local,scope.owner ? result.owner : result.requester)
            else {throw ChatError.identityChanged}
            let lease=try TicketOfflineLease(scope:scope,verifiedGrantExpiry:expiry,generation:generation)
            if ticketCacheReady {
                do {try SecureTicketCache(scope:scope,local:local).putDetail(result,lease:lease)}
                catch {ticketCacheReady=false}
            }
            ticketReadLease=lease
            ticketReadOffline=false
            return result
        } catch {
            guard generation==configurationGeneration,!Task.isCancelled else {throw CancellationError()}
            guard TicketOfflineFallbackPolicy.allows(error),ticketCacheReady,
                  secureTicketCanRead(scope,app:app),let lease=ticketReadLease else {
                invalidateSecureTicketRead(scope)
                throw error
            }
            do {
                let local=try ticketLocalIdentity(scope,app:app)
                guard let result=try SecureTicketCache(scope:scope,local:local).detail(id,lease:lease)
                else {throw ChatError.invalidResponse}
                ticketReadOffline=true
                return result
            } catch {
                invalidateSecureTicketRead(scope)
                throw error
            }
        }
    }

    func secureTicketOwnerDevices(_ scope: TicketScreenScope, app: AppModel) async throws -> [ChatIdentity] {
        try checkTicketScope(scope, app)
        guard !scope.owner, let configuration else { throw ChatError.authenticationFailed }
        let roster = try await relay.familyGroup(configuration: configuration)
        try checkTicketScope(scope, app)
        let owners = roster.members.filter { $0.profile == "nico" && $0.chatRegistered }
        guard roster.id == "family", owners.count == 1,
              roster.members.contains(where: { $0.userID == scope.user && $0.profile != "nico" })
        else { throw ChatError.invalidEnvelope }
        let devices = try await relay.identities(for: owners[0].userID, configuration: configuration)
        try checkTicketScope(scope, app)
        guard devices.count <= 20, devices.allSatisfy({
            $0.userID == owners[0].userID && EncryptedTicketMessage.validIdentity($0)
        }), Set(devices.map(\.deviceID)).count == devices.count
        else { throw ChatError.invalidResponse }
        return devices.map(TicketIdentityBinding.canonical)
    }

    func secureTicketDetail(_ id: String, scope: TicketScreenScope, app: AppModel) async throws -> EncryptedTicketDetail {
        let auth = try await ticketAuthorization(scope, app)
        let result = try await EncryptedTicketClient().detail(id, using: auth)
        try checkTicketScope(scope, app)
        guard let keys else { throw ChatError.authenticationFailed }
        let local = keys.publicIdentity(userID: scope.user, deviceID: scope.device)
        guard TicketIdentityBinding.matches(local, scope.owner ? result.owner : result.requester)
        else { throw ChatError.identityChanged }
        return result
    }

    func openSecureTicket(_ detail: EncryptedTicketDetail, number: String,
                          scope: TicketScreenScope, app: AppModel) throws -> [TicketReadableMessage] {
        try checkTicketScope(scope, app)
        guard secureTicketCanRead(scope,app:app),let keys else { throw ChatError.authenticationFailed }
        let local = TicketIdentityBinding.canonical(keys.publicIdentity(userID: scope.user, deviceID: scope.device))
        let requester = TicketIdentityBinding.canonical(detail.requester)
        let owner = TicketIdentityBinding.canonical(detail.owner)
        guard local == (scope.owner ? owner : requester) else { throw ChatError.identityChanged }
        _ = try TicketIdentityBinding.confirmed(scope.owner ? requester : owner, number: number)
        let confirmed = number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return try detail.messages.map { message in
            guard let first = message.copies.first else { throw ChatError.invalidEnvelope }
            let actor = [first.senderUserID, first.senderDeviceID]
            let author: ChatIdentity
            let other: ChatIdentity
            if actor == [requester.userID, requester.deviceID] { author = requester; other = owner }
            else if actor == [owner.userID, owner.deviceID] { author = owner; other = requester }
            else { throw ChatError.invalidEnvelope }
            let plain = try message.open(expectedTicketID: detail.ticketID, author: author,
                counterparty: other, confirmedSafetyNumber: confirmed, local: local, keys: keys)
            return TicketReadableMessage(id: message.messageID, text: plain, own: author == local)
        }
    }

    func prepareSecureTicket(text: String, detail: EncryptedTicketDetail?, peer: ChatIdentity,
                             number: String, scope: TicketScreenScope, app: AppModel) async throws -> TicketPendingSend {
        try checkTicketScope(scope, app)
        guard let keys, let configuration, detail != nil || !scope.owner else { throw ChatError.authenticationFailed }
        let peer = try TicketIdentityBinding.confirmed(peer, number: number)
        let local = TicketIdentityBinding.canonical(keys.publicIdentity(userID: scope.user, deviceID: scope.device))
        if let detail {
            guard TicketIdentityBinding.matches(local, scope.owner ? detail.owner : detail.requester),
                  TicketIdentityBinding.matches(peer, scope.owner ? detail.requester : detail.owner)
            else { throw ChatError.identityChanged }
        } else {
            let devices = try await secureTicketOwnerDevices(scope, app: app)
            guard devices.contains(where: { TicketIdentityBinding.matches($0, peer) }) else { throw ChatError.identityChanged }
        }
        let current = try await relay.identities(for: peer.userID, configuration: configuration)
        try checkTicketScope(scope, app)
        guard current.contains(where: { TicketIdentityBinding.matches($0, peer) }) else { throw ChatError.identityChanged }
        let message = try EncryptedTicketMessage.seal(text: text,
            ticketID: detail?.ticketID ?? UUID().uuidString.lowercased(),
            author: local, counterparty: peer,
            confirmedSafetyNumber: number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), keys: keys)
        return TicketPendingSend(scope: scope, message: message, peer: peer, create: detail == nil)
    }

    func restoreSecureTicketPending(_ scope: TicketScreenScope, app: AppModel) async throws -> TicketPendingSend? {
        _ = try await ticketAuthorization(scope, app)
        try checkTicketScope(scope, app)
        return try SecureTicketOutbox(scope: scope).pending()
    }

    func stageSecureTicket(_ pending: TicketPendingSend, scope: TicketScreenScope, app: AppModel) async throws {
        _ = try await ticketAuthorization(scope, app)
        try checkTicketScope(scope, app)
        try SecureTicketOutbox(scope: scope).stage(pending)
    }

    func submitSecureTicket(_ pending: TicketPendingSend, scope: TicketScreenScope, app: AppModel) async throws -> EncryptedTicketDetail {
        guard pending.scope == scope, let configuration,
              secureTicketCanRead(scope,app:app),!ticketReadOffline else { throw ChatError.authenticationFailed }
        // An ambiguous write may have changed remote history.
        ticketCacheReady=false
        try checkTicketScope(scope, app)
        let current = try await relay.identities(for: pending.peer.userID, configuration: configuration)
        try checkTicketScope(scope, app)
        guard current.contains(where: { TicketIdentityBinding.matches($0, pending.peer) }) else { throw ChatError.identityChanged }
        let auth = try await ticketAuthorization(scope, app)
        try checkTicketScope(scope, app)
        // Reauthenticate the stored signed message against the current key.
        guard let keys, try SecureTicketOutbox(scope: scope).pending() == pending,
              let safety = ChatDeviceKeys.safetyNumber(for: pending.peer) else { throw ChatError.authenticationFailed }
        let local = TicketIdentityBinding.canonical(keys.publicIdentity(userID: scope.user, deviceID: scope.device))
        _ = try pending.message.open(expectedTicketID: pending.message.ticketID, author: local,
            counterparty: pending.peer, confirmedSafetyNumber: safety, local: local, keys: keys)
        let client = EncryptedTicketClient()
        let result: EncryptedTicketDetail
        if pending.create {
            result = try await client.create(pending.message, ownerDeviceID: pending.peer.deviceID, using: auth)
        } else {
            result = try await client.reply(pending.message, using: auth)
        }
        try checkTicketScope(scope, app)
        guard TicketIdentityBinding.matches(scope.owner ? result.owner : result.requester, local),
              TicketIdentityBinding.matches(scope.owner ? result.requester : result.owner, pending.peer)
        else { throw ChatError.identityChanged }
        try SecureTicketOutbox(scope: scope).acknowledge(pending, receipt: result)
        return result
    }

    func secureTicketProjects(_ scope: TicketScreenScope, app: AppModel) async throws -> [String:String] {
        guard scope.owner else { throw ChatError.authenticationFailed }
        _ = try await ticketAuthorization(scope, app)
        try checkTicketScope(scope, app)
        return try SecureTicketProjectStore(scope: scope).read()
    }

    func assignSecureTicketProject(_ projectID: String?, ticket: EncryptedTicketDetail,
                                  scope: TicketScreenScope, app: AppModel) async throws {
        guard scope.owner else { throw ChatError.authenticationFailed }
        let authorized = try await secureTicketDetail(ticket.ticketID, scope: scope, app: app)
        try checkTicketScope(scope, app)
        guard TicketIdentityBinding.matches(authorized.owner, ticket.owner),
              TicketIdentityBinding.matches(authorized.requester, ticket.requester)
        else { throw ChatError.identityChanged }
        try SecureTicketProjectStore(scope: scope).assign(ticketID: authorized.ticketID, projectID: projectID)
    }

    func secureTicketStatus(_ status: EncryptedTicketStatus, id: String,
                            scope: TicketScreenScope, app: AppModel) async throws -> EncryptedTicketDetail {
        guard scope.owner,secureTicketCanRead(scope,app:app),!ticketReadOffline else { throw ChatError.authenticationFailed }
        ticketCacheReady=false
        let auth = try await ticketAuthorization(scope, app)
        let result = try await EncryptedTicketClient().status(status, ticketID: id, using: auth)
        try checkTicketScope(scope, app)
        return result
    }
}
