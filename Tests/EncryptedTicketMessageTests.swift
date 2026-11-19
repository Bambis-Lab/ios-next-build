import XCTest
@testable import IOSNext

final class EncryptedTicketMessageTests: XCTestCase {
    func testBothDevicesCanOpenButForeignDeviceCannot() throws {
        let member = ChatDeviceKeys(agreement: .init(), signing: .init())
        let owner = ChatDeviceKeys(agreement: .init(), signing: .init())
        let foreign = ChatDeviceKeys(agreement: .init(), signing: .init())
        let a = member.publicIdentity(userID: "fixture-gabi", deviceID: "ios-a")
        let b = owner.publicIdentity(userID: "fixture-owner", deviceID: "ios-b")
        let c = foreign.publicIdentity(userID: "fixture-other", deviceID: "ios-c")
        let id = UUID().uuidString.lowercased()
        let message = try EncryptedTicketMessage.seal(text: "Synthetic private ticket", ticketID: id,
            author: a, counterparty: b, confirmedSafetyNumber: owner.safetyNumber, keys: member)
        XCTAssertEqual(try message.open(expectedTicketID: id, author: a, counterparty: b,
            confirmedSafetyNumber: owner.safetyNumber, local: a, keys: member), "Synthetic private ticket")
        XCTAssertEqual(try message.open(expectedTicketID: id, author: a, counterparty: b,
            confirmedSafetyNumber: member.safetyNumber, local: b, keys: owner), "Synthetic private ticket")
        XCTAssertThrowsError(try message.open(expectedTicketID: id, author: a, counterparty: b,
            confirmedSafetyNumber: member.safetyNumber, local: c, keys: foreign))
        XCTAssertThrowsError(try message.open(expectedTicketID: UUID().uuidString.lowercased(), author: a,
            counterparty: b, confirmedSafetyNumber: member.safetyNumber, local: b, keys: owner))
        XCTAssertThrowsError(try message.open(expectedTicketID: id, author: a, counterparty: b,
            confirmedSafetyNumber: "unverified", local: b, keys: owner))
        let reply = try EncryptedTicketMessage.seal(text: "Owner reply", ticketID: id,
            author: b, counterparty: a, confirmedSafetyNumber: member.safetyNumber, keys: owner)
        XCTAssertEqual(try reply.open(expectedTicketID: id, author: b, counterparty: a,
            confirmedSafetyNumber: owner.safetyNumber, local: a, keys: member), "Owner reply")
        let raw = try JSONEncoder().encode(message)
        XCTAssertNil(raw.range(of: Data("Synthetic private ticket".utf8)))
        var copies = message.copies
        copies[0].signature = Data(repeating: 0, count: 64).base64EncodedString()
        let modified = EncryptedTicketMessage(version: 1, ticketID: id,
            messageID: message.messageID, copies: copies)
        XCTAssertThrowsError(try modified.open(expectedTicketID: id, author: a, counterparty: b,
            confirmedSafetyNumber: member.safetyNumber, local: b, keys: owner))
    }
}
