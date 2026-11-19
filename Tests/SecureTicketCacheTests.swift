import Foundation
import XCTest
@testable import IOSNext

final class SecureTicketCacheTests: XCTestCase {
    func testOfflineFallbackExcludesTLSAuthorizationAndCancellation() throws {
        XCTAssertTrue(TicketOfflineFallbackPolicy.allows(URLError(.notConnectedToInternet)))
        XCTAssertTrue(TicketOfflineFallbackPolicy.allows(URLError(.networkConnectionLost)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(URLError(.serverCertificateUntrusted)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(URLError(.secureConnectionFailed)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(URLError(.cancelled)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(ChatError.rejected(401)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(ChatError.rejected(403)))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(ChatError.invalidResponse))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(FamilyBootstrapError.unauthorized))
        XCTAssertFalse(TicketOfflineFallbackPolicy.allows(CancellationError()))
    }

    @MainActor
    func testCiphertextCacheScopeExpiryPruningAndInvalidation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let file=root.appendingPathComponent("ticket-cache.enc")
        let localKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let peerKeys=ChatDeviceKeys(agreement:.init(),signing:.init())
        let local=localKeys.publicIdentity(userID:"fixture-member",deviceID:"ios-member")
        let peer=peerKeys.publicIdentity(userID:"fixture-owner",deviceID:"ios-owner")
        let scope=TicketScreenScope(endpoint:try XCTUnwrap(URL(string:"https://example.invalid")),
            user:local.userID,device:local.deviceID,owner:false,keyFingerprint:localKeys.safetyNumber)
        let lease=try TicketOfflineLease(scope:scope,verifiedGrantExpiry:Date().addingTimeInterval(300))
        let key=Data(repeating:57,count:32)
        let aad=Data("fixture-ticket-cache".utf8)
        func open() throws -> SecureTicketCache {
            try SecureTicketCache(scope:scope,local:local,
                archive:ChatHistoryArchive(file:file,scope:aad,keyData:key))
        }
        let id=UUID().uuidString.lowercased()
        let message=try EncryptedTicketMessage.seal(text:"synthetic confidential message",ticketID:id,
            author:local,counterparty:peer,confirmedSafetyNumber:peerKeys.safetyNumber,keys:localKeys)
        let detail=EncryptedTicketDetail(ticketID:id,requester:local,owner:peer,status:.open,messages:[message])
        try open().putDetail(detail,lease:lease)
        XCTAssertEqual(try open().list(lease:lease).map(\.ticketID),[id])
        XCTAssertEqual(try open().detail(id,lease:lease)?.messages,[message])
        XCTAssertNil(try Data(contentsOf:file).range(of:Data("synthetic confidential message".utf8)))
        XCTAssertThrowsError(try lease.require(scope,now:Date().addingTimeInterval(121)))
        XCTAssertThrowsError(try lease.require(scope,generation:1))
        XCTAssertNoThrow(try lease.require(scope,generation:0))
        let foreign=TicketScreenScope(endpoint:scope.endpoint,user:"foreign",device:scope.device,
            owner:false,keyFingerprint:scope.keyFingerprint)
        let wrongLease=try TicketOfflineLease(scope:foreign,verifiedGrantExpiry:Date().addingTimeInterval(300))
        XCTAssertThrowsError(try open().list(lease:wrongLease))
        XCTAssertThrowsError(try open().putDetail(EncryptedTicketDetail(ticketID:id,requester:peer,owner:local,
            status:.open,messages:[message]),lease:lease))
        try open().replaceList([EncryptedTicketSummary(ticketID:id,requester:local,owner:peer,status:.resolved)],lease:lease)
        XCTAssertNil(try open().detail(id,lease:lease))
        XCTAssertEqual(try open().list(lease:lease).first?.status,.resolved)
        try open().invalidate()
        XCTAssertTrue(try open().list(lease:lease).isEmpty)
    }
}
