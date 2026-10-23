import XCTest
@testable import IOSNext

final class FamilyIdentityTests: XCTestCase {
    private func result(
        userID: String, profile: HomeProfile, role: String, deviceID: String = "ios-member",
        approval: String = "not_available"
    ) -> FamilyRegistration {
        FamilyRegistration(
            haUserID: userID, profile: profile, role: role,
            deviceID: deviceID, ownerAuthorization: approval
        )
    }

    func testMikaAndJuliAreRecognizedAsMembers() {
        for profile in [HomeProfile.mika, .juli] {
            let value = result(userID: "stable-ha-id", profile: profile, role: "member")
            XCTAssertTrue(value.isValid(for: "stable-ha-id", expectedDeviceID: "ios-member"))
        }
    }

    func testNicoCannotBecomeOwnerFromMemberRole() {
        let forged = result(userID: "ha-mika", profile: .nico, role: "member")
        XCTAssertFalse(forged.isValid(for: "ha-mika", expectedDeviceID: "ios-member"))
    }

    func testOwnerRequiresSeparateEnrollment() {
        let pending = result(
            userID: "ha-nico", profile: .nico, role: "owner",
            approval: "separate_device_approval_required"
        )
        XCTAssertTrue(pending.isValid(for: "ha-nico", expectedDeviceID: "ios-member"))
        let forged = result(userID: "ha-nico", profile: .nico, role: "owner")
        XCTAssertFalse(forged.isValid(for: "ha-nico", expectedDeviceID: "ios-member"))
    }

    func testCannotInheritAnotherAccountOrDevice() {
        let result = result(userID: "ha-juli", profile: .juli, role: "member")
        XCTAssertFalse(result.isValid(for: "ha-mika", expectedDeviceID: "ios-member"))
        XCTAssertFalse(result.isValid(for: "ha-juli", expectedDeviceID: "ios-someone-else"))
    }

    func testDecodeUsesServerIdentifiersNotDisplayNames() throws {
        let data = Data("""
        {"ha_user_id":"ha-juli","profile":"juli","role":"member",
        "device_id":"ios-device","owner_authorization":"not_available"}
        """.utf8)
        let decoded = try JSONDecoder().decode(FamilyRegistration.self, from: data)
        XCTAssertEqual(decoded.profile, .juli)
        XCTAssertTrue(decoded.isValid(for: "ha-juli", expectedDeviceID: "ios-device"))
    }
}
