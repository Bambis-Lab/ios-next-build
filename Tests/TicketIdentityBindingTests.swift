import XCTest
@testable import IOSNext

final class TicketIdentityBindingTests: XCTestCase {
    func testTimestampCannotChangeDeviceBindingAndWrongKeyFails() throws {
        let keys = ChatDeviceKeys(agreement: .init(), signing: .init())
        let identity = keys.publicIdentity(userID: "fixture-owner", deviceID: "ios-owner")
        let stamped = ChatIdentity(userID: identity.userID, deviceID: identity.deviceID,
            agreementPublicKey: identity.agreementPublicKey, signingPublicKey: identity.signingPublicKey,
            updatedAt: "2026-11-19T00:00:00Z")
        XCTAssertTrue(TicketIdentityBinding.matches(identity, stamped))
        XCTAssertEqual(try TicketIdentityBinding.confirmed(stamped, number: keys.safetyNumber).updatedAt, nil)
        XCTAssertThrowsError(try TicketIdentityBinding.confirmed(stamped, number: "not-confirmed"))
        let wrong = ChatDeviceKeys(agreement: .init(), signing: .init())
            .publicIdentity(userID: identity.userID, deviceID: identity.deviceID)
        XCTAssertFalse(TicketIdentityBinding.matches(identity, wrong))
    }
}
