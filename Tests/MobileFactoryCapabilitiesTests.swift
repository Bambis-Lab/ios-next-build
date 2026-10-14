import Foundation
import XCTest
@testable import IOSNext

/// BKI-02B isolated, deterministic contract coverage.
final class MobileFactoryCapabilitiesTests: XCTestCase {
    private let submit = "factory_master_runner_v1_job_submit"

    private func status(hostControl: Bool = true) -> [String: Any] {
        ["status": "ok",
         "capabilities": ["READ_ONLY": true, "HOST_CONTROL": hostControl]]
    }

    private func row(_ manifest: MobileFactoryCapabilityManifest, _ id: String) throws -> MobileFactoryCapability {
        try XCTUnwrap(manifest.capabilities.first(where: { $0.id == id }))
    }

    func testMissingBackendFailsClosed() {
        let result = MobileFactoryCapabilityProjector.project(
            status: nil, registeredTools: ["factory_status", submit],
            backendOnline: false, operationAuthorization: [submit: true])
        XCTAssertFalse(result.snapshotComplete)
        XCTAssertTrue(result.capabilities.allSatisfy { !$0.authorized && !$0.available })
        XCTAssertFalse(result.allowsDisplay("runner.job_submit"))
    }

    func testUnknownToolNotAdvertised() throws {
        let result = MobileFactoryCapabilityProjector.project(
            status: status(), registeredTools: ["factory_status"], backendOnline: true)
        XCTAssertTrue(try row(result, "factory.status").authorized)
        XCTAssertEqual(try row(result, "runner.job_submit").reason, "tool_missing")
        XCTAssertFalse(result.allowsDisplay("runner.job_submit"))
    }

    func testHostControlPolicyDoesNotImplyPerOperationApproval() throws {
        let result = MobileFactoryCapabilityProjector.project(
            status: status(), registeredTools: [submit], backendOnline: true)
        let job = try row(result, "runner.job_submit")
        XCTAssertTrue(job.enabled)
        XCTAssertTrue(job.requiresApproval)
        XCTAssertFalse(job.authorized)
        XCTAssertEqual(job.reason, "approval_required")
    }

    func testScopedProofNeverAppliesToOtherTools() throws {
        let result = MobileFactoryCapabilityProjector.project(
            status: status(), registeredTools: [submit, "factory_master_runner_v1_job_cancel"],
            backendOnline: true, operationAuthorization: [submit: true])
        XCTAssertTrue(try row(result, "runner.job_submit").authorized)
        XCTAssertFalse(try row(result, "runner.job_cancel").authorized)
    }

    func testCapabilityDisabledOverridesProof() throws {
        let result = MobileFactoryCapabilityProjector.project(
            status: status(hostControl: false), registeredTools: [submit],
            backendOnline: true, operationAuthorization: [submit: true])
        XCTAssertFalse(try row(result, "runner.job_submit").authorized)
        XCTAssertEqual(try row(result, "runner.job_submit").reason, "capability_disabled")
    }

    func testUnhealthyStatusCannotAdvertiseAvailability() {
        let result = MobileFactoryCapabilityProjector.project(
            status: ["status": "degraded", "capabilities": ["READ_ONLY": true]],
            registeredTools: ["factory_status"], backendOnline: true)
        XCTAssertFalse(result.snapshotComplete)
        XCTAssertFalse(result.allowsDisplay("factory.status"))
    }

    func testEncodedJSONConformsToVersionedKeyShape() throws {
        let manifest = MobileFactoryCapabilityProjector.project(
            status: status(), registeredTools: ["factory_status"], backendOnline: true)
        let data = try JSONEncoder().encode(manifest)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schema_version"] as? String, "1.0")
        XCTAssertEqual(json["snapshot_complete"] as? Bool, true)
        let capabilities = try XCTUnwrap(json["capabilities"] as? [[String: Any]])
        XCTAssertNotNil(capabilities.first?["requires_approval"])
        XCTAssertEqual(try JSONDecoder().decode(MobileFactoryCapabilityManifest.self, from: data), manifest)
    }
}
