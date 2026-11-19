import Foundation
import XCTest
@testable import IOSNext

final class EncryptedTicketClientTests: XCTestCase {
    func testSeparateRoleRoutesAndOwnerProof() throws {
        let url = try XCTUnwrap(URL(string: "https://family.example.invalid/"))
        let member = EncryptedTicketAuthorization.member(.init(baseURL: url, token: "synthetic-member",
            userID: "ha-member", deviceID: "ios-member"))
        let request = try member.request(limit: 50)
        XCTAssertEqual(request.url?.path, "/v2/chat/encrypted-tickets")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Owner-Device-Session"))
        let id = UUID().uuidString.lowercased()
        XCTAssertThrowsError(try member.request(ticketID: id, action: "status", method: "POST"))
        XCTAssertThrowsError(try member.request(ticketID: "../admin"))
        XCTAssertThrowsError(try member.request(limit: 101))
        let owner = EncryptedTicketAuthorization.owner(.init(baseURL: url, ownerToken: "synthetic-owner",
            ownerDeviceSession: "synthetic-proof"), userID: "ha-owner", deviceID: "ios-owner")
        let status = try owner.request(ticketID: id, action: "status", method: "POST")
        XCTAssertEqual(status.url?.path, "/v2/admin/encrypted-tickets/" + id + "/status")
        XCTAssertEqual(status.value(forHTTPHeaderField: "X-Owner-Device-Session"), "synthetic-proof")
        XCTAssertThrowsError(try owner.request(method: "POST"))
        let missing = EncryptedTicketAuthorization.owner(.init(baseURL: url, ownerToken: "synthetic-owner"),
            userID: "ha-owner", deviceID: "ios-owner")
        XCTAssertThrowsError(try missing.request())
        let insecure = EncryptedTicketAuthorization.member(.init(baseURL: URL(string: "http://example.invalid/")!,
            token: "synthetic-member", userID: "ha-member", deviceID: "ios-member"))
        XCTAssertThrowsError(try insecure.request())
    }
}
