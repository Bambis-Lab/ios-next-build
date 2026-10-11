import Foundation
import XCTest
@testable import IOSNext

final class FactoryWorkspaceCollectionTests: XCTestCase {
    func testTypedFactoryList() throws {
        let json = """
        {"schema_version":"factory.workspace.v1","source":"factory","status":"ok",
         "freshness":{"stale":false},"data":{"items":[
            {"id":"r1","name":"Repository","status":"active"},
            {"id":"r2","title":"Build","status":"success"}]},
         "next_cursor":"page-2"}
        """
        let parsed = try FactoryWorkspaceCollection.decode(json)
        XCTAssertEqual(parsed.records.map(\.id), ["r1", "r2"])
        XCTAssertEqual(parsed.records.map(\.title), ["Repository", "Build"])
        XCTAssertEqual(parsed.nextCursor, "page-2")
        XCTAssertFalse(parsed.stale)
    }

    func testNoListCannotPretendToBeSuccessfulData() {
        let json = #"{"schema_version":"factory.workspace.v1","source":"factory","status":"ok","data":{}}"#
        XCTAssertThrowsError(try FactoryWorkspaceCollection.decode(json))
    }

    func testInvalidItemIsRejected() {
        let json = #"{"schema_version":"factory.workspace.v1","source":"factory","status":"ok","data":{"items":[{"name":"Unknown"}]}}"#
        XCTAssertThrowsError(try FactoryWorkspaceCollection.decode(json))
    }

    func testNoFreshnessIsStaleByDefault() throws {
        let json = #"{"schema_version":"factory.workspace.v1","source":"factory","status":"ok","data":{"items":[]}}"#
        XCTAssertTrue(try FactoryWorkspaceCollection.decode(json).stale)
    }
}
