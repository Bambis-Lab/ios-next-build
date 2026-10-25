import XCTest
@testable import IOSNext

@MainActor
final class ChatDraftSafetyTests: XCTestCase {
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
