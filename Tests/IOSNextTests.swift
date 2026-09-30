import XCTest
import CryptoKit
@testable import IOSNext

final class IOSNextTests: XCTestCase {
    func testProfileHasStableIdentity() {
        XCTAssertEqual(HomeProfile.timo.id, "timo")
    }

    func testEntityOnState() {
        let entity = HomeAssistantEntity(entityID: "light.example", state: "on", attributes: [:])
        XCTAssertTrue(entity.isOn)
    }

    func testGroupToggleUsesHomeAssistantServiceDomain() {
        let group = HomeAssistantEntity(entityID: "group.nico_beleuchtung", state: "on", attributes: [:])
        let light = HomeAssistantEntity(entityID: "light.example", state: "on", attributes: [:])
        XCTAssertEqual(AppModel.toggleServiceDomain(for: group), "homeassistant")
        XCTAssertEqual(AppModel.toggleServiceDomain(for: light), "light")
    }

    func testEntityPresentationValues() {
        let entity = HomeAssistantEntity(
            entityID: "light.example",
            state: "unavailable",
            attributes: [
                "friendly_name": .string("Testlicht"),
                "brightness": .number(127.5)
            ]
        )
        XCTAssertEqual(entity.domain, "light")
        XCTAssertEqual(entity.displayName, "Testlicht")
        XCTAssertEqual(entity.stateDisplayName, "Nicht verfügbar")
        XCTAssertFalse(entity.isAvailable)
        XCTAssertEqual(try XCTUnwrap(entity.brightness), 0.5, accuracy: 0.0001)
    }

    func testMediaAttributesAreNormalized() {
        let entity = HomeAssistantEntity(
            entityID: "media_player.example",
            state: "playing",
            attributes: [
                "media_title": .string("Titel"),
                "volume_level": .number(1.4)
            ]
        )
        XCTAssertEqual(entity.mediaTitle, "Titel")
        XCTAssertEqual(entity.volumeLevel, 1)
        XCTAssertTrue(entity.isOn)
    }

    func testMediaPowerAndCompanionCapabilitiesAreFailClosed() {
        let paused = HomeAssistantEntity(
            entityID: "media_player.fire_tv_companion",
            state: "paused",
            attributes: [
                "supported_features": .number(Double(128 | 256)),
                "capabilities": .object([
                    "capability_version": .number(2),
                    "launch_apps": .bool(true),
                    "global_navigation": .bool(false)
                ])
            ]
        )
        XCTAssertTrue(paused.isOn)
        XCTAssertTrue(paused.supportsTurnOn)
        XCTAssertTrue(paused.supportsTurnOff)
        XCTAssertTrue(paused.companionSupportsLaunchApps)
        XCTAssertFalse(paused.companionSupportsGlobalNavigation)
        XCTAssertFalse(paused.companionSupportsQueueControl)

        let off = HomeAssistantEntity(
            entityID: "media_player.example",
            state: "off",
            attributes: ["supported_features": .number(Double(128))]
        )
        XCTAssertFalse(off.isOn)
        XCTAssertTrue(off.supportsTurnOn)
        XCTAssertFalse(off.supportsTurnOff)
    }

    func testRunnerCriticalActionsRequireAuthentication() {
        XCTAssertTrue(RunnerAction.gracefulRestart.requiresBiometrics)
        XCTAssertTrue(RunnerAction.shutdown.requiresBiometrics)
        XCTAssertFalse(RunnerAction.healthCheck.requiresBiometrics)
    }

    func testRunnerStatusDecodesOptionalRunnerInventoryAndJobs() throws {
        let data = Data(#"{"vm_online":true,"service_active":true,"registered_runners":2,"idle_runners":1,"busy_runners":1,"runner_instances":[{"id":"runner-01","name":"runner-01","online":true,"busy":false,"labels":["self-hosted","linux"],"operating_system":"Linux","architecture":"x64","current_job_id":null,"last_seen":"2026-09-20T20:10:00Z"},{"id":"runner-02","name":"runner-02","online":true,"busy":true,"current_job_id":"job-123"}],"active_jobs":[{"id":"job-123","name":"iOS Fast Gate","workflow":"ios-fast-gate","repository":"nicofroeba16-cell/iOS-App","branch":"codex/test","runner_id":"runner-02","runner_name":"runner-02","state":"running","started_at":"2026-09-20T20:09:00Z"}]}"#.utf8)
        let status = try CommanderLiveCoding.decoder().decode(RunnerStatus.self, from: data)
        XCTAssertEqual(status.runnerInstances?.count, 2)
        XCTAssertEqual(status.runnerInstances?.first?.name, "runner-01")
        XCTAssertEqual(status.runnerInstances?.last?.currentJobID, "job-123")
        XCTAssertEqual(status.activeJobs?.first?.runnerName, "runner-02")
        XCTAssertEqual(status.activeJobs?.first?.state, "running")
    }

    func testRunnerStatusInventoryExtensionsRemainOptional() throws {
        let data = Data(#"{"vm_online":true,"service_active":true,"registered_runners":1,"idle_runners":1,"busy_runners":0}"#.utf8)
        let status = try CommanderLiveCoding.decoder().decode(RunnerStatus.self, from: data)
        XCTAssertNil(status.runnerInstances)
        XCTAssertNil(status.activeJobs)
    }

    func testAdminMutationsRequireFreshBiometrics() {
        XCTAssertFalse(AdminAction.healthCheck.requiresFreshBiometrics)
        XCTAssertTrue(AdminAction.enableMaintenance.requiresFreshBiometrics)
        XCTAssertTrue(AdminAction.clearCache.requiresFreshBiometrics)
        XCTAssertTrue(AdminAction.createBackup.requiresFreshBiometrics)
    }

    func testChatSessionDecodesServerSideOwnerRole() throws {
        let data = Data(#"{"user_id":"nico","role":"owner"}"#.utf8)
        let session = try JSONDecoder().decode(ChatSession.self, from: data)
        XCTAssertEqual(session.userID, "nico")
        XCTAssertEqual(session.role, .owner)
    }

    func testChatAutoOnboardingModelsDecodeWithoutPresenceMetadata() throws {
        let bootstrapData = Data(
            #"{"user_id":"mika","display_name":"Mika","chat_token":"abcdefghijklmnopqrstuvwxyz1234567890"}"#.utf8
        )
        let bootstrap = try JSONDecoder().decode(ChatBootstrapResponse.self, from: bootstrapData)
        XCTAssertEqual(bootstrap.userID, "mika")
        XCTAssertEqual(bootstrap.displayName, "Mika")

        let contactsData = Data(#"[{"user_id":"nico","display_name":"Nico"}]"#.utf8)
        let contacts = try JSONDecoder().decode([ChatContact].self, from: contactsData)
        XCTAssertEqual(contacts, [ChatContact(userID: "nico", displayName: "Nico")])
    }

    func testLegacyChatMigrationRejectsDifferentHomeAssistantUser() {
        XCTAssertTrue(
            ChatModel.legacyIdentityMatchesHomeAssistant(chatUserID: "mika", displayName: "Mika")
        )
        XCTAssertTrue(
            ChatModel.legacyIdentityMatchesHomeAssistant(chatUserID: "NICO", displayName: "nico")
        )
        XCTAssertFalse(
            ChatModel.legacyIdentityMatchesHomeAssistant(chatUserID: "mika", displayName: "Juli")
        )
        XCTAssertFalse(
            ChatModel.legacyIdentityMatchesHomeAssistant(chatUserID: "mika", displayName: "   ")
        )
    }

    func testAutomaticChatRelayEndpointUsesTailnetAndSafeFallback() throws {
        let tailscaleHA = try XCTUnwrap(URL(string: "https://homeassistant.tailff745a.ts.net"))
        XCTAssertEqual(
            ChatModel.automaticRelayEndpoint(for: tailscaleHA)?.absoluteString,
            "https://iosnext-chat.tailff745a.ts.net/"
        )
        let localHA = try XCTUnwrap(URL(string: "http://192.168.178.63"))
        XCTAssertEqual(
            ChatModel.automaticRelayEndpoint(for: localHA)?.absoluteString,
            "https://iosnext-chat.tailff745a.ts.net/"
        )
    }

    func testSupportTicketDecodesSummaryAndConversation() throws {
        let summaryData = Data(
            #"{"id":"ticket-1","requester_user_id":"mika","status":"open","created_at":"2026-09-16T18:00:00Z","updated_at":"2026-09-16T18:01:00Z","last_message":"Bitte prüfen","suggested_project_id":"fire-tv","dispatched_project_id":null,"dispatch_state":null}"#.utf8
        )
        let summary = try JSONDecoder().decode(SupportTicket.self, from: summaryData)
        XCTAssertEqual(summary.requesterUserID, "mika")
        XCTAssertEqual(summary.lastMessage, "Bitte prüfen")
        XCTAssertNil(summary.messages)
        XCTAssertEqual(summary.suggestedProjectID, "fire-tv")
        XCTAssertNil(summary.dispatchedProjectID)

        let detailData = Data(
            #"{"id":"ticket-1","requester_user_id":"mika","status":"in_progress","created_at":"2026-09-16T18:00:00Z","updated_at":"2026-09-16T18:02:00Z","messages":[{"id":"message-1","author_user_id":"nico","author_role":"owner","body":"Übernommen","created_at":"2026-09-16T18:02:00Z"}]}"#.utf8
        )
        let detail = try JSONDecoder().decode(SupportTicket.self, from: detailData)
        XCTAssertEqual(detail.status, "in_progress")
        XCTAssertEqual(detail.messages?.first?.authorRole, .owner)
        XCTAssertEqual(detail.messages?.first?.body, "Übernommen")
    }

    func testProjectDispatchDecodesApprovalReceipt() throws {
        let routeData = Data(
            #"{"id":"fire-tv","title":"Fire TV Companion","repository":"nicofroeba16-cell/AmazonTV-App"}"#.utf8
        )
        let route = try JSONDecoder().decode(ProjectRoute.self, from: routeData)
        XCTAssertEqual(route.id, "fire-tv")
        XCTAssertEqual(route.repository, "nicofroeba16-cell/AmazonTV-App")

        let dispatchData = Data(
            #"{"id":"dispatch-1","ticket_id":"ticket-1","project_id":"fire-tv","state":"queued","approved_by":"nico","approved_at":"2026-09-16T19:00:00Z","queue_file":"ignored"}"#.utf8
        )
        let dispatch = try JSONDecoder().decode(ProjectDispatch.self, from: dispatchData)
        XCTAssertEqual(dispatch.ticketID, "ticket-1")
        XCTAssertEqual(dispatch.projectID, "fire-tv")
        XCTAssertEqual(dispatch.state, "queued")
    }

    func testTimoProfileContainsOnlyVerifiedFavorites() {
        let definition = ProfileCatalog.definition(for: .timo)
        XCTAssertEqual(definition.favoriteEntityIDs, [
            "light.hintergrund_fernseher",
            "light.nachttisch",
            "light.schlafzimmer",
            "media_player.schlafzimmer"
        ])
    }

    func testOAuthAuthorizationURLUsesNativeRedirect() {
        let configuration = HomeAssistantOAuthConfiguration(
            instanceURL: URL(string: "https://ha.example.com")!,
            clientID: URL(string: "https://example.com/ios-next")!
        )
        let url = try! XCTUnwrap(configuration.authorizationURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(url.path, "/auth/authorize")
        XCTAssertEqual(items?.first(where: { $0.name == "redirect_uri" })?.value, "iosnext://auth")

        let stateURL = try! XCTUnwrap(configuration.authorizationURL(state: "nonce-123"))
        let stateItems = URLComponents(url: stateURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(stateItems?.first(where: { $0.name == "state" })?.value, "nonce-123")
    }

    func testOAuthInstanceURLPolicyAllowsLocalHTTPAndHTTPS() throws {
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://192.168.178.63:8123")?.absoluteString,
            "http://192.168.178.63:8123"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "192.168.178.63:8123")?.absoluteString,
            "http://192.168.178.63:8123"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://homeassistant.local:8123")?.absoluteString,
            "http://homeassistant.local:8123"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "https://ha.example.com")?.absoluteString,
            "https://ha.example.com"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://100.64.0.1")?.absoluteString,
            "http://100.64.0.1"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://100.83.11.105")?.absoluteString,
            "http://100.83.11.105"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://100.127.255.254")?.absoluteString,
            "http://100.127.255.254"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://homeassistant.tailff745a.ts.net")?.absoluteString,
            "http://homeassistant.tailff745a.ts.net"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "https://homeassistant.tailff745a.ts.net")?.absoluteString,
            "https://homeassistant.tailff745a.ts.net"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "homeassistant.tailff745a.ts.net")?.absoluteString,
            "https://homeassistant.tailff745a.ts.net"
        )
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "100.83.11.105")?.absoluteString,
            "https://100.83.11.105"
        )
        XCTAssertNil(HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://100.128.0.1"))
        XCTAssertNil(HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://ts.net"))
        XCTAssertNil(HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://evilts.net"))
        XCTAssertNil(HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "http://ha.example.com"))
        XCTAssertNil(HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: "ftp://192.168.178.63"))
    }

    func testOAuthErrorsIdentifyAuthorizationCallbackAndTokenStages() {
        XCTAssertTrue(HomeAssistantOAuthError.authorizationSessionFailed("offline").localizedDescription.contains("OAuth-Anmeldung"))
        XCTAssertTrue(HomeAssistantOAuthError.callbackMismatch.localizedDescription.contains("OAuth-Rückruf"))
        XCTAssertTrue(HomeAssistantOAuthError.stateMismatch.localizedDescription.contains("OAuth-Rückruf"))
        XCTAssertTrue(HomeAssistantOAuthError.missingAuthorizationCode.localizedDescription.contains("OAuth-Rückruf"))
        XCTAssertTrue(HomeAssistantOAuthError.tokenTransportFailed("offline").localizedDescription.contains("Token-Austausch"))
        XCTAssertTrue(HomeAssistantOAuthError.tokenExchangeFailed(nil).localizedDescription.contains("Token-Austausch"))
        XCTAssertTrue(HomeAssistantOAuthError.tokenExchangeFailed(401).localizedDescription.contains("HTTP 401"))
        XCTAssertTrue(HomeAssistantOAuthError.tokenResponseInvalid.localizedDescription.contains("Token-Austausch"))
    }

    func testOAuthCallbackValidatesSchemeHostAndState() throws {
        let valid = URL(string: "iosnext://auth?code=code-123&state=nonce-123")!
        XCTAssertEqual(
            try HomeAssistantOAuthService.authorizationCode(from: valid, expectedState: "nonce-123"),
            "code-123"
        )

        let wrongHost = URL(string: "iosnext://wrong?code=code-123&state=nonce-123")!
        XCTAssertThrowsError(
            try HomeAssistantOAuthService.authorizationCode(from: wrongHost, expectedState: "nonce-123")
        ) { error in
            XCTAssertEqual(error as? HomeAssistantOAuthError, .callbackMismatch)
        }

        let wrongState = URL(string: "iosnext://auth?code=code-123&state=other")!
        XCTAssertThrowsError(
            try HomeAssistantOAuthService.authorizationCode(from: wrongState, expectedState: "nonce-123")
        ) { error in
            XCTAssertEqual(error as? HomeAssistantOAuthError, .stateMismatch)
        }

        let denied = URL(string: "iosnext://auth?error=access_denied&error_description=Denied&state=nonce-123")!
        XCTAssertThrowsError(
            try HomeAssistantOAuthService.authorizationCode(from: denied, expectedState: "nonce-123")
        ) { error in
            XCTAssertEqual(error as? HomeAssistantOAuthError, .authorizationDenied("Denied"))
        }
    }

    func testProductionOAuthClientIDUsesPublishedPage() {
        XCTAssertEqual(
            HomeAssistantOAuthConfiguration.productionClientID.absoluteString,
            "https://bambis-lab.github.io/ios-next-releases/oauth-client.html"
        )
    }

    func testChatEnvelopeEncryptsSignsAndDecrypts() throws {
        let senderKeys = ChatDeviceKeys(
            agreement: Curve25519.KeyAgreement.PrivateKey(),
            signing: Curve25519.Signing.PrivateKey()
        )
        let recipientKeys = ChatDeviceKeys(
            agreement: Curve25519.KeyAgreement.PrivateKey(),
            signing: Curve25519.Signing.PrivateKey()
        )
        let sender = senderKeys.publicIdentity(userID: "nico", deviceID: "iphone")
        let recipient = recipientKeys.publicIdentity(userID: "mika", deviceID: "ipad")
        let plaintext = Data("Nur im RAM".utf8)
        let envelope = try senderKeys.encrypt(
            plaintext,
            kind: .text,
            contentType: "text/plain",
            groupID: "group-test",
            chunkIndex: 0,
            chunkCount: 1,
            sender: sender,
            recipient: recipient,
            createdAt: "2026-09-16T05:00:00Z"
        )
        let ciphertext = try XCTUnwrap(Data(base64Encoded: envelope.ciphertext))
        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(try recipientKeys.decrypt(envelope, sender: sender), plaintext)
    }

    func testChatEnvelopeRejectsCiphertextTampering() throws {
        let senderKeys = ChatDeviceKeys(
            agreement: Curve25519.KeyAgreement.PrivateKey(),
            signing: Curve25519.Signing.PrivateKey()
        )
        let recipientKeys = ChatDeviceKeys(
            agreement: Curve25519.KeyAgreement.PrivateKey(),
            signing: Curve25519.Signing.PrivateKey()
        )
        let sender = senderKeys.publicIdentity(userID: "nico", deviceID: "iphone")
        let recipient = recipientKeys.publicIdentity(userID: "mika", deviceID: "ipad")
        let envelope = try senderKeys.encrypt(
            Data("Original".utf8),
            kind: .text,
            contentType: "text/plain",
            groupID: "tamper-test",
            chunkIndex: 0,
            chunkCount: 1,
            sender: sender,
            recipient: recipient,
            createdAt: "2026-09-16T05:00:00Z"
        )
        let tampered = ChatEnvelope(
            id: envelope.id,
            groupID: envelope.groupID,
            senderUserID: envelope.senderUserID,
            senderDeviceID: envelope.senderDeviceID,
            recipientUserID: envelope.recipientUserID,
            recipientDeviceID: envelope.recipientDeviceID,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            ciphertext: Data("Manipuliert".utf8).base64EncodedString(),
            signature: envelope.signature,
            messageType: envelope.messageType,
            contentType: envelope.contentType,
            chunkIndex: envelope.chunkIndex,
            chunkCount: envelope.chunkCount,
            createdAt: envelope.createdAt
        )
        XCTAssertThrowsError(try recipientKeys.decrypt(tampered, sender: sender)) { error in
            XCTAssertEqual(error as? ChatError, .invalidSignature)
        }
    }

    func testWireGuardConfigurationAcceptsStrictSubset() throws {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        let configuration = """
        [Interface]
        PrivateKey = \(key)
        Address = 10.44.0.2/32, fd44::2/128
        DNS = 10.44.0.1
        MTU = 1280

        [Peer]
        PublicKey = \(key)
        AllowedIPs = 10.0.0.0/8, fd44::/64
        Endpoint = vpn.example.com:51820
        PersistentKeepalive = 25
        """
        let parsed = try WireGuardConfigurationValidator.validate(configuration)
        XCTAssertEqual(parsed.interface.addresses, ["10.44.0.2/32", "fd44::2/128"])
        XCTAssertEqual(parsed.peers.first?.endpoint, "vpn.example.com:51820")
    }

    func testWireGuardConfigurationRejectsScripts() {
        let key = Data(repeating: 8, count: 32).base64EncodedString()
        let configuration = """
        [Interface]
        PrivateKey = \(key)
        Address = 10.44.0.2/32
        PostUp = curl https://attacker.invalid

        [Peer]
        PublicKey = \(key)
        AllowedIPs = 10.0.0.0/8
        Endpoint = vpn.example.com:51820
        """
        XCTAssertThrowsError(try WireGuardConfigurationValidator.validate(configuration))
    }

    func testWireGuardConfigurationRejectsInvalidAddressAndDuplicatePeer() {
        let key = Data(repeating: 9, count: 32).base64EncodedString()
        let invalidAddress = """
        [Interface]
        PrivateKey = \(key)
        Address = 999.1.1.1/32

        [Peer]
        PublicKey = \(key)
        AllowedIPs = 10.0.0.0/8
        Endpoint = vpn.example.com:51820
        """
        XCTAssertThrowsError(try WireGuardConfigurationValidator.validate(invalidAddress))

        let duplicatePeer = """
        [Interface]
        PrivateKey = \(key)
        Address = 10.44.0.2/32

        [Peer]
        PublicKey = \(key)
        AllowedIPs = 10.0.0.0/8
        Endpoint = vpn-a.example.com:51820

        [Peer]
        PublicKey = \(key)
        AllowedIPs = 192.168.0.0/16
        Endpoint = vpn-b.example.com:51820
        """
        XCTAssertThrowsError(try WireGuardConfigurationValidator.validate(duplicatePeer))
    }
    func testLiveHACardCatalogCoversEveryLiveDashboardType() {
        XCTAssertEqual(
            Set(LiveHACardType.allCases.map(\.rawValue)),
            Set([
                "sections",
                "grid",
                "conditional",
                "template",
                "entity",
                "custom:mushroom-title-card",
                "custom:mushroom-chips-card",
                "custom:mushroom-template-card",
                "custom:navbar-card",
                "custom:battery-state-card",
                "custom:ios-light-card",
                "custom:ios-media-player"
            ])
        )
        XCTAssertEqual(LiveHACardType.allCases.count, 12)
    }

    func testLiveHACardScreenshotPageArguments() {
        XCTAssertEqual(LiveHACardTestModeView.page(from: ["app"]), 0)
        XCTAssertEqual(LiveHACardTestModeView.page(from: ["app", "--live-card-page=1"]), 1)
        XCTAssertEqual(LiveHACardTestModeView.page(from: ["app", "--live-card-page=2"]), 2)
        XCTAssertEqual(LiveHACardTestModeView.page(from: ["app", "--live-card-page=99"]), 0)
    }

    func testHomeAssistantCommandTimeoutBudgets() {
        XCTAssertEqual(HomeAssistantClient.commandTimeoutSeconds(for: "get_states"), 15)
        XCTAssertEqual(HomeAssistantClient.commandTimeoutSeconds(for: "subscribe_events"), 10)
        XCTAssertEqual(HomeAssistantClient.commandTimeoutSeconds(for: "call_service"), 10)
    }

    func testHomeAssistantJSONBridgeKeepsNumericMessageIDsNumeric() throws {
        let payload = try JSONSerialization.jsonObject(
            with: Data(#"{"id":1,"success":true}"#.utf8)
        ) as! [String: Any]

        XCTAssertEqual(JSONValue(any: payload["id"] as Any), .number(1))
        XCTAssertEqual(JSONValue(any: payload["success"] as Any), .bool(true))
    }

    func testReconnectBackoffIncludesBoundedJitter() {
        XCTAssertEqual(AppModel.reconnectDelaySeconds(attempt: 1, jitterFraction: 0), 1, accuracy: 0.001)
        XCTAssertEqual(AppModel.reconnectDelaySeconds(attempt: 5, jitterFraction: 0), 16, accuracy: 0.001)
        XCTAssertEqual(AppModel.reconnectDelaySeconds(attempt: 9, jitterFraction: 0), 30, accuracy: 0.001)
        XCTAssertEqual(AppModel.reconnectDelaySeconds(attempt: 3, jitterFraction: -1), 3.2, accuracy: 0.001)
        XCTAssertEqual(AppModel.reconnectDelaySeconds(attempt: 3, jitterFraction: 1), 4.8, accuracy: 0.001)
    }

    func testProductAcceptanceScreenArguments() {
        XCTAssertEqual(ProductAcceptanceRootView.screen(from: ["app", "--product-ui-test-screen=home"]), .home)
        XCTAssertEqual(ProductAcceptanceRootView.screen(from: ["app", "--product-ui-test-screen=media-detail"]), .mediaDetail)
        XCTAssertEqual(ProductAcceptanceRootView.screen(from: ["app", "--product-ui-test-screen=invalid"]), .home)
    }

    @MainActor
    func testFireTVCompanionPreviewContract() throws {
        let entity = try XCTUnwrap(
            AppModel.preview.entities.first { $0.entityID == "media_player.fire_tv_companion" }
        )
        XCTAssertEqual(entity.domain, "media_player")
        XCTAssertEqual(entity.state, "playing")
        XCTAssertEqual(entity.mediaTitle, "Companion Testfilm")
        XCTAssertEqual(entity.mediaContentType, "video")
        XCTAssertEqual(try XCTUnwrap(entity.volumeLevel), 0.52, accuracy: 0.001)
        XCTAssertEqual(entity.attributes["skip_interval_seconds"]?.numberValue, 10)
    }

    private func fakeHABaseURL(_ mode: String) -> URL {
        let port = ProcessInfo.processInfo.environment["FAKE_HA_PORT"] ?? "18765"
        return URL(string: "http://127.0.0.1:\(port)?mode=\(mode)")!
    }

    private func fakeHAConfiguration(_ mode: String) -> HomeAssistantConfiguration {
        HomeAssistantConfiguration(
            baseURL: fakeHABaseURL(mode),
            accessToken: "integration-test-token"
        )
    }

    func testFakeHAWebSocketConnectAndServiceCall() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        let snapshot = try await client.connect(configuration: fakeHAConfiguration("normal"))
        let states = snapshot.states
        XCTAssertEqual(
            Set(states.map(\.entityID)),
            Set(["light.fake", "media_player.fire_tv_companion"])
        )
        XCTAssertEqual(Set(snapshot.areas.map(\.id)), Set(["living_room", "nico_room"]))
        XCTAssertEqual(snapshot.floors.first?.id, "ground_floor")
        XCTAssertEqual(snapshot.floors.first?.name, "Erdgeschoss")
        XCTAssertEqual(snapshot.floors.first?.level, 0)
        XCTAssertEqual(snapshot.areas.first(where: { $0.id == "living_room" })?.floorID, "ground_floor")
        XCTAssertNil(snapshot.areas.first(where: { $0.id == "nico_room" })?.floorID)
        XCTAssertEqual(snapshot.devices.first(where: { $0.id == "device-firetv" })?.areaID, "living_room")
        XCTAssertEqual(
            snapshot.entityRegistry.first(where: { $0.entityID == "media_player.fire_tv_companion" })?.platform,
            "firetv_companion"
        )

        let fireTV = try XCTUnwrap(
            states.first { $0.entityID == "media_player.fire_tv_companion" }
        )
        XCTAssertEqual(fireTV.mediaContentType, "video")
        XCTAssertEqual(fireTV.attributes["skip_interval_seconds"]?.numberValue, 10)
        XCTAssertEqual(fireTV.companionCapabilityVersion, 2)
        XCTAssertTrue(fireTV.companionSupportsLaunchApps)
        XCTAssertTrue(fireTV.companionSupportsGlobalNavigation)
        XCTAssertTrue(fireTV.companionSupportsQueueControl)
        XCTAssertTrue(fireTV.companionSupportsWakeControl)
        XCTAssertTrue(fireTV.companionSupportsStandbyControl)
        XCTAssertTrue(fireTV.supportsTurnOn)
        XCTAssertTrue(fireTV.supportsTurnOff)

        try await client.callService(
            domain: "light",
            service: "turn_on",
            targetEntityID: "light.fake"
        )
        await client.disconnect()
    }

    func testFakeHAConnectSurvivesUnsupportedRegistryCommands() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        let snapshot = try await client.connect(configuration: fakeHAConfiguration("registry_unsupported"))
        XCTAssertEqual(
            Set(snapshot.states.map(\.entityID)),
            Set(["light.fake", "media_player.fire_tv_companion"])
        )
        XCTAssertTrue(snapshot.floors.isEmpty)
        XCTAssertTrue(snapshot.areas.isEmpty)
        XCTAssertTrue(snapshot.devices.isEmpty)
        XCTAssertTrue(snapshot.entityRegistry.isEmpty)
        await client.disconnect()
    }

    func testFakeHAFireTVCompanionPauseProducesStateEvent() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        _ = try await client.connect(configuration: fakeHAConfiguration("normal"))
        let stream = await client.stateChanges()
        let paused = expectation(description: "Fire TV Companion publishes paused state")

        let observer = Task {
            for await change in stream {
                if change.entityID == "media_player.fire_tv_companion",
                   change.newState?.state == "paused" {
                    paused.fulfill()
                    break
                }
            }
        }

        try await client.callService(
            domain: "media_player",
            service: "media_pause",
            targetEntityID: "media_player.fire_tv_companion"
        )

        await fulfillment(of: [paused], timeout: 4.0)
        observer.cancel()
        await client.disconnect()
    }

    func testFakeHAAuthHandshakeTimeout() async {
        let client = HomeAssistantClient(timing: .integrationTest)

        do {
            _ = try await client.connect(configuration: fakeHAConfiguration("auth_stall"))
            XCTFail("Auth handshake should have timed out.")
        } catch HomeAssistantClientError.timedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected auth timeout error: \(error)")
        }

        await client.disconnect()
    }

    func testFakeHACommandTimeout() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        _ = try await client.connect(configuration: fakeHAConfiguration("call_stall"))

        do {
            try await client.callService(
                domain: "light",
                service: "turn_off",
                targetEntityID: "light.fake"
            )
            XCTFail("Stalled service call should have timed out.")
        } catch HomeAssistantClientError.timedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected command timeout error: \(error)")
        }

        await client.disconnect()
    }

    func testFakeHAHalfOpenConnectionIsDetectedByHeartbeat() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        _ = try await client.connect(configuration: fakeHAConfiguration("no_pong"))
        let stream = await client.stateChanges()
        let finished = expectation(description: "state stream finishes after missing pong")

        let observer = Task {
            for await _ in stream {}
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 4.0)
        observer.cancel()
        await client.disconnect()
    }

    func testFakeHAServerDisconnectFinishesStateStream() async throws {
        let client = HomeAssistantClient(timing: .integrationTest)
        _ = try await client.connect(configuration: fakeHAConfiguration("close_after_subscribe"))
        let stream = await client.stateChanges()
        let finished = expectation(description: "state stream finishes after server disconnect")

        let observer = Task {
            for await _ in stream {}
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 4.0)
        observer.cancel()
        await client.disconnect()
    }

    @MainActor
    func testAppModelReconnectsAfterFakeHAServerDrop() async throws {
        let model = AppModel(
            client: HomeAssistantClient(timing: .integrationTest)
        )
        await model.connect(
            serverURL: fakeHABaseURL("close_once"),
            accessToken: "integration-test-token",
            persist: false
        )

        XCTAssertTrue(model.isConnected, "Initial fake-HA connection must succeed before the drop.")
        XCTAssertEqual(
            model.entities.first(where: {
                $0.entityID == "media_player.fire_tv_companion"
            })?.mediaTitle,
            "Companion Initial"
        )

        var restored = false
        for _ in 0..<200 {
            if model.isConnected,
               model.entities.first(where: {
                   $0.entityID == "media_player.fire_tv_companion"
               })?.mediaTitle == "Companion Reconnected" {
                restored = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(
            restored,
            "Expected AppModel to reconnect and replace the Fire TV Companion snapshot."
        )
        model.disconnect()
    }


    func testMowerPresentationStatesAreNormalizedForUI() {
        let ready = HomeAssistantEntity(entityID: "sensor.mower_status", state: "mode_ready", attributes: [:])
        let docked = HomeAssistantEntity(entityID: "lawn_mower.mower", state: "docked", attributes: [:])
        let returning = HomeAssistantEntity(entityID: "lawn_mower.mower", state: "returning_home", attributes: [:])
        let mowing = HomeAssistantEntity(entityID: "lawn_mower.mower", state: "mowing", attributes: [:])
        XCTAssertEqual(ready.stateDisplayText, "Bereit")
        XCTAssertEqual(docked.stateDisplayText, "In Ladestation")
        XCTAssertEqual(returning.stateDisplayText, "Fährt zur Ladestation")
        XCTAssertTrue(mowing.isOn)
    }

    func testOwnerSuggestedEndpointUsesPrivateHTTPSService() {
        XCTAssertEqual(AdminControlConfiguration.suggestedEndpoint, "https://iosnext-owner.tailff745a.ts.net/")
        XCTAssertTrue(AdminControlConfiguration.suggestedEndpoint.hasPrefix("https://"))
    }

    func testOwnerCapabilitiesFailClosedForFutureBackendFeatures() {
        let registry = OwnerCapabilityRegistry.currentAdminAPI
        XCTAssertTrue(registry.supports(.backendStatus))
        XCTAssertTrue(registry.supports(.tickets))
        XCTAssertTrue(registry.supports(.audit))
        XCTAssertFalse(registry.supports(.workflows))
        XCTAssertFalse(registry.supports(.credentials))
        XCTAssertFalse(registry.supports(.releaseInventory))
    }

    func testOwnerV2CapabilitiesMapIntoExistingNativeSections() {
        let response = AdminCapabilitiesResponse(
            apiVersion: 2,
            modules: ["systems", "operations", "security"],
            capabilities: [
                "backend.status.read",
                "backups.read",
                "workflows.read",
                "credentials.metadata.read",
                "devices.read",
                "releases.read",
                "events.read"
            ],
            actions: []
        )
        let registry = OwnerCapabilityRegistry.discovered(from: response)
        XCTAssertTrue(registry.supports(.backendStatus))
        XCTAssertTrue(registry.supports(.backups))
        XCTAssertTrue(registry.supports(.workflows))
        XCTAssertTrue(registry.supports(.credentials))
        XCTAssertTrue(registry.supports(.devices))
        XCTAssertTrue(registry.supports(.releaseInventory))
        XCTAssertTrue(registry.supports(.notifications))
        XCTAssertFalse(registry.supports(.users))
    }

    func testRemoteCriticalActionPreservesRiskAndBreakGlassRequirement() {
        let action = AdminRemoteAction(
            id: "hypervisor.snapshot.rollback",
            title: "VM Snapshot zurückrollen",
            category: "hypervisor",
            risk: "critical",
            available: true,
            requiresBiometrics: true,
            requiresConfirmation: true,
            requiresBreakGlass: true,
            parameters: [
                AdminActionParameterV2(id: "vm_id", title: "VM", required: true),
                AdminActionParameterV2(id: "snapshot_id", title: "Snapshot", required: true)
            ]
        )
        XCTAssertEqual(action.ownerRiskLevel, .critical)
        XCTAssertTrue(action.requiresBreakGlass)
        XCTAssertEqual(action.parameters?.count, 2)
    }

    func testOwnerRiskModelKeepsSensitiveActionsOutOfSafeClass() {
        XCTAssertEqual(AdminAction.healthCheck.ownerRiskLevel, .safe)
        XCTAssertEqual(AdminAction.createBackup.ownerRiskLevel, .operational)
        XCTAssertEqual(AdminAction.enableMaintenance.ownerRiskLevel, .sensitive)
        XCTAssertEqual(AdminAction.clearCache.ownerRiskLevel, .sensitive)
    }

    func testOwnerPresentationStatesUseTextAndSemanticSymbols() {
        XCTAssertEqual(OwnerConnectionPhase.live.title, "Live")
        XCTAssertEqual(OwnerConnectionPhase.live.symbol, "circle.fill")
        XCTAssertEqual(OwnerConnectionPhase.offline.title, "Owner Backend nicht erreichbar")
        XCTAssertEqual(OwnerConnectionPhase.connecting.title, "Verbindung wird hergestellt …")
    }


    @MainActor
    func testUnavailableV2LegacyActionIsNotConsideredAvailable() {
        let model = AdminControlModel()
        model.v2Capabilities = AdminCapabilitiesResponse(
            apiVersion: 2,
            modules: ["operations"],
            capabilities: ["backups.read"],
            actions: [
                AdminRemoteAction(
                    id: AdminAction.createBackup.rawValue,
                    title: "Backend-Backup erstellen",
                    category: "backup",
                    risk: "operational",
                    available: false,
                    requiresBiometrics: true,
                    requiresConfirmation: true,
                    requiresBreakGlass: false,
                    parameters: []
                )
            ]
        )
        XCTAssertFalse(model.isActionAvailable(.createBackup))
        XCTAssertTrue(model.isActionAvailable(.healthCheck))
    }

    func testLightSegmentBridgeContractIsFailClosed() throws {
        let ready = HomeAssistantEntity(
            entityID: "sensor.segment_bridge",
            state: "ready",
            attributes: [
                "source_entity": .string("light.test"),
                "supported": .bool(true),
                "segment_count": .number(4),
                "segments": .array([.number(0), .number(1), .number(2), .number(3)]),
                "provider": .string("battletron_segments"),
                "ui_enabled": .bool(true),
                "device_write_enabled": .bool(true)
            ]
        )
        let bridge = try XCTUnwrap(ready.lightSegmentBridgeSnapshot)
        XCTAssertTrue(bridge.isReady)
        XCTAssertEqual(bridge.sourceEntityID, "light.test")
        XCTAssertEqual(bridge.segmentIndices, [0, 1, 2, 3])

        let blocked = HomeAssistantEntity(
            entityID: "sensor.segment_bridge_blocked",
            state: "ready",
            attributes: [
                "source_entity": .string("light.test"),
                "supported": .bool(true),
                "segment_count": .number(4),
                "ui_enabled": .bool(true),
                "device_write_enabled": .bool(false)
            ]
        )
        XCTAssertFalse(try XCTUnwrap(blocked.lightSegmentBridgeSnapshot).isReady)
    }

    @MainActor
    func testAppModelFindsOnlyReadySegmentBridgeForLight() throws {
        let model = AppModel()
        let light = HomeAssistantEntity(
            entityID: "light.segmented",
            state: "on",
            attributes: ["supported_color_modes": .array([.string("rgb")])]
        )
        let bridge = HomeAssistantEntity(
            entityID: "sensor.segment_bridge",
            state: "ready",
            attributes: [
                "source_entity": .string(light.entityID),
                "supported": .bool(true),
                "segment_count": .number(3),
                "segments": .array([.number(0), .number(1), .number(2)]),
                "ui_enabled": .bool(true),
                "device_write_enabled": .bool(true)
            ]
        )
        model.entities = [light, bridge]
        XCTAssertEqual(try XCTUnwrap(model.lightSegmentBridge(for: light)).segmentCount, 3)
    }

    func testLightColorFavoritesAreBoundedAndDeduplicated() throws {
        let suite = "IOSNextTests.LightFavorites.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entityID = "light.favorite-test"

        _ = LightColorFavoritesStore.add(.init(red: 1, green: 0, blue: 0), for: entityID, defaults: defaults)
        _ = LightColorFavoritesStore.add(.init(red: 1, green: 0, blue: 0), for: entityID, defaults: defaults)
        XCTAssertEqual(LightColorFavoritesStore.favorites(for: entityID, defaults: defaults).count, 1)

        for index in 0..<8 {
            _ = LightColorFavoritesStore.add(
                .init(red: Double(index) / 10, green: 0.4, blue: 0.8),
                for: entityID,
                defaults: defaults
            )
        }
        XCTAssertEqual(LightColorFavoritesStore.favorites(for: entityID, defaults: defaults).count, 6)
    }

    @MainActor
    func testJuliFireTVBindingNeverFallsBackToAndroidTV() {
        let model = AppModel()
        model.areas = [HomeAssistantArea(id: "juli_zimmer", name: "Juli Zimmer")]
        model.devices = [
            HomeAssistantDevice(id: "juli-adb", name: "Fire TV 192.168.178.75", areaID: "juli_zimmer")
        ]
        model.entityRegistry = [
            HomeAssistantRegistryEntity(
                entityID: "media_player.juli_zimmer_fire_tv_192_168_178_75",
                deviceID: "juli-adb",
                areaID: nil,
                platform: "androidtv"
            )
        ]
        model.entities = [
            HomeAssistantEntity(
                entityID: "media_player.juli_zimmer_fire_tv_192_168_178_75",
                state: "playing",
                attributes: [:]
            )
        ]

        XCTAssertNil(model.fireTVCompanion(inArea: "juli_zimmer"))

        model.devices.append(
            HomeAssistantDevice(id: "juli-companion", name: "Fire TV Companion", areaID: "juli_zimmer")
        )
        model.entityRegistry.append(
            HomeAssistantRegistryEntity(
                entityID: "media_player.fire_tv_companion_3",
                deviceID: "juli-companion",
                areaID: nil,
                platform: "firetv_companion"
            )
        )
        model.entities.append(
            HomeAssistantEntity(
                entityID: "media_player.fire_tv_companion_3",
                state: "idle",
                attributes: [:]
            )
        )

        XCTAssertEqual(
            model.fireTVCompanion(inArea: "juli_zimmer")?.entityID,
            "media_player.fire_tv_companion_3"
        )
    }

    @MainActor
    func testResourceMetricsDoNotMixDevicesAndEntities() {
        let model = AppModel()
        model.areas = [HomeAssistantArea(id: "yard", name: "Rasen")]
        model.devices = [
            HomeAssistantDevice(id: "mower-device", name: "Mäher", areaID: "yard"),
            HomeAssistantDevice(id: "weather-device", name: "Wetter", areaID: "yard")
        ]
        model.entityRegistry = [
            HomeAssistantRegistryEntity(entityID: "switch.mower_power", deviceID: "mower-device", areaID: nil, platform: "test"),
            HomeAssistantRegistryEntity(entityID: "sensor.mower_status", deviceID: "mower-device", areaID: nil, platform: "test"),
            HomeAssistantRegistryEntity(entityID: "sensor.temperature", deviceID: "weather-device", areaID: nil, platform: "test")
        ]
        model.entities = [
            HomeAssistantEntity(entityID: "switch.mower_power", state: "on", attributes: [:]),
            HomeAssistantEntity(entityID: "sensor.mower_status", state: "mode_ready", attributes: [:]),
            HomeAssistantEntity(entityID: "sensor.temperature", state: "21.4", attributes: ["unit_of_measurement": .string("°C")])
        ]

        let metrics = model.resourceMetrics(inArea: "yard")
        XCTAssertEqual(metrics.deviceCount, 2)
        XCTAssertEqual(metrics.activeDeviceCount, 1)
        XCTAssertEqual(metrics.entityCount, 3)
        XCTAssertEqual(metrics.activeEntityCount, 1)
        XCTAssertEqual(metrics.unavailableEntityCount, 0)
    }


    func testMotionMasterTimelineContract() {
        XCTAssertEqual(IOSNextMotionSequence.masterFramesPerSecond, 120, accuracy: 0.0001)
        XCTAssertEqual(IOSNextMotionSequence.startup.frameCount, 87)
        XCTAssertEqual(IOSNextMotionSequence.startup.lastFrame, 86)
        XCTAssertEqual(IOSNextMotionSequence.startup.duration, 86.0 / 120.0, accuracy: 0.000001)
        XCTAssertEqual(IOSNextMotionSequence.controlCenterUnlock.frameCount, 109)
        XCTAssertEqual(IOSNextMotionSequence.controlCenterUnlock.lastFrame, 108)
        XCTAssertEqual(IOSNextMotionSequence.controlCenterUnlock.duration, 0.9, accuracy: 0.000001)
    }

    func testStartupMotionKeyframesAreDeterministic() {
        let start = IOSNextMasterMotion.startup(frame: 0)
        XCTAssertEqual(start.contentOpacity, 0, accuracy: 0.000001)
        XCTAssertEqual(start.backdropOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(start.logoScale, 1, accuracy: 0.000001)
        XCTAssertEqual(start.logoOpacity, 0, accuracy: 0.000001)

        let logoVisible = IOSNextMasterMotion.startup(frame: 14)
        XCTAssertEqual(logoVisible.logoOpacity, 1, accuracy: 0.000001)

        let halo = IOSNextMasterMotion.startup(frame: 22)
        XCTAssertEqual(halo.haloOpacity, 0.14, accuracy: 0.000001)
        XCTAssertEqual(halo.haloDiameter, 184, accuracy: 0.000001)

        let compressed = IOSNextMasterMotion.startup(frame: 32)
        XCTAssertEqual(compressed.logoScale, 0.965, accuracy: 0.000001)

        let expanded = IOSNextMasterMotion.startup(frame: 45)
        XCTAssertEqual(expanded.logoScale, 1, accuracy: 0.000001)
        XCTAssertEqual(expanded.glassWidthFraction, 0.93, accuracy: 0.000001)

        let revealed = IOSNextMasterMotion.startup(frame: 72)
        XCTAssertEqual(revealed.contentOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(revealed.backdropOpacity, 0, accuracy: 0.000001)
        XCTAssertEqual(revealed.glassOpacity, 0, accuracy: 0.000001)
    }

    func testControlCenterUnlockKeyframesAreDeterministic() {
        let start = IOSNextMasterMotion.controlCenterUnlock(frame: 0)
        XCTAssertEqual(start.lockScale, 1, accuracy: 0.000001)
        XCTAssertEqual(start.lockOpacity, 1, accuracy: 0.000001)

        let compressed = IOSNextMasterMotion.controlCenterUnlock(frame: 8)
        XCTAssertEqual(compressed.lockScale, 0.94, accuracy: 0.000001)

        let opened = IOSNextMasterMotion.controlCenterUnlock(frame: 20)
        XCTAssertEqual(opened.lockOpenProgress, 1, accuracy: 0.000001)

        let dissolved = IOSNextMasterMotion.controlCenterUnlock(frame: 38)
        XCTAssertEqual(dissolved.lockOpacity, 0, accuracy: 0.000001)
        XCTAssertEqual(dissolved.lockBlur, 6, accuracy: 0.000001)

        let glass = IOSNextMasterMotion.controlCenterUnlock(frame: 58)
        XCTAssertEqual(glass.glassWidthFraction, 0.94, accuracy: 0.000001)
        XCTAssertEqual(glass.glassHeight, 202, accuracy: 0.000001)

        let modules = IOSNextMasterMotion.controlCenterUnlock(frame: 83)
        XCTAssertEqual(modules.moduleReveal(index: 4), 1, accuracy: 0.000001)

        let ready = IOSNextMasterMotion.controlCenterUnlock(frame: 108)
        XCTAssertEqual(ready.readyOpacity, 1, accuracy: 0.000001)
        XCTAssertEqual(ready.readyScale, 1, accuracy: 0.000001)
    }

}
