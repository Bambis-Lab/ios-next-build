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
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task {
            await pipeline.execute(entityID: "light.schrank") { events.append("B") }
        }
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(events, ["start-A", "end-A", "B"])
    }

    func testQueuedAbsoluteValuesCoalesceWithoutDroppingFinalIntent() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [Int] = []
        let first = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(1)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let obsolete = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(2)
            }
        }
        try await Task.sleep(for: .milliseconds(12))
        let white = Task {
            await pipeline.execute(entityID: "light.schrank", coalescingKey: "light.appearance") {
                applied.append(3)
            }
        }
        let firstResult = await first.value
        let obsoleteResult = await obsolete.value
        let whiteResult = await white.value
        XCTAssertTrue(firstResult)
        XCTAssertFalse(obsoleteResult)
        XCTAssertTrue(whiteResult)
        XCTAssertEqual(applied, [1, 3])
    }

    func testOrderOnlyActionsNeverCoalesce() async throws {
        let pipeline = EntityCommandPipeline()
        var applied: [String] = []
        let a = Task { await pipeline.execute(entityID: "switch.test") { applied.append("off") } }
        let b = Task { await pipeline.execute(entityID: "switch.test") { applied.append("on") } }
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
            }
        }
        try await Task.sleep(for: .milliseconds(15))
        let pending = Task {
            await pipeline.execute(entityID: "light.schrank") { applied.append(2) }
        }
        try await Task.sleep(for: .milliseconds(12))
        pipeline.invalidatePending()
        let runningResult = await running.value
        let pendingResult = await pending.value
        XCTAssertTrue(runningResult)
        XCTAssertFalse(pendingResult)
        XCTAssertEqual(applied, [1])
    }
}
