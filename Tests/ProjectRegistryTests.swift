import XCTest
@testable import IOSNext

final class ProjectRegistryTests: XCTestCase {
    func testIOSAppLegacyRepositoryIsCanonicalized() {
        XCTAssertEqual(
            ProjectRegistry.canonicalRepository(
                projectID: "ios-next",
                title: "iOS App",
                reportedRepository: "nicofroeba16-cell/ha-ios-next-ios"
            ),
            "Bambis-Lab/ios-next"
        )
        XCTAssertTrue(
            ProjectRegistry.repositoryMismatch(
                projectID: "ios-next",
                title: "iOS App",
                reportedRepository: "nicofroeba16-cell/ha-ios-next-ios"
            )
        )
    }

    func testKnownProjectRepositoriesStayCanonical() {
        let cases: [(String, String, String)] = [
            ("fire-tv-companion", "Fire TV Companion", "Bambis-Lab/firetv-companion"),
            ("home-assistant-dashboard", "Home Assistant Dashboard", "Bambis-Lab/ha-config"),
            ("intelligence-suite", "Intelligence Suite", "Bambis-Lab/ha-intelligence"),
            ("file-bridge", "File Bridge", "Bambis-Lab/mcp-file-bridge")
        ]

        for (projectID, title, repository) in cases {
            XCTAssertEqual(
                ProjectRegistry.canonicalRepository(
                    projectID: projectID,
                    title: title,
                    reportedRepository: repository
                ),
                repository
            )
            XCTAssertFalse(
                ProjectRegistry.repositoryMismatch(
                    projectID: projectID,
                    title: title,
                    reportedRepository: repository
                )
            )
        }
    }

    func testGlobalProjectHealthStaysUnconfigured() {
        XCTAssertNil(
            ProjectRegistry.canonicalRepository(
                projectID: "global-project-health",
                title: "Global Project Health",
                reportedRepository: nil
            )
        )
        XCTAssertNil(
            ProjectRegistry.canonicalRepository(
                projectID: "global-health",
                title: "Global Project Health",
                reportedRepository: "nicofroeba16-cell/ha-grok-bridge"
            )
        )
        XCTAssertNil(
            ProjectRegistry.canonicalDefaultBranch(
                projectID: "global-health",
                title: "Global Project Health",
                reportedRepository: nil
            )
        )
    }

    func testUnknownRepositoryPassesThroughWithoutMutation() {
        XCTAssertEqual(
            ProjectRegistry.canonicalRepository(
                projectID: "future-project",
                title: "Future Project",
                reportedRepository: "nicofroeba16-cell/Future-Repo"
            ),
            "nicofroeba16-cell/Future-Repo"
        )
    }

    func testEmptyRepositoryStaysUnconfigured() {
        XCTAssertNil(
            ProjectRegistry.canonicalRepository(
                projectID: "general",
                title: "General / Triage",
                reportedRepository: "   "
            )
        )
    }
}
