import XCTest
@testable import IOSNext

@MainActor
final class LatestValueCommandQueueTests: XCTestCase {
    func testRapidColorValuesCoalesceToLatest() async throws {
        let queue = LatestValueCommandQueue<Int>(settlingDelay: .milliseconds(20))
        var applied: [Int] = []
        queue.submit(1) { applied.append($0) }
        queue.submit(2) { applied.append($0) }
        queue.submit(3) { applied.append($0) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(applied, [3])
    }

    func testLatestValueIsNotLostWhilePreviousWriteIsInFlight() async throws {
        let queue = LatestValueCommandQueue<Int>(settlingDelay: .milliseconds(10))
        var applied: [Int] = []
        queue.submit(1) {
            applied.append($0)
            try? await Task.sleep(for: .milliseconds(70))
        }
        try await Task.sleep(for: .milliseconds(30))
        queue.submit(2) { applied.append($0) }
        queue.submit(3) { applied.append($0) }
        try await Task.sleep(for: .milliseconds(170))
        XCTAssertEqual(applied, [1, 3])
    }

    func testCancelPendingDoesNotSendUncommittedChanges() async throws {
        let queue = LatestValueCommandQueue<Int>(settlingDelay: .milliseconds(90))
        var applied: [Int] = []
        queue.submit(4) { applied.append($0) }
        queue.cancelPending()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(applied.isEmpty)
    }
}
