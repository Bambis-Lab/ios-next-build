import Foundation
import XCTest
@testable import IOSNext

@MainActor
final class FactoryWorkspaceCoordinatorTests: XCTestCase {
    func testUnconfiguredFactoryNeverFetchesOrClaimsData() async {
        let credentials = FactoryCredentialStore(
            read: { nil },
            write: { _ in XCTFail("No credentials must be saved") },
            delete: { }
        )
        let service = FactoryMCPService(credentials: credentials)
        let connection = FactoryConnectionModel(service: service)
        let coordinator = FactoryWorkspaceCoordinator(connection: connection)
        await coordinator.refresh()
        XCTAssertEqual(connection.phase, .disconnected)
        XCTAssertFalse(coordinator.canReadWorkspace)
        XCTAssertFalse(coordinator.isOverviewCurrent)
        XCTAssertNil(coordinator.overview)
        XCTAssertNil(coordinator.overviewError)
        XCTAssertTrue(coordinator.sourceStates.isEmpty)
        XCTAssertTrue(coordinator.recentFactoryEvents.isEmpty)
    }

    func testNoGenericFactoryWriteActionEverExecutes() {
        let coordinator = FactoryWorkspaceCoordinator(
            connection: FactoryConnectionModel(service: FactoryMCPService(
                credentials: FactoryCredentialStore(read: { nil }, write: { _ in }, delete: {})
            ))
        )
        XCTAssertThrowsError(try coordinator.executeAction("operation_execute"))
        XCTAssertThrowsError(try coordinator.executeAction("live_home_assistant_input_boolean_set"))
        XCTAssertThrowsError(try coordinator.executeAction("arbitrary_shell"))
    }
}
