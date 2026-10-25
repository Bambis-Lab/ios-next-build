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
    func testFamilyGrantDeniesOwnerScopeAndExpiredToken() {
        let future = Int(Date().timeIntervalSince1970) + 900
        let valid = FamilyChatGrant(accessToken: String(repeating: "a", count: 64), expiresAt: future, scopes: ["chat", "tickets"])
        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(FamilyChatGrant(accessToken: valid.accessToken, expiresAt: future, scopes: ["chat", "owner"]).isValid)
        XCTAssertFalse(FamilyChatGrant(accessToken: valid.accessToken, expiresAt: 1, scopes: ["chat", "tickets"]).isValid)
    }

    func testFamilyRegistrationDecodesChatCredentialWithoutAcceptingAnOwnerPermission() throws {
        let timestamp = Int(Date().timeIntervalSince1970) + 900
        let data = Data("""
        {"ha_user_id":"ha-mika","profile":"mika","role":"member",
         "device_id":"ios-device","owner_authorization":"not_available",
         "chat":{"access_token":"\(String(repeating: "a", count: 64))",
         "expires_at":\(timestamp),"scopes":["chat","tickets"]}}
        """.utf8)
        let decoded = try JSONDecoder().decode(FamilyRegistration.self, from: data)
        XCTAssertEqual(decoded.profile, .mika)
        XCTAssertTrue(decoded.chat?.isValid == true)
        XCTAssertTrue(decoded.isValid(for: "ha-mika", expectedDeviceID: "ios-device"))
    }

    func testOwnerSessionCannotBeReusedByAnotherAccountOrDevice() {
        let expiry = Int(Date().timeIntervalSince1970) + 900
        let session = FamilyOwnerSession(
            accessToken: String(repeating: "o", count: 64),
            deviceSession: String(repeating: "s", count: 64),
            expiresAt: expiry, deviceID: "ios-nico", haUserID: "ha-nico", role: "owner"
        )
        XCTAssertTrue(session.isValid(haUserID: "ha-nico", deviceID: "ios-nico"))
        XCTAssertFalse(session.isValid(haUserID: "ha-mika", deviceID: "ios-nico"))
        XCTAssertFalse(session.isValid(haUserID: "ha-nico", deviceID: "ios-mika"))
        let expired = FamilyOwnerSession(
            accessToken: session.accessToken, deviceSession: session.deviceSession,
            expiresAt: 1, deviceID: "ios-nico", haUserID: "ha-nico", role: "owner"
        )
        XCTAssertFalse(expired.isValid(haUserID: "ha-nico", deviceID: "ios-nico"))
    }

    func testFamilyChatKeyNamespaceIsDistinctForMikaAndJuli() throws {
        let mika = try ChatDeviceKeys.loadOrCreate(forUserID: "ha-mika")
        let juli = try ChatDeviceKeys.loadOrCreate(forUserID: "ha-juli")
        XCTAssertNotEqual(mika.safetyNumber, juli.safetyNumber)
        XCTAssertEqual(try ChatDeviceKeys.loadOrCreate(forUserID: "ha-mika").safetyNumber,
                       mika.safetyNumber)
    }

    func testE2EEMigrationNeverCrossesHAAccountsOrOverwritesFamilyIdentity() {
        XCTAssertTrue(ChatDeviceKeys.mayMigrateLegacyKeys(
            previouslyBoundHAUserID: "ha-mika", verifiedHAUserID: "ha-mika",
            hasOldChatConfiguration: true, alreadyUsingFamilyCredential: false
        ))
        XCTAssertFalse(ChatDeviceKeys.mayMigrateLegacyKeys(
            previouslyBoundHAUserID: "ha-mika", verifiedHAUserID: "ha-juli",
            hasOldChatConfiguration: true, alreadyUsingFamilyCredential: false
        ))
        XCTAssertFalse(ChatDeviceKeys.mayMigrateLegacyKeys(
            previouslyBoundHAUserID: nil, verifiedHAUserID: "ha-mika",
            hasOldChatConfiguration: true, alreadyUsingFamilyCredential: false
        ))
        XCTAssertFalse(ChatDeviceKeys.mayMigrateLegacyKeys(
            previouslyBoundHAUserID: "ha-mika", verifiedHAUserID: "ha-mika",
            hasOldChatConfiguration: true, alreadyUsingFamilyCredential: true
        ))
    }


    func testLegacyPersonalNavigationRestoresOwnerModulesAfterHALogin() {
        XCTAssertTrue(OwnerServiceNavigationPolicy.showServices(
            familyBrokerConfigured: false, registeredProfile: nil,
            selectedProfile: .nico, hasHAIdentity: true
        ))
        XCTAssertFalse(OwnerServiceNavigationPolicy.showServices(
            familyBrokerConfigured: false, registeredProfile: nil,
            selectedProfile: .nico, hasHAIdentity: false
        ))
        XCTAssertFalse(OwnerServiceNavigationPolicy.showServices(
            familyBrokerConfigured: false, registeredProfile: nil,
            selectedProfile: .gabi, hasHAIdentity: true
        ))
    }

    func testFamilyMemberNeverReceivesOwnerNavigationFromSelectedProfile() {
        for member in [HomeProfile.mika, .juli, .gabi, .timo] {
            XCTAssertFalse(OwnerServiceNavigationPolicy.showServices(
                familyBrokerConfigured: true, registeredProfile: member,
                selectedProfile: .nico, hasHAIdentity: true
            ))
            XCTAssertFalse(OwnerServiceNavigationPolicy.showRecovery(
                familyBrokerConfigured: true, registeredProfile: member
            ))
        }
    }

    func testVerifiedNicoNavigationIsIndependentOfRunnerOrFactoryConnectivity() {
        XCTAssertTrue(OwnerServiceNavigationPolicy.showServices(
            familyBrokerConfigured: true, registeredProfile: .nico,
            selectedProfile: .gabi, hasHAIdentity: true
        ))
    }

    func testUnverifiedFamilyIdentityOnlyOffersOwnerRecovery() {
        XCTAssertFalse(OwnerServiceNavigationPolicy.showServices(
            familyBrokerConfigured: true, registeredProfile: nil,
            selectedProfile: .nico, hasHAIdentity: true
        ))
        XCTAssertTrue(OwnerServiceNavigationPolicy.showRecovery(
            familyBrokerConfigured: true, registeredProfile: nil
        ))
        XCTAssertFalse(OwnerServiceNavigationPolicy.showRecovery(
            familyBrokerConfigured: false, registeredProfile: nil
        ))
    }

    func testFamilyDeviceProofPersistsForSameAppInstallation() throws {
        let first = try FamilyDeviceBinding.identity()
        let again = try FamilyDeviceBinding.identity()
        XCTAssertEqual(first.deviceID, again.deviceID)
        XCTAssertEqual(first.publicKey, again.publicKey)
    }

}
