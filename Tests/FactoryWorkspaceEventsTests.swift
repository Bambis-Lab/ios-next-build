import Foundation
import XCTest
@testable import IOSNext

final class FactoryWorkspaceEventsTests: XCTestCase {
    private func batch(_ numbers: [Int64], end: Int64? = nil) -> FactoryWorkspaceEventBatch {
        FactoryWorkspaceEventBatch(
            events: numbers.map {
                FactoryWorkspaceEvent(id: "e\($0)", sequence: $0,
                                      kind: "ci.job.updated", source: "factory", occurredAt: nil)
            },
            lastSequence: end
        )
    }

    func testRepeatedHistoryDoesNotDuplicateEvents() {
        var store = FactoryWorkspaceEventReconciler()
        store.append(batch([10, 11, 12]))
        store.append(batch([10, 11, 12, 13]))
        XCTAssertEqual(store.events.map(\.sequence), [10, 11, 12, 13])
        XCTAssertEqual(store.lastSequence, 13)
        XCTAssertFalse(store.needsResync)
    }

    func testGapForcesResyncRatherThanClaimingLive() {
        var store = FactoryWorkspaceEventReconciler()
        store.append(batch([20, 21]))
        store.append(batch([23]))
        XCTAssertTrue(store.needsResync)
        XCTAssertEqual(store.lastSequence, 21)
        store.reset()
        XCTAssertFalse(store.needsResync)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testFutureTerminalCursorCannotHideMissingEvents() {
        var store = FactoryWorkspaceEventReconciler()
        store.append(batch([5, 6], end: 8))
        XCTAssertTrue(store.needsResync)
    }

    func testMalformedAndUntrustedEventsRejected() {
        let invalid = #"{"schema_version":"factory.events.v1","events":[{"event_id":"e1","sequence":1,"type":"ci.job.updated"}]}"#
        XCTAssertThrowsError(try FactoryWorkspaceEventBatch.decode(invalid))
    }

    func testValidHistoryContractDecodes() throws {
        let json = """
        {"schema_version":"factory.events.v1","last_sequence":2,
         "events":[
           {"event_id":"a","sequence":1,"type":"runner.job.updated","source":"factory"},
           {"event_id":"b","sequence":2,"type":"runner.job.updated","source":"factory"}
         ]}
        """
        let batch = try FactoryWorkspaceEventBatch.decode(json)
        XCTAssertEqual(batch.events.count, 2)
        XCTAssertEqual(batch.lastSequence, 2)
    }
}
