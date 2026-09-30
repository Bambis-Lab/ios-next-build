import XCTest
@testable import IOSNext

final class LiveOperationsTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"

    func testLiveURLMapsHTTPSAndCarriesBothSequences() throws {
        let configuration = LiveOperationsConfiguration(
            baseURL: URL(string: "https://live.example/base/")!,
            token: token
        )
        let url = try XCTUnwrap(LiveOperationsClient.liveURL(
            configuration: configuration,
            lastMCPSequence: 42,
            lastSentinelSequence: 9
        ))
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertTrue(url.path.hasSuffix("/v1/live"))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["last_mcp_seq"], "42")
        XCTAssertEqual(items["last_sentinelx_seq"], "9")
    }

    func testReducerKeepsSequencesIndependent() throws {
        var mcp = LiveOperationsSourceState(source: .mcp)
        var sentinel = LiveOperationsSourceState(source: .sentinelX)
        let decoder = LiveOperationsCoding.decoder()

        let mcpEvent = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"mcp","seq":1,"type":"source.status","timestamp":"2026-09-24T09:00:00.000Z","payload":{"online":true}}"#.utf8))
        let sxEvent = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":1,"type":"source.status","timestamp":"2026-09-24T09:00:00.000Z","payload":{"online":true}}"#.utf8))

        XCTAssertEqual(mcp.apply(mcpEvent), .applied)
        XCTAssertEqual(sentinel.apply(sxEvent), .applied)
        XCTAssertEqual(mcp.lastSequence, 1)
        XCTAssertEqual(sentinel.lastSequence, 1)
        XCTAssertTrue(mcp.online)
        XCTAssertTrue(sentinel.online)
    }

    func testReducerRequestsResyncOnGap() throws {
        var state = LiveOperationsSourceState(source: .mcp)
        let decoder = LiveOperationsCoding.decoder()
        let first = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"mcp","seq":1,"type":"heartbeat","timestamp":"2026-09-24T09:00:00.000Z","payload":{}}"#.utf8))
        let third = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"mcp","seq":3,"type":"heartbeat","timestamp":"2026-09-24T09:00:01.000Z","payload":{}}"#.utf8))
        XCTAssertEqual(state.apply(first), .applied)
        XCTAssertEqual(state.apply(third), .resyncRequired)
        XCTAssertTrue(state.needsFullResync)
    }

    func testAuthoritativeSnapshotRepairsSequenceGap() throws {
        var state = LiveOperationsSourceState(source: .sentinelX)
        let decoder = LiveOperationsCoding.decoder()
        let first = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":1,"type":"heartbeat","timestamp":"2026-09-24T09:00:00.000Z","payload":{}}"#.utf8))
        let gap = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":3,"type":"heartbeat","timestamp":"2026-09-24T09:00:02.000Z","payload":{}}"#.utf8))
        let snapshot = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":20,"type":"source.snapshot","timestamp":"2026-09-24T09:00:03.000Z","payload":{"snapshot":{"source":"sentinelx","online":true,"last_seq":20,"active_operations":[],"recent_operations":[],"metrics":{"cpu_percent":18.0},"source_metadata":{"host":"DESKTOP-J94UIA0","agent_version":"0.18.4"}}}}"#.utf8))

        XCTAssertEqual(state.apply(first), .applied)
        XCTAssertEqual(state.apply(gap), .resyncRequired)
        XCTAssertTrue(state.needsFullResync)
        XCTAssertEqual(state.apply(snapshot), .applied)
        XCTAssertFalse(state.needsFullResync)
        XCTAssertEqual(state.lastSequence, 20)
        XCTAssertTrue(state.online)
        XCTAssertEqual(state.sourceMetadata["host"], .string("DESKTOP-J94UIA0"))
    }

    func testOperationLifecycleMovesToRecent() throws {
        var state = LiveOperationsSourceState(source: .mcp)
        let decoder = LiveOperationsCoding.decoder()
        let started = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"mcp","seq":1,"type":"operation.started","timestamp":"2026-09-24T09:00:00.000Z","payload":{"operation":{"id":"mcp_1","source":"mcp","kind":"toolCall","title":"GitHub.fetch_file","state":"running","started_at":"2026-09-24T09:00:00.000Z","updated_at":"2026-09-24T09:00:00.000Z","repository":"Bambis-Lab/ios-next"}}}"#.utf8))
        let completed = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"mcp","seq":2,"type":"operation.completed","timestamp":"2026-09-24T09:00:01.000Z","payload":{"operation":{"id":"mcp_1","source":"mcp","kind":"toolCall","title":"GitHub.fetch_file","state":"completed","started_at":"2026-09-24T09:00:00.000Z","updated_at":"2026-09-24T09:00:01.000Z","completed_at":"2026-09-24T09:00:01.000Z","duration_ms":1000,"repository":"Bambis-Lab/ios-next"}}}"#.utf8))

        XCTAssertEqual(state.apply(started), .applied)
        XCTAssertEqual(state.activeOperations.count, 1)
        XCTAssertEqual(state.apply(completed), .applied)
        XCTAssertEqual(state.activeOperations.count, 0)
        XCTAssertEqual(state.recentOperations.first?.durationMS, 1000)
    }

    func testMetricsMergeWithoutDestroyingOtherValues() throws {
        var state = LiveOperationsSourceState(source: .sentinelX)
        let decoder = LiveOperationsCoding.decoder()
        let first = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":1,"type":"metrics.updated","timestamp":"2026-09-24T09:00:00.000Z","payload":{"metrics":{"cpu_percent":22.5,"memory_percent":61.7},"source_metadata":{"host":"DESKTOP-J94UIA0","agent_version":"0.18.4"}}}"#.utf8))
        let second = try decoder.decode(LiveOperationsEnvelope.self, from: Data(#"{"schema":1,"source":"sentinelx","seq":2,"type":"metrics.updated","timestamp":"2026-09-24T09:00:01.000Z","payload":{"metrics":{"cpu_percent":24.0}}}"#.utf8))

        XCTAssertEqual(state.apply(first), .applied)
        XCTAssertEqual(state.apply(second), .applied)
        XCTAssertEqual(state.metrics["cpu_percent"], .double(24.0))
        XCTAssertEqual(state.metrics["memory_percent"], .double(61.7))
        XCTAssertEqual(state.sourceMetadata["host"], .string("DESKTOP-J94UIA0"))
    }
}
