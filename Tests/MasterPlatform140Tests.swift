import XCTest
@testable import IOSNext

final class MasterPlatform140Tests: XCTestCase {
    func testCompatibilitySnapshotCanonicalizesRepositoryAndCI() {
        let now = Date()
        let ci = AdminCIStatusV2(
            status: "completed",
            conclusion: "success",
            headSHA: "1234567890abcdef",
            workflow: "validate-ios-next-source",
            updatedAt: now,
            error: nil
        )
        let project = AdminProjectStatusV2(
            id: "ios-next",
            title: "iOS App",
            repository: "nicofroeba16-cell/ha-ios-next-ios",
            dispatchCount: 0,
            activeJobs: 0,
            latestDispatchState: nil,
            ci: ci
        )

        let snapshot = MasterDataPlaneSnapshot.compatibility(projects: [project], runnerStatus: nil, observedAt: now)

        XCTAssertEqual(snapshot.repositories.count, 1)
        XCTAssertEqual(snapshot.repositories[0].fullName, "Bambis-Lab/ios-next")
        XCTAssertEqual(snapshot.repositories[0].category, .product)
        XCTAssertEqual(snapshot.ciRuns.first?.state, .success)
        XCTAssertEqual(snapshot.governance.capabilities, [MasterCapability.readOnly.rawValue])
        XCTAssertTrue(snapshot.governance.actionsServerControlled)
    }

    func testFreshnessUsesBackendTTL() {
        let observed = Date(timeIntervalSince1970: 1_000)
        let freshness = MasterFreshness(observedAt: observed, ttlSeconds: 30)
        XCTAssertEqual(freshness.state(now: Date(timeIntervalSince1970: 1_010)), .verified)
        XCTAssertEqual(freshness.state(now: Date(timeIntervalSince1970: 1_031)), .stale)
    }

    func testDiagnosticRedactorFailsClosedOnSecrets() {
        XCTAssertEqual(MasterDiagnosticRedactor.sanitized("Authorization: Bearer abc"), "[redacted]")
        XCTAssertEqual(MasterDiagnosticRedactor.sanitized("owner token configured"), "[redacted]")
        XCTAssertEqual(MasterDiagnosticRedactor.sanitized("Runner healthy"), "Runner healthy")
    }

    func testStorageSeverityThresholds() {
        XCTAssertEqual(MasterStorageMount(id: "a", title: "A", mountPath: "/", usedPercent: 79, totalBytes: nil, freeBytes: nil).severity, .normal)
        XCTAssertEqual(MasterStorageMount(id: "b", title: "B", mountPath: "/", usedPercent: 85, totalBytes: nil, freeBytes: nil).severity, .notice)
        XCTAssertEqual(MasterStorageMount(id: "c", title: "C", mountPath: "/", usedPercent: 94, totalBytes: nil, freeBytes: nil).severity, .warning)
        XCTAssertEqual(MasterStorageMount(id: "d", title: "D", mountPath: "/", usedPercent: 96, totalBytes: nil, freeBytes: nil).severity, .critical)
    }

    func testGovernedActionRejectsExpiredPlan() {
        let plan = makePlan(capability: .sourceWrite, expiresAt: Date(timeIntervalSince1970: 100))
        let precheck = MasterActionPrecheck(
            planID: plan.id,
            state: .pass,
            checkedAt: Date(timeIntervalSince1970: 90),
            items: []
        )
        let decision = MasterActionPolicy.canApprove(
            plan: plan,
            precheck: precheck,
            capabilityActive: true,
            authorityFresh: true,
            connected: true,
            now: Date(timeIntervalSince1970: 101)
        )
        guard case .deny = decision else { return XCTFail("Expired plan must fail closed") }
    }

    func testGovernedActionRejectsLockedCapability() {
        let plan = makePlan(capability: .hostControl, expiresAt: Date(timeIntervalSince1970: 200))
        let precheck = MasterActionPrecheck(
            planID: plan.id,
            state: .pass,
            checkedAt: Date(timeIntervalSince1970: 90),
            items: []
        )
        let decision = MasterActionPolicy.canApprove(
            plan: plan,
            precheck: precheck,
            capabilityActive: true,
            authorityFresh: true,
            connected: true,
            now: Date(timeIntervalSince1970: 100)
        )
        guard case .deny = decision else { return XCTFail("HOST_CONTROL must remain locked") }
    }

    func testGovernedActionAllowsImplementedCapabilityOnlyWhenAllGatesPass() {
        let plan = makePlan(capability: .runnerWrite, expiresAt: Date(timeIntervalSince1970: 200))
        let precheck = MasterActionPrecheck(
            planID: plan.id,
            state: .pass,
            checkedAt: Date(timeIntervalSince1970: 90),
            items: []
        )
        XCTAssertEqual(
            MasterActionPolicy.canApprove(
                plan: plan,
                precheck: precheck,
                capabilityActive: true,
                authorityFresh: true,
                connected: true,
                now: Date(timeIntervalSince1970: 100)
            ),
            .allow
        )
    }

    private func makePlan(capability: MasterCapability, expiresAt: Date) -> MasterActionPlan {
        MasterActionPlan(
            id: "plan-1",
            actionID: "test.action",
            targetID: "target-1",
            capability: capability,
            risk: .medium,
            createdAt: Date(timeIntervalSince1970: 50),
            expiresAt: expiresAt,
            nonce: "nonce",
            planHash: "hash",
            authority: "Bambis Master",
            steps: [],
            rollback: MasterRollbackDescriptor(supported: true, title: "Rollback", reference: "previous")
        )
    }
}
