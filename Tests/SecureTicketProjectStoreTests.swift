import Foundation
import XCTest
@testable import IOSNext

final class SecureTicketProjectStoreTests: XCTestCase {
    @MainActor
    func testLocalProjectAssignmentPersistsAndRejectsUnknownProjectAndMember() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let file = directory.appendingPathComponent("projects.enc")
        let scope = TicketScreenScope(endpoint: try XCTUnwrap(URL(string:"https://example.invalid")),
            user:"fixture-owner",device:"ios-owner",owner:true,keyFingerprint:"fixture-key")
        let id = UUID().uuidString.lowercased()
        let key = Data(repeating:23,count:32)
        let scopeData = Data("fixture-projects".utf8)
        func open() throws -> SecureTicketProjectStore {
            try SecureTicketProjectStore(scope:scope,
                archive:ChatHistoryArchive(file:file,scope:scopeData,keyData:key))
        }
        try open().assign(ticketID:id, projectID:"ios-next")
        XCTAssertEqual(try open().read(),[id:"ios-next"])
        XCTAssertNil(try Data(contentsOf:file).range(of:Data("ios-next".utf8)))
        XCTAssertThrowsError(try open().assign(ticketID:id, projectID:"unregistered-project"))
        XCTAssertEqual(try open().read(),[id:"ios-next"])
        let member = TicketScreenScope(endpoint:scope.endpoint,user:"fixture-member",
            device:"ios-member",owner:false,keyFingerprint:"member-key")
        XCTAssertThrowsError(try SecureTicketProjectStore(scope:member,
            archive:ChatHistoryArchive(file:file,scope:scopeData,keyData:key)))
        let wrongScope = try SecureTicketProjectStore(scope:scope,
            archive:ChatHistoryArchive(file:file,scope:Data("foreign-scope".utf8),keyData:key))
        XCTAssertThrowsError(try wrongScope.read())
        try open().assign(ticketID:id,projectID:nil)
        XCTAssertEqual(try open().read(),[:])
    }
}
