import XCTest
@testable import IOSNext

final class CommanderLiveTests: XCTestCase {
    private let token = "0123456789abcdef0123456789abcdef"

    func testRunnerStatusDecodesCommanderExtensionWithoutBreakingLegacyFields() throws {
        let data = Data(#"{"vm_online":true,"service_active":true,"registered_runners":14,"idle_runners":14,"busy_runners":0,"commander":{"state":"idle","online":true,"version":"0.2.51","active_sessions":3,"active_searches":0,"active_count":0,"activities":[],"status_confidence":"authoritative"}}"#.utf8)
        let decoder = CommanderLiveCoding.decoder()
        let status = try decoder.decode(RunnerStatus.self, from: data)
        XCTAssertEqual(status.registeredRunners, 14)
        XCTAssertEqual(status.commander?.state, .idle)
        XCTAssertEqual(status.commander?.version, "0.2.51")
    }

    func testLiveURLMapsHTTPSAndCarriesSequence() throws {
        let configuration = RunnerControlConfiguration(
            baseURL: URL(string: "https://runner.example/base/")!,
            token: token,
            liveToken: "fedcba9876543210fedcba9876543210"
        )
        let url = try XCTUnwrap(RunnerLiveClient.liveURL(configuration: configuration, lastSequence: 42))
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertTrue(url.path.hasSuffix("/v1/live"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "42")
    }

    func testFractionalISO8601EventDecodes() throws {
        let data = Data(#"{"schema":1,"seq":7,"type":"heartbeat","timestamp":"2026-09-20T20:00:00.123Z","payload":{"snapshot":null,"activity":null,"active_sessions":null,"active_searches":null,"reason":null}}"#.utf8)
        let event = try CommanderLiveCoding.decoder().decode(RunnerLiveEnvelope.self, from: data)
        XCTAssertEqual(event.seq, 7)
    }

    func testReducerRequiresResyncOnSequenceGap() throws {
        var state = CommanderLiveViewState()
        let snapshot = CommanderSnapshot(state: .idle, online: true, statusConfidence: "authoritative")
        let first = RunnerLiveEnvelope(
            schema: 1,
            seq: 4,
            type: "commander.snapshot",
            timestamp: Date(),
            payload: CommanderLivePayload(snapshot: snapshot, activity: nil, activeSessions: nil, activeSearches: nil, reason: nil)
        )
        XCTAssertEqual(state.apply(first), .applied)
        let gap = RunnerLiveEnvelope(
            schema: 1,
            seq: 6,
            type: "heartbeat",
            timestamp: Date(),
            payload: CommanderLivePayload(snapshot: nil, activity: nil, activeSessions: nil, activeSearches: nil, reason: nil)
        )
        XCTAssertEqual(state.apply(gap), .resyncRequired)
        XCTAssertTrue(state.needsFullResync)
        XCTAssertEqual(state.connection, .degraded)
    }

    func testReducerTracksParallelActivitiesAndReturnsIdle() throws {
        var state = CommanderLiveViewState()
        let snapshot = CommanderSnapshot(state: .idle, online: true, statusConfidence: "authoritative")
        _ = state.apply(.init(
            schema: 1,
            seq: 10,
            type: "commander.snapshot",
            timestamp: Date(),
            payload: .init(snapshot: snapshot, activity: nil, activeSessions: nil, activeSearches: nil, reason: nil)
        ))
        let a = CommanderActivity(id: "cmd-1", tool: "read_file", startedAt: Date(), state: .running, durationMS: nil, completedAt: nil, uncertain: false)
        let b = CommanderActivity(id: "cmd-2", tool: "start_process", startedAt: Date(), state: .running, durationMS: nil, completedAt: nil, uncertain: false)
        _ = state.apply(.init(schema: 1, seq: 11, type: "commander.activity.started", timestamp: Date(), payload: .init(snapshot: nil, activity: a, activeSessions: nil, activeSearches: nil, reason: nil)))
        _ = state.apply(.init(schema: 1, seq: 12, type: "commander.activity.started", timestamp: Date(), payload: .init(snapshot: nil, activity: b, activeSessions: nil, activeSearches: nil, reason: nil)))
        XCTAssertEqual(state.effectiveSnapshot?.activeCount, 2)
        var doneA = a
        doneA.state = .completed
        doneA.completedAt = Date()
        _ = state.apply(.init(schema: 1, seq: 13, type: "commander.activity.completed", timestamp: Date(), payload: .init(snapshot: nil, activity: doneA, activeSessions: nil, activeSearches: nil, reason: nil)))
        XCTAssertEqual(state.effectiveSnapshot?.activeCount, 1)
        var doneB = b
        doneB.state = .completed
        doneB.completedAt = Date()
        _ = state.apply(.init(schema: 1, seq: 14, type: "commander.activity.completed", timestamp: Date(), payload: .init(snapshot: nil, activity: doneB, activeSessions: nil, activeSearches: nil, reason: nil)))
        XCTAssertEqual(state.effectiveSnapshot?.activeCount, 0)
        XCTAssertEqual(state.effectiveSnapshot?.state, .idle)
    }

    func testDuplicateEventIsIdempotent() {
        var state = CommanderLiveViewState()
        let snapshot = CommanderSnapshot(state: .idle, online: true, statusConfidence: "authoritative")
        let event = RunnerLiveEnvelope(
            schema: 1,
            seq: 1,
            type: "commander.snapshot",
            timestamp: Date(),
            payload: .init(snapshot: snapshot, activity: nil, activeSessions: nil, activeSearches: nil, reason: nil)
        )
        XCTAssertEqual(state.apply(event), .applied)
        let heartbeat = RunnerLiveEnvelope(
            schema: 1,
            seq: 2,
            type: "heartbeat",
            timestamp: Date(),
            payload: .init(snapshot: nil, activity: nil, activeSessions: nil, activeSearches: nil, reason: nil)
        )
        XCTAssertEqual(state.apply(heartbeat), .applied)
        XCTAssertEqual(state.apply(heartbeat), .duplicate)
    }

    func testCommanderLiveFixtureStatusAndWebSocketUseSeparatedCredentials() async throws {
        guard let port = ProcessInfo.processInfo.environment["FAKE_RUNNER_PORT"], !port.isEmpty else {
            throw XCTSkip("FAKE_RUNNER_PORT is only injected by the isolated Xcode integration gate")
        }
        let controlToken = ProcessInfo.processInfo.environment["FAKE_RUNNER_CONTROL_TOKEN"] ?? ""
        let liveToken = ProcessInfo.processInfo.environment["FAKE_RUNNER_LIVE_TOKEN"] ?? ""
        XCTAssertFalse(controlToken.isEmpty)
        XCTAssertFalse(liveToken.isEmpty)
        XCTAssertNotEqual(controlToken, liveToken)

        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/"))
        let statusConfiguration = RunnerControlConfiguration(
            baseURL: baseURL,
            token: controlToken,
            liveToken: liveToken
        )
        let statusClient = RunnerControlClient()
        let status = try await statusClient.status(configuration: statusConfiguration)
        XCTAssertEqual(status.commander?.state, .idle)
        XCTAssertEqual(status.commander?.statusConfidence, "authoritative")

        // Intentionally poison the control credential. A successful WebSocket proves
        // RunnerLiveClient authenticates only with the dedicated read-only live token.
        let liveConfiguration = RunnerControlConfiguration(
            baseURL: baseURL,
            token: "wrong-control-token",
            liveToken: liveToken
        )
        let liveClient = RunnerLiveClient()
        defer { Task { await liveClient.disconnect() } }
        let stream = try await liveClient.stream(configuration: liveConfiguration, lastSequence: nil)
        let event = try await firstLiveEvent(from: stream)
        XCTAssertEqual(event.type, "commander.snapshot")
        XCTAssertEqual(event.payload.snapshot?.state, .idle)
        XCTAssertEqual(event.payload.snapshot?.version, "fixture-0.2.51")
    }

    private func firstLiveEvent(
        from stream: AsyncThrowingStream<RunnerLiveEnvelope, Error>
    ) async throws -> RunnerLiveEnvelope {
        try await withThrowingTaskGroup(of: RunnerLiveEnvelope.self) { group in
            group.addTask {
                for try await event in stream { return event }
                throw RunnerLiveError.disconnected
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw RunnerLiveError.timedOut
            }
            guard let event = try await group.next() else {
                group.cancelAll()
                throw RunnerLiveError.disconnected
            }
            group.cancelAll()
            return event
        }
    }

}
