import Foundation
import XCTest
@testable import IOSNext

@MainActor
final class ChatDraftSafetyTests: XCTestCase {
    func testQuietFamilyChatLongPollDoesNotTimeoutBeforeBackendResponse() {
        XCTAssertEqual(ChatRelayPollingPolicy.serverWaitSeconds, 25)
        XCTAssertGreaterThan(
            ChatRelayPollingPolicy.longPollRequestTimeout,
            Double(ChatRelayPollingPolicy.serverWaitSeconds) + 10,
            "A healthy empty 25-second backend wait must not turn Chat offline"
        )
        XCTAssertGreaterThan(
            ChatRelayPollingPolicy.sessionResourceTimeout,
            ChatRelayPollingPolicy.longPollRequestTimeout,
            "The URLSession resource timeout may not preempt an authenticated long-poll request"
        )
        XCTAssertEqual(
            ChatRelayPollingPolicy.timeout(
                for: "v1/chat/messages?recipient_device_id=ios-mika&wait=25&limit=64",
                method: "GET"
            ),
            ChatRelayPollingPolicy.longPollRequestTimeout
        )
    }

    func testOnlyAuthenticatedMessageReceiveLongPollGetsExtendedTimeout() {
        for path in [
            "v1/chat/session",
            "v1/chat/contacts",
            "v1/chat/identities/ha-gabi",
            "v1/chat/messages",
            "v1/chat/messages?recipient_device_id=ios-mika&wait=0&limit=64",
            "v1/chat/messages?recipient_device_id=ios-mika&wait=24&limit=64",
            "v1/chat/tickets",
            "v2/family/challenge"
        ] {
            XCTAssertEqual(
                ChatRelayPollingPolicy.timeout(for: path, method: "GET"),
                ChatRelayPollingPolicy.ordinaryRequestTimeout,
                "Unrelated request must keep its short timeout: \(path)"
            )
        }
        XCTAssertEqual(
            ChatRelayPollingPolicy.timeout(
                for: "v1/chat/messages?recipient_device_id=ios-mika&wait=25&limit=64",
                method: "POST"
            ),
            ChatRelayPollingPolicy.ordinaryRequestTimeout,
            "Sending E2EE messages must not silently inherit 42-second long-poll timeouts"
        )
    }

    private func batchEnvelope(_ id: String) -> ChatEnvelope {
        ChatEnvelope(
            id: id, groupID: "group-1",
            senderUserID: "ha-mika", senderDeviceID: "ios-mika",
            recipientUserID: "ha-nico", recipientDeviceID: "ios-nico",
            ephemeralPublicKey: "", ciphertext: "", signature: "",
            messageType: .text, contentType: "text/plain",
            chunkIndex: 0, chunkCount: 1, createdAt: "2026-10-25T11:00:00Z"
        )
    }

    func testBadEncryptedEnvelopeDoesNotDropLaterValidMessagesFromDequeuedBatch() async throws {
        // The backend relay deletes ciphertext on batch delivery. Processing
        // must continue after a rejected signature, never decrypt it or
        // permanently lose the subsequent valid envelopes in that batch.
        let items = [
            batchEnvelope("invalid-signature"),
            batchEnvelope("valid-1"),
            batchEnvelope("valid-2"),
        ]
        var accepted: [String] = []
        let rejected = try await ChatModel.processReceivedBatch(items) { envelope in
            if envelope.id == "invalid-signature" { throw ChatError.invalidSignature }
            accepted.append(envelope.id)
        }
        XCTAssertEqual(rejected, 1)
        XCTAssertEqual(accepted, ["valid-1", "valid-2"])
    }

    func testRelayAuthorizationFailureIsNotMisclassifiedAsCorruptCiphertext() async {
        let items = [batchEnvelope("unauthorized"), batchEnvelope("would-not-process")]
        var accepted: [String] = []
        do {
            _ = try await ChatModel.processReceivedBatch(items) { envelope in
                if envelope.id == "unauthorized" { throw ChatError.rejected(401) }
                accepted.append(envelope.id)
            }
            XCTFail("Relay 401 must fail the receive loop, not falsely report online")
        } catch ChatError.rejected(401) {
            XCTAssertTrue(accepted.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
    }

    func testNetworkTimeoutIsNotMisclassifiedAsCorruptCiphertext() async {
        let items = [batchEnvelope("timed-out"), batchEnvelope("would-not-process")]
        var accepted: [String] = []
        do {
            _ = try await ChatModel.processReceivedBatch(items) { envelope in
                if envelope.id == "timed-out" { throw URLError(.timedOut) }
                accepted.append(envelope.id)
            }
            XCTFail("Network timeout must remain a transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
            XCTAssertTrue(accepted.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
    }

    func testBatchCancellationPropagatesInsteadOfBeingSwallowedAsInvalidMessage() async {
        let items = [batchEnvelope("valid"), batchEnvelope("cancel"), batchEnvelope("must-not-process")]
        var accepted: [String] = []
        do {
            _ = try await ChatModel.processReceivedBatch(items) { envelope in
                if envelope.id == "cancel" { throw CancellationError() }
                accepted.append(envelope.id)
            }
            XCTFail("Cancellation must abort the batch and not report online")
        } catch is CancellationError {
            XCTAssertEqual(accepted, ["valid"])
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testChatRelayAlwaysRefusesTokenBearingHTTPRedirects() throws {
        let delegate = ChatRelayNoRedirects()
        let source = try XCTUnwrap(URL(string: "https://family.example.invalid/v1/chat/contacts"))
        let untrusted = try XCTUnwrap(URL(string: "https://untrusted.example.invalid/collect"))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: source)
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        for status in [301, 302, 307, 308] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: source, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Location": untrusted.absoluteString]
            ))
            var redirectWasConsidered = false
            var forwarded: URLRequest?
            delegate.urlSession(
                session, task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: untrusted)
            ) { candidate in
                redirectWasConsidered = true
                forwarded = candidate
            }
            XCTAssertTrue(redirectWasConsidered)
            XCTAssertNil(forwarded, "Chat or HA bearer may not follow HTTP redirect \(status)")
        }
    }

    func testFamilyContactsAreNeverInventedWhenBrokerDiscoveryFails() {
        XCTAssertFalse(ChatContactDiscoveryPolicy.mayUseLegacyRecipient(
            statusCode: 404, familyCredentialActive: true
        ))
        XCTAssertFalse(ChatContactDiscoveryPolicy.mayUseLegacyRecipient(
            statusCode: 401, familyCredentialActive: false
        ))
        XCTAssertFalse(ChatContactDiscoveryPolicy.mayUseLegacyRecipient(
            statusCode: 503, familyCredentialActive: false
        ))
        XCTAssertTrue(ChatContactDiscoveryPolicy.mayUseLegacyRecipient(
            statusCode: 404, familyCredentialActive: false
        ))
    }

    func testNicoOwnerTicketEntryUsesVerifiedIdentityNotElevatedChatToken() {
        // The Owner inbox is independent from the Chat relay; the tap still
        // enters AdminAreaView which requires a separate approved P-256 Owner
        // device session before showing or mutating Owner tickets.
        XCTAssertTrue(ChatTicketVisibilityPolicy.ownerEntry(
            familyBrokerConfigured: true, verifiedProfile: .nico
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.memberEntry(
            familyBrokerConfigured: true, verifiedProfile: .nico, chatRole: .member
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.ownerEntry(
            familyBrokerConfigured: true, verifiedProfile: nil
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.ownerEntry(
            familyBrokerConfigured: true, verifiedProfile: .gabi
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.ownerEntry(
            familyBrokerConfigured: false, verifiedProfile: .nico
        ))
        // No Chat token is required for the *navigation link*: Owner rights
        // remain exclusively in the independently authorized backend.
        XCTAssertTrue(ChatTicketVisibilityPolicy.ownerEntry(
            familyBrokerConfigured: true, verifiedProfile: .nico
        ))
    }

    func testMemberTicketsRequireVerifiedMemberWhenFamilyBrokerIsConfigured() {
        XCTAssertTrue(ChatTicketVisibilityPolicy.memberEntry(
            familyBrokerConfigured: true, verifiedProfile: .gabi, chatRole: .member
        ))
        XCTAssertTrue(ChatTicketVisibilityPolicy.memberEntry(
            familyBrokerConfigured: true, verifiedProfile: .timo, chatRole: .member
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.memberEntry(
            familyBrokerConfigured: true, verifiedProfile: nil, chatRole: .member
        ))
        XCTAssertFalse(ChatTicketVisibilityPolicy.memberEntry(
            familyBrokerConfigured: true, verifiedProfile: .nico, chatRole: .owner
        ))
    }

    func testDraftIsPreservedWhenNoContactSelected() async {
        let chat = ChatModel()
        chat.recipientUserID = ""
        chat.draft = "  important message  "
        await chat.sendDraft()
        XCTAssertEqual(chat.draft, "  important message  ")
        XCTAssertEqual(chat.lastError, "Bitte zuerst einen Chat-Kontakt auswählen.")
        XCTAssertTrue(chat.messages.isEmpty)
    }

    func testOutgoingAndIncomingMessagesStayWithTheirOwnContact() {
        let chat = ChatModel()
        let mika = ChatContact(userID: "ha-mika", displayName: "Mika")
        let juli = ChatContact(userID: "ha-juli", displayName: "Juli")
        chat.selectContact(mika)
        chat.messages = [
            ChatMessage(id: "m-out", senderUserID: "ha-nico", recipientUserID: "ha-mika",
                        kind: .text, contentType: "text/plain", data: Data("M".utf8),
                        createdAt: .now, direction: .outgoing, delivery: .queued),
            ChatMessage(id: "j-in", senderUserID: "ha-juli", recipientUserID: "ha-nico",
                        kind: .text, contentType: "text/plain", data: Data("J".utf8),
                        createdAt: .now, direction: .incoming, delivery: .received),
            ChatMessage(id: "j-out", senderUserID: "ha-nico", recipientUserID: "ha-juli",
                        kind: .text, contentType: "text/plain", data: Data("J2".utf8),
                        createdAt: .now, direction: .outgoing, delivery: .queued)
        ]
        XCTAssertEqual(chat.visibleMessages.map(\.id), ["m-out"])
        chat.selectContact(juli)
        XCTAssertEqual(chat.visibleMessages.map(\.id), ["j-in", "j-out"])
    }

    func testContactDraftsDoNotBleedAcrossConversationsOrAccountReset() {
        let chat = ChatModel()
        let mika = ChatContact(userID: "ha-mika", displayName: "Mika")
        let juli = ChatContact(userID: "ha-juli", displayName: "Juli")
        chat.selectContact(mika)
        chat.draft = "An Mika"
        chat.selectContact(juli)
        XCTAssertEqual(chat.draft, "")
        chat.draft = "An Juli"
        chat.selectContact(mika)
        XCTAssertEqual(chat.draft, "An Mika")
        chat.selectContact(juli)
        XCTAssertEqual(chat.draft, "An Juli")
        chat.forgetConfiguration()
        chat.selectContact(mika)
        XCTAssertEqual(chat.draft, "")
    }


    func testSignedFamilyGroupContextSeparatesMessagesFromDirectChats() throws {
        let chat = ChatModel()
        let profiles = ["nico", "gabi", "timo", "mika", "juli"]
        let members = profiles.map {
            ChatFamilyGroup.Member(userID: "ha-\($0)", profile: $0, chatRegistered: true)
        }
        chat.familyGroup = ChatFamilyGroup(id: "family", title: "Familie",
                                           members: members, maxParticipants: 5)
        XCTAssertEqual(chat.familyGroup?.isReady, true)
        chat.selectFamilyGroup()
        XCTAssertTrue(chat.showingFamilyGroup)
        var message = ChatMessage(id: "g1", senderUserID: "ha-mika",
                                  recipientUserID: "ha-nico", kind: .text,
                                  contentType: "text/plain", data: Data("Hallo Familie".utf8),
                                  createdAt: .now, direction: .incoming, delivery: .received)
        message.conversationID = "family"
        chat.messages = [message]
        XCTAssertEqual(chat.visibleMessages.map(\.id), ["g1"])
        chat.selectContact(ChatContact(userID: "ha-mika", displayName: "Mika"))
        XCTAssertTrue(chat.visibleMessages.isEmpty)
    }

    func testFamilyGroupDoesNotPretendUnregisteredMemberCanReceive() {
        let profiles = ["nico", "gabi", "timo", "mika", "juli"]
        var members = profiles.map {
            ChatFamilyGroup.Member(userID: "ha-\($0)", profile: $0, chatRegistered: $0 != "juli")
        }
        let group = ChatFamilyGroup(id: "family", title: "Familie",
                                    members: members, maxParticipants: 5)
        XCTAssertFalse(group.isReady)
        members.removeLast()
        XCTAssertFalse(ChatFamilyGroup(id: "family", title: "Familie",
                                      members: members, maxParticipants: 5).isReady)
    }


    func testInboxPreviewsRemainIsolatedAcrossDirectAndFamilyChats() {
        var family = ChatMessage(
            id: "family-message", senderUserID: "ha-mika", recipientUserID: "ha-nico",
            kind: .text, contentType: "text/plain", data: Data("Alle".utf8),
            createdAt: .now, direction: .incoming, delivery: .received
        )
        family.conversationID = "family"
        let mika = ChatMessage(
            id: "mika-message", senderUserID: "ha-mika", recipientUserID: "ha-nico",
            kind: .text, contentType: "text/plain", data: Data("Privat Mika".utf8),
            createdAt: .now, direction: .incoming, delivery: .received
        )
        let juli = ChatMessage(
            id: "juli-message", senderUserID: "ha-nico", recipientUserID: "ha-juli",
            kind: .text, contentType: "text/plain", data: Data("Privat Juli".utf8),
            createdAt: .now, direction: .outgoing, delivery: .queued
        )
        let items = [family, mika, juli]
        XCTAssertEqual(ChatInboxPolicy.previewText(items, peerUserID: nil), "Alle")
        XCTAssertEqual(ChatInboxPolicy.previewText(items, peerUserID: "ha-mika"), "Privat Mika")
        XCTAssertEqual(ChatInboxPolicy.previewText(items, peerUserID: "ha-juli"), "Privat Juli")
        XCTAssertEqual(ChatInboxPolicy.previewText(items, peerUserID: "ha-timo"), "Noch keine Nachrichten")
    }


}
