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
}
