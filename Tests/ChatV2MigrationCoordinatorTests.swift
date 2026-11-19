import Foundation
import XCTest
@testable import IOSNext

final class ChatV2MigrationCoordinatorTests: XCTestCase {
    @MainActor
    func testPreparedCutoverIsExplicitResumableAndNeverFallsBackAfterActivation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let v1=root.appendingPathComponent("legacy.enc"), v2=root.appendingPathComponent("candidate.sqlite3")
        let scope=Data("fixture-migration-scope".utf8), key=Data(repeating:73,count:32)
        let archive=try ChatHistoryArchive(file:v1,scope:scope,keyData:key)
        let date=Date(timeIntervalSinceReferenceDate:1234)
        let initial=ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:["old":date])
        try archive.save(initial)
        let original=try Data(contentsOf:v1)
        var marker:Data?
        func coordinator() throws -> ChatV2MigrationCoordinator {
            try ChatV2MigrationCoordinator(file:v2,scope:scope,key:key,readMarker:{marker},
                insertMarker:{value in guard marker==nil else {return false}; marker=value; return true})
        }
        let first=try coordinator()
        let prepared=try await first.prepare(archive)
        XCTAssertNil(marker)
        let notActive=try await first.openActive()
        XCTAssertNil(notActive)
        let restored=try await coordinator().prepare(archive)
        XCTAssertEqual(prepared,restored)
        XCTAssertEqual(try Data(contentsOf:v1),original)
        let changed=ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:["new":date])
        try archive.save(changed)
        do {
            _ = try await first.activate(prepared:prepared,archive:archive)
            XCTFail("changed legacy archive was promoted")
        } catch let failure as ChatV2MigrationCoordinator.Failure { XCTAssertEqual(failure,.sourceChanged) }
        XCTAssertNil(marker)
        try original.write(to:v1,options:.atomic)
        let active=try await first.activate(prepared:prepared,archive:archive)
        XCTAssertNotNil(marker)
        let loaded=try await active.load()
        XCTAssertEqual(loaded,initial)
        _ = try await active.commit(previous:initial,next:changed,verifiedEnvelopeIDs:["new"])
        let opened=try await coordinator().openActive()
        let reopened=try XCTUnwrap(opened)
        let latest=try await reopened.load()
        XCTAssertEqual(latest,changed)
        XCTAssertEqual(try Data(contentsOf:v1),original)
        do {
            _ = try await coordinator().prepare(archive)
            XCTFail("active database could be overwritten from legacy")
        } catch let failure as ChatV2MigrationCoordinator.Failure { XCTAssertEqual(failure,.alreadyActivated) }
        try FileManager.default.removeItem(at:v2)
        do {
            _ = try await coordinator().openActive()
            XCTFail("missing active database silently fell back")
        } catch let failure as ChatV2MigrationCoordinator.Failure { XCTAssertEqual(failure,.missingCandidate) }
        XCTAssertEqual(try Data(contentsOf:v1),original)
    }
}
