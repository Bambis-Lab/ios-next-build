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

    func testTicketReadFenceRejectsSupersededAndInvalidatedRequests() throws {
        let url=try XCTUnwrap(URL(string:"https://example.invalid"))
        let a=TicketScreenScope(endpoint:url,user:"a",device:"ios-a",owner:false,keyFingerprint:"fixture-a")
        let b=TicketScreenScope(endpoint:url,user:"b",device:"ios-b",owner:true,keyFingerprint:"fixture-b")
        var fence=TicketReadRequestFence()
        let first=fence.begin(a)
        XCTAssertTrue(fence.accepts(first,scope:a))
        XCTAssertFalse(fence.accepts(first,scope:b))
        let second=fence.begin(a)
        XCTAssertFalse(fence.accepts(first,scope:a))
        XCTAssertTrue(fence.accepts(second,scope:a))
        fence.invalidate()
        XCTAssertFalse(fence.accepts(second,scope:a))
        let third=fence.begin(b)
        XCTAssertFalse(fence.accepts(first,scope:a))
        XCTAssertFalse(fence.accepts(third,scope:a))
        XCTAssertTrue(fence.accepts(third,scope:b))
    }

    func testSupersededAuthorizationDenialStillInvalidatesOnlyMatchingLease() throws {
        let url=try XCTUnwrap(URL(string:"https://example.invalid"))
        let a=TicketScreenScope(endpoint:url,user:"a",device:"ios-a",owner:true,keyFingerprint:"fixture-a")
        let b=TicketScreenScope(endpoint:url,user:"b",device:"ios-b",owner:false,keyFingerprint:"fixture-b")
        var fence=TicketReadRequestFence()
        let first=fence.begin(a)
        let second=fence.begin(a)
        XCTAssertFalse(fence.accepts(first,scope:a))
        XCTAssertTrue(fence.accepts(second,scope:a))
        for error:Error in [ChatError.rejected(401),ChatError.rejected(403),ChatError.authenticationFailed,FamilyBootstrapError.unauthorized] {
            XCTAssertTrue(TicketOfflineFallbackPolicy.invalidatesLease(error,requestGeneration:1,currentGeneration:1,requestScope:a,activeScope:fence.scope))
            XCTAssertFalse(TicketOfflineFallbackPolicy.invalidatesLease(error,requestGeneration:0,currentGeneration:1,requestScope:a,activeScope:fence.scope))
            XCTAssertFalse(TicketOfflineFallbackPolicy.invalidatesLease(error,requestGeneration:1,currentGeneration:1,requestScope:a,activeScope:b))
        }
        XCTAssertFalse(TicketOfflineFallbackPolicy.invalidatesLease(URLError(.timedOut),requestGeneration:1,currentGeneration:1,requestScope:a,activeScope:a))
        XCTAssertFalse(TicketOfflineFallbackPolicy.invalidatesLease(CancellationError(),requestGeneration:1,currentGeneration:1,requestScope:a,activeScope:a))
        fence.invalidate()
        XCTAssertFalse(fence.accepts(second,scope:a))
    }

    func testWritePermitRejectsLateResponseAfterRevocationExpiryOrAccountChange() throws {
        let url=try XCTUnwrap(URL(string:"https://example.invalid"))
        let a=TicketScreenScope(endpoint:url,user:"a",device:"ios-a",owner:true,keyFingerprint:"fixture-a")
        let b=TicketScreenScope(endpoint:url,user:"b",device:"ios-b",owner:false,keyFingerprint:"fixture-b")
        let now=Date()
        let lease=try TicketOfflineLease(scope:a,verifiedGrantExpiry:now.addingTimeInterval(300),generation:7,now:now)
        var fence=TicketReadRequestFence()
        let revision=fence.begin(a)
        XCTAssertNoThrow(try fence.requireWrite(revision,scope:a,generation:7,currentGeneration:7,lease:lease,now:now))
        XCTAssertThrowsError(try fence.requireWrite(revision,scope:a,generation:7,currentGeneration:8,lease:lease,now:now))
        XCTAssertThrowsError(try fence.requireWrite(revision,scope:a,generation:7,currentGeneration:7,lease:nil,now:now))
        XCTAssertThrowsError(try fence.requireWrite(revision,scope:a,generation:7,currentGeneration:7,lease:lease,now:now.addingTimeInterval(61)))
        XCTAssertThrowsError(try fence.requireWrite(revision,scope:b,generation:7,currentGeneration:7,lease:lease,now:now))
        fence.invalidate()
        XCTAssertThrowsError(try fence.requireWrite(revision,scope:a,generation:7,currentGeneration:7,lease:lease,now:now))
    }

    /// Local native cryptographic and persistence matrix. The five roles
    /// here are disposable fixtures, not live HA enrollments or UI sessions.
    @MainActor
    func testFiveRoleTicketMatrixExactReplyRecoveryAndCacheIsolation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let profiles=["nico","gabi","timo","mika","juli"]
        let endpoint=try XCTUnwrap(URL(string:"https://fixture.invalid"))
        let now=Date()
        let keys=profiles.map{_ in ChatDeviceKeys(agreement:.init(),signing:.init())}
        let identities=zip(profiles,keys).map{profile,key in
            key.publicIdentity(userID:"fixture-"+profile,deviceID:"ios-fixture-"+profile)
        }
        let scopes=profiles.indices.map{i in
            TicketScreenScope(endpoint:endpoint,user:identities[i].userID,device:identities[i].deviceID,
                owner:i==0,keyFingerprint:keys[i].safetyNumber)
        }
        let leases=try scopes.map{try TicketOfflineLease(scope:$0,verifiedGrantExpiry:now.addingTimeInterval(300),generation:7,now:now)}
        let authorizations=profiles.indices.map{i -> EncryptedTicketAuthorization in
            if i==0 {
                return .owner(.init(baseURL:endpoint,ownerToken:"synthetic-owner",ownerDeviceSession:"synthetic-device-proof"),
                    userID:identities[i].userID,deviceID:identities[i].deviceID)
            }
            return .member(.init(baseURL:endpoint,token:"synthetic-member-\(i)",
                userID:identities[i].userID,deviceID:identities[i].deviceID))
        }
        func archive(_ index:Int,_ kind:String) throws -> ChatHistoryArchive {
            try ChatHistoryArchive(file:root.appendingPathComponent("\(index)-\(kind).enc"),
                scope:Data("\(index)-\(kind)-fixture".utf8),keyData:Data(repeating:UInt8(index+1),count:32))
        }
        func cache(_ i:Int) throws -> SecureTicketCache {
            try SecureTicketCache(scope:scopes[i],local:identities[i],archive:archive(i,"cache"))
        }
        func outbox(_ i:Int) throws -> SecureTicketOutbox {
            SecureTicketOutbox(scope:scopes[i],archive:try archive(i,"outbox"))
        }
        var details:[EncryptedTicketDetail]=[]
        var pending:[TicketPendingSend]=[]
        for i in 1..<5 {
            let id=UUID().uuidString.lowercased()
            let message=try EncryptedTicketMessage.seal(text:"Synthetic request \(i)",ticketID:id,
                author:identities[i],counterparty:identities[0],confirmedSafetyNumber:keys[0].safetyNumber,keys:keys[i])
            let request=TicketPendingSend(scope:scopes[i],message:message,peer:identities[0],create:true)
            try outbox(i).stage(request)
            pending.append(request)
            details.append(.init(ticketID:id,requester:identities[i],owner:identities[0],status:.open,messages:[message]))
        }
        // All four member queues coexist. Reopen each from storage before
        // acknowledging its own request. No foreign receipt can clear it.
        for i in 1..<5 {
            let detail=details[i-1],request=pending[i-1]
            XCTAssertEqual(try outbox(i).pending(),request)
            XCTAssertThrowsError(try outbox(i).acknowledge(request,receipt:details[i%4]))
            XCTAssertEqual(try outbox(i).pending(),request)
            for role in 0..<5 {
                XCTAssertEqual(authorizations[role].allows(requester:detail.requester,owner:detail.owner),role==0 || role==i)
                if role != 0 && role != i {
                    XCTAssertThrowsError(try cache(role).putDetail(detail,lease:leases[role]))
                    XCTAssertThrowsError(try detail.messages[0].open(expectedTicketID:detail.ticketID,
                        author:identities[i],counterparty:identities[0],confirmedSafetyNumber:keys[i].safetyNumber,
                        local:identities[role],keys:keys[role]))
                }
            }
            try outbox(i).acknowledge(request,receipt:detail)
            XCTAssertNil(try outbox(i).pending())
            try cache(i).putDetail(detail,lease:leases[i])
            try cache(0).putDetail(detail,lease:leases[0])
            let reply=try EncryptedTicketMessage.seal(text:"Synthetic reply \(i)",ticketID:detail.ticketID,
                author:identities[0],counterparty:identities[i],confirmedSafetyNumber:keys[i].safetyNumber,keys:keys[0])
            let outgoing=TicketPendingSend(scope:scopes[0],message:reply,peer:identities[i],create:false)
            try outbox(0).stage(outgoing)
            // A lost HTTP reply must leave the exact original request intact.
            try outbox(0).stage(outgoing)
            XCTAssertEqual(try outbox(0).pending(),outgoing)
            let complete=EncryptedTicketDetail(ticketID:detail.ticketID,requester:detail.requester,owner:detail.owner,
                status:.open,messages:detail.messages+[reply])
            try outbox(0).acknowledge(outgoing,receipt:complete)
            XCTAssertNil(try outbox(0).pending())
            XCTAssertEqual(try reply.open(expectedTicketID:detail.ticketID,author:identities[0],counterparty:identities[i],
                confirmedSafetyNumber:keys[0].safetyNumber,local:identities[i],keys:keys[i]),"Synthetic reply \(i)")
            try cache(i).putDetail(complete,lease:leases[i])
            try cache(0).putDetail(complete,lease:leases[0])
            XCTAssertEqual(try cache(i).detail(detail.ticketID,lease:leases[i])?.messages,complete.messages)
            XCTAssertEqual(try cache(i).list(lease:leases[i]).map(\.ticketID),[detail.ticketID])
            for role in 0..<5 where role != i {
                XCTAssertThrowsError(try cache(i).list(lease:leases[role]))
            }
            XCTAssertThrowsError(try leases[i].require(scopes[i],generation:8,now:now))
            XCTAssertThrowsError(try leases[i].require(scopes[i],now:now.addingTimeInterval(121)))
        }
        XCTAssertEqual(Set(try cache(0).list(lease:leases[0]).map(\.ticketID)),Set(details.map(\.ticketID)))
        XCTAssertThrowsError(try leases[0].require(scopes[0],now:now.addingTimeInterval(61)))
        // Invalidating one member's view cannot clear another role's data.
        try cache(1).invalidate()
        XCTAssertTrue(try cache(1).list(lease:leases[1]).isEmpty)
        XCTAssertEqual(try cache(0).list(lease:leases[0]).count,4)
        for i in 2..<5 {XCTAssertEqual(try cache(i).list(lease:leases[i]).count,1)}
        print("V65_TICKET_LOCAL_ROLE_MATRIX=PASS roles=5 requests=4 replies=4 live_backend=false")
    }
}
