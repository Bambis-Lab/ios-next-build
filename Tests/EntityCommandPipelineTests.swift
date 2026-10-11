import XCTest
@testable import IOSNext

@MainActor
final class EntityCommandPipelineTests: XCTestCase {
    func testCommandsForSameEntityExecuteSequentially() async throws {
        let pipeline = EntityCommandPipeline()
        var events: [String] = []
        let first = Task {
            await pipeline.execute(entityID: "light.schrank") {
                events.append("start-A")
                try? await Task.sleep(for: .milliseconds(65))
                events.append("end-A")
                return .executed
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task {
            await pipeline.execute(entityID: "light.schrank") {
                events.append("B")
                return .executed
            }
        }
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .executed)
        XCTAssertEqual(secondResult, .executed)
        XCTAssertEqual(events, ["start-A", "end-A", "B"])
    }

    func testQueuedAbsoluteValuesCoalesceWithoutDroppingFinalIntent() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [Int] = []
        let first = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(1)
                try? await Task.sleep(for: .milliseconds(80))
                return .executed
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let obsolete = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(2)
                return .executed
            }
        }
        try await Task.sleep(for: .milliseconds(12))
        let white = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(3)
                return .executed
            }
        }
        let firstResult = await first.value
        let obsoleteResult = await obsolete.value
        let whiteResult = await white.value
        XCTAssertEqual(firstResult, .executed)
        XCTAssertEqual(obsoleteResult, .superseded)
        XCTAssertEqual(whiteResult, .executed)
        XCTAssertEqual(applied, [1, 3])
    }

    func testOperationMayReportCancelledOrUnknownOutcome() async {
        let pipeline = EntityCommandPipeline()
        let cancelled = await pipeline.execute(entityID: "light.test") { .cancelled }
        let unknown = await pipeline.execute(entityID: "light.test") { .outcomeUnknown("transport closed") }
        let failed = await pipeline.execute(entityID: "light.test") { .failed("service rejected") }
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(unknown, .outcomeUnknown("transport closed"))
        XCTAssertEqual(failed, .failed("service rejected"))
    }

    func testOrderOnlyActionsNeverCoalesce() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [String] = []
        let a = Task {
            await pipeline.execute(entityID: "switch.test") { applied.append("off"); return .executed }
        }
        let b = Task {
            await pipeline.execute(entityID: "switch.test") { applied.append("on"); return .executed }
        }
        _ = await (a.value, b.value)
        XCTAssertEqual(applied.count, 2)
        XCTAssertEqual(Set(applied), ["off", "on"])
    }

    func testDisconnectDropsOnlyQueuedCommands() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [Int] = []
        let running = Task {
            await pipeline.execute(entityID: "light.schrank") {
                applied.append(1)
                try? await Task.sleep(for: .milliseconds(65))
                return .executed
            }
        }
        try await Task.sleep(for: .milliseconds(15))
        let pending = Task {
            await pipeline.execute(entityID: "light.schrank") { applied.append(2); return .executed }
        }
        try await Task.sleep(for: .milliseconds(12))
        pipeline.invalidatePending()
        let runningResult = await running.value
        let pendingResult = await pending.value
        guard case .outcomeUnknown = runningResult else {
            return XCTFail("An in-flight action invalidated by disconnect must report an unknown outcome.")
        }
        XCTAssertEqual(pendingResult, .cancelled)
        XCTAssertEqual(applied, [1])
    }

    func testNewGenerationWaitsUntilInvalidatedOperationUnwinds() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [String] = []
        let old = Task {
            await pipeline.execute(entityID: "light.test") {
                applied.append("old-start")
                try? await Task.sleep(for: .milliseconds(60))
                applied.append("old-end")
                return .executed
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        pipeline.invalidatePending()
        let fresh = Task {
            await pipeline.execute(entityID: "light.test") {
                applied.append("fresh")
                return .executed
            }
        }
        let oldResult = await old.value
        let freshResult = await fresh.value
        guard case .outcomeUnknown = oldResult else {
            return XCTFail("Old in-flight action must be reported as uncertain.")
        }
        XCTAssertEqual(freshResult, .executed)
        XCTAssertEqual(applied, ["old-start", "old-end", "fresh"])
    }

}
