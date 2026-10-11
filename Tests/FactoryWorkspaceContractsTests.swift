import Foundation
import XCTest
@testable import IOSNext

final class FactoryWorkspaceContractsTests: XCTestCase {
    func testLegacyFactoryToolsAreAllPreserved() {
        XCTAssertEqual(FactoryWorkspaceToolCatalog.legacyRead.count, 11)
        for name in FactoryWorkspaceToolCatalog.legacyRead {
            XCTAssertTrue(FactoryWorkspaceToolCatalog.isPermittedRead(name))
        }
    }

    func testNewWorkspaceReadsAreExplicitlyAllowed() {
        XCTAssertTrue(FactoryWorkspaceToolCatalog.isPermittedRead("workspace_overview_get"))
        XCTAssertTrue(FactoryWorkspaceToolCatalog.isPermittedRead("owner_tickets_list"))
        XCTAssertTrue(FactoryWorkspaceToolCatalog.isPermittedRead("runner_job_logs_get"))
        XCTAssertTrue(FactoryWorkspaceToolCatalog.isPermittedRead("events_history_list"))
    }

    func testUnknownAndWriteToolsFailClosed() {
        XCTAssertFalse(FactoryWorkspaceToolCatalog.isPermittedRead("dangerous_host_write"))
        XCTAssertFalse(FactoryWorkspaceToolCatalog.isPermittedRead("operation_execute"))
        XCTAssertFalse(FactoryWorkspaceToolCatalog.mayExecute("operation_execute"))
        XCTAssertFalse(FactoryWorkspaceToolCatalog.mayExecute("runner_shutdown"))
        XCTAssertFalse(FactoryWorkspaceToolCatalog.mayExecute("live_home_assistant_input_boolean_set"))
    }

    func testRecognizedEnvelopeDecodesProvenanceAndCapabilities() throws {
        let raw = """
        {"schema_version":"factory.workspace.v1","source":"factory","status":"ok",
         "observed_at":"2026-10-11T18:00:00Z","revision":"r1",
         "freshness":{"stale":false},
         "capabilities":{"READ_ONLY":true,"RUNNER_WRITE":false}}
        """
        let value = try FactoryWorkspaceEnvelope.decode(raw)
        XCTAssertEqual(value.source, "factory")
        XCTAssertEqual(value.revision, "r1")
        XCTAssertEqual(value.capabilityNames["READ_ONLY"], true)
        XCTAssertEqual(value.capabilityNames["RUNNER_WRITE"], false)
        XCTAssertFalse(value.stale)
        XCTAssertNotNil(value.observedAt)
    }

    func testUnsupportedSchemaIsRejectedRatherThanAssumedCompatible() {
        let raw = #"{"schema_version":"factory.workspace.v2","source":"factory","status":"ok"}"#
        XCTAssertThrowsError(try FactoryWorkspaceEnvelope.decode(raw)) { error in
            XCTAssertEqual(error as? FactoryWorkspaceContractError, .unsupportedSchema)
        }
    }

    func testMissingProvenanceCannotBePresentedAsLive() {
        let raw = #"{"schema_version":"factory.workspace.v1","status":"ok"}"#
        XCTAssertThrowsError(try FactoryWorkspaceEnvelope.decode(raw)) { error in
            XCTAssertEqual(error as? FactoryWorkspaceContractError, .invalidEnvelope)
        }
    }

    func testMissingFreshnessFailsStale() throws {
        let raw = #"{"schema_version":"factory.workspace.v1","source":"factory","status":"ok"}"#
        XCTAssertTrue(try FactoryWorkspaceEnvelope.decode(raw).stale)
    }
}
