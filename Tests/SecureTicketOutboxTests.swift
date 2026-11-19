import Foundation
import XCTest
@testable import IOSNext

final class SecureTicketOutboxTests: XCTestCase {
    @MainActor
    func testExactPendingSurvivesReopenAndOnlyMatchingReceiptClears() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("tickets.enc"), key = Data(repeating: 17, count: 32)
        let actor = ChatDeviceKeys(agreement: .init(), signing: .init())
        let peerKeys = ChatDeviceKeys(agreement: .init(), signing: .init())
        let local = actor.publicIdentity(userID: "fixture-member", deviceID: "ios-member")
        let peer = peerKeys.publicIdentity(userID: "fixture-owner", deviceID: "ios-owner")
        let scope = TicketScreenScope(endpoint: try XCTUnwrap(URL(string: "https://example.invalid")),
            user: local.userID, device: local.deviceID, owner: false, keyFingerprint: actor.safetyNumber)
        let scopeBytes = Data("fixture-scoped-outbox".utf8)
        func open() throws -> SecureTicketOutbox {
            SecureTicketOutbox(scope: scope, archive: try ChatHistoryArchive(file: file, scope: scopeBytes, keyData: key))
        }
        func request(_ text: String) throws -> TicketPendingSend {
            let message = try EncryptedTicketMessage.seal(text: text, ticketID: UUID().uuidString.lowercased(),
                author: local, counterparty: peer, confirmedSafetyNumber: peerKeys.safetyNumber, keys: actor)
            return TicketPendingSend(scope: scope, message: message, peer: peer, create: true)
        }
        let pending = try request("synthetic private ticket")
        let different = try request("different ticket")
        try open().stage(pending)
        XCTAssertEqual(try open().pending(), pending)
        try open().stage(pending)
        XCTAssertThrowsError(try open().stage(different))
        XCTAssertNil(try Data(contentsOf: file).range(of: Data("synthetic private ticket".utf8)))
        let wrong = EncryptedTicketDetail(ticketID: pending.message.ticketID, requester: local,
            owner: peer, status: .open, messages: [different.message])
        XCTAssertThrowsError(try open().acknowledge(pending, receipt: wrong))
        XCTAssertEqual(try open().pending(), pending)
        let correct = EncryptedTicketDetail(ticketID: pending.message.ticketID, requester: local,
            owner: peer, status: .open, messages: [pending.message])
        try open().acknowledge(pending, receipt: correct)
        XCTAssertNil(try open().pending())
        let other = TicketScreenScope(endpoint: scope.endpoint, user: "foreign", device: scope.device,
            owner: false, keyFingerprint: scope.keyFingerprint)
        let foreign = SecureTicketOutbox(scope: other, archive: try ChatHistoryArchive(file: file, scope: scopeBytes, keyData: key))
        XCTAssertThrowsError(try foreign.stage(pending))
    }
}
