import XCTest
@testable import IOSNext

@MainActor
final class ChatDraftSafetyTests: XCTestCase {
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

}
