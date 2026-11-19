import Foundation
import XCTest
@testable import IOSNext

final class EncryptedTicketClientTests: XCTestCase {
    // Synthetic identities and local URLRequest construction only.
    // This verifies the client contract, not server-side authorization.
    func testV73FiveProfileTicketVisibilityMatrix() throws {
        let url = try XCTUnwrap(URL(string: "https://family.example.invalid/"))
        let keys = (0..<5).map { _ in ChatDeviceKeys(agreement: .init(), signing: .init()) }
        let identities = keys.enumerated().map { index, key in
            key.publicIdentity(userID: "fixture-ha-\(index)", deviceID: "fixture-ios-\(index)")
        }
        let owner = identities[0]
        let ownerAuth = EncryptedTicketAuthorization.owner(
            .init(baseURL: url, ownerToken: "synthetic-owner", ownerDeviceSession: "synthetic-proof"),
            userID: owner.userID, deviceID: owner.deviceID)
        for requesterIndex in 1..<identities.count {
            let requester = identities[requesterIndex]
            XCTAssertTrue(ownerAuth.allows(requester: requester, owner: owner))
            XCTAssertFalse(ownerAuth.allows(requester: owner, owner: owner))
            for memberIndex in 1..<identities.count {
                let member = identities[memberIndex]
                let auth = EncryptedTicketAuthorization.member(.init(
                    baseURL: url, token: "synthetic-member", userID: member.userID, deviceID: member.deviceID))
                XCTAssertEqual(auth.allows(requester: requester, owner: owner),
                               memberIndex == requesterIndex)
                XCTAssertFalse(auth.allows(requester: owner, owner: requester))
            }
            // A mismatched device must not inherit the matching account.
            let mismatched = EncryptedTicketAuthorization.member(.init(
                baseURL: url, token: "synthetic-member", userID: requester.userID, deviceID: owner.deviceID))
            XCTAssertFalse(mismatched.allows(requester: requester, owner: owner))
            let wrongOwnerDevice = keys[0].publicIdentity(userID: owner.userID, deviceID: "foreign-device")
            XCTAssertFalse(ownerAuth.allows(requester: requester, owner: wrongOwnerDevice))
        }
    }

    func testV73AllMemberTicketRoutesRefuseOwnerOperations() throws {
        let url = try XCTUnwrap(URL(string: "https://family.example.invalid/"))
        let ticket = UUID().uuidString.lowercased()
        for index in 1...4 {
            let auth = EncryptedTicketAuthorization.member(.init(
                baseURL: url, token: "synthetic-member", userID: "fixture-ha-\(index)",
                deviceID: "fixture-ios-\(index)"))
            let list = try auth.request(limit: 50)
            XCTAssertEqual(list.url?.path, "/v2/chat/encrypted-tickets")
            XCTAssertNil(list.value(forHTTPHeaderField: "X-Owner-Device-Session"))
            XCTAssertEqual(try auth.request(method: "POST").url?.path, "/v2/chat/encrypted-tickets")
            XCTAssertEqual(try auth.request(ticketID: ticket, action: "messages", method: "POST").url?.path,
                           "/v2/chat/encrypted-tickets/" + ticket + "/messages")
            XCTAssertThrowsError(try auth.request(ticketID: ticket, action: "status", method: "POST"))
            XCTAssertThrowsError(try auth.request(ticketID: ticket, action: "status"))
            XCTAssertThrowsError(try auth.request(ticketID: "../admin", method: "POST"))
            XCTAssertThrowsError(try auth.request(ticketID: ticket, action: "../../admin", method: "POST"))
            XCTAssertThrowsError(try auth.request(ticketID: ticket, method: "DELETE"))
            XCTAssertThrowsError(try auth.request(ticketID: ticket, limit: 50))
        }
    }

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
