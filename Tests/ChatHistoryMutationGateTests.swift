import Foundation
import XCTest
@testable import IOSNext

final class ChatHistoryMutationGateTests: XCTestCase {
    @MainActor
    func testConcurrentDurableMutationsObserveOnlyCommittedStateAndRejectOldGeneration() async throws {
        let gate=ChatHistoryMutationGate()
        let initial=ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:[:])
        let stamp=Date(timeIntervalSinceReferenceDate:1000)
        var state=initial, durable=initial, current=true
        var entered=false
        func add(_ id:String) {
            var seen=state.seen
            seen[id]=stamp
            state=ChatPersistentSnapshot(version:1,messages:[],partials:[:],seen:seen)
        }
        let first=Task { @MainActor in
            try await gate.commit(isCurrent:{current},read:{state},apply:{state=$0},mutate:{add("first")}) { previous,next in
                XCTAssertEqual(previous,durable)
                entered=true
                try await Task.sleep(for:.milliseconds(150))
                XCTAssertEqual(state,previous)
                durable=next
            }
        }
        for _ in 0..<200 {
            if entered { break }
            try await Task.sleep(for:.milliseconds(5))
        }
        guard entered else {
            first.cancel()
            return XCTFail("first write did not enter its transaction")
        }
        let second=Task { @MainActor in
            try await gate.commit(isCurrent:{current},read:{state},apply:{state=$0},mutate:{add("second")}) { previous,next in
                XCTAssertEqual(previous,durable)
                XCTAssertEqual(previous.seen["first"],stamp)
                durable=next
            }
        }
        try await first.value
        try await second.value
        XCTAssertEqual(state,durable)
        XCTAssertEqual(Set(state.seen.keys),Set(["first","second"]))
        let before=state
        do {
            try await gate.commit(isCurrent:{current},read:{state},apply:{state=$0},mutate:{add("bad")}) { _,_ in
                throw ChatHistoryError.capacity
            }
            XCTFail("failed write reported success")
        } catch {}
        XCTAssertEqual(state,before)
        do {
            try await gate.commit(isCurrent:{current},read:{state},apply:{state=$0},mutate:{add("old-account")}) { _,next in
                durable=next
                current=false
                state=initial
            }
            XCTFail("old generation result was applied")
        } catch is CancellationError {}
        XCTAssertEqual(state,initial)
        XCTAssertNotNil(durable.seen["old-account"])
    }

    @MainActor
    func testExclusiveAcquisitionCannotOverlapAcrossSuspension() async throws {
        let gate=ChatHistoryMutationGate()
        var inFlight=0, highWater=0
        let tasks=(0..<8).map { _ in
            Task { @MainActor in
                try await gate.withExclusive(isCurrent:{true}) {
                    inFlight += 1
                    highWater=max(highWater,inFlight)
                    defer { inFlight -= 1 }
                    try await Task.sleep(for:.milliseconds(10))
                }
            }
        }
        for task in tasks { try await task.value }
        XCTAssertEqual(highWater,1)
        XCTAssertEqual(inFlight,0)
    }
}
