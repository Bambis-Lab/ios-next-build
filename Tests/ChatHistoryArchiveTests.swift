import Foundation
import XCTest
@testable import IOSNext

final class ChatHistoryArchiveTests: XCTestCase {
    private struct FragmentState: Codable, Equatable {
        var chunks: [Int: Data] = [:]
        var seen: [String] = []
    }

    @MainActor
    func testCheckpointRestoresOnFailureAndReopensCommittedFragments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fragments.enc")
        let scope = Data("synthetic-receiver".utf8)
        let key = Data(repeating: 7, count: 32)
        let archive = try ChatHistoryArchive(file: file, scope: scope, keyData: key)
        var state = FragmentState()
        var acknowledgements: [String] = []
        func receive(_ index: Int, id: String, fail: Bool) throws {
            // Same transaction boundary used by ChatModel.
            try ChatHistoryCheckpoint.commit(previous: state, mutate: {
                state.chunks[index] = Data([UInt8(index)])
                state.seen.append(id)
            }, persist: {
                if fail { throw ChatHistoryError.capacity }
                try archive.save(state)
            }, restore: { state = $0 })
            acknowledgements.append(id)
        }
        try receive(0, id: "first", fail: false)
        let checkpoint = state
        XCTAssertThrowsError(try receive(1, id: "second", fail: true))
        XCTAssertEqual(state, checkpoint)
        XCTAssertEqual(acknowledgements, ["first"])
        let reopened = try ChatHistoryArchive(file: file, scope: scope, keyData: key)
        state = try XCTUnwrap(reopened.load(FragmentState.self))
        XCTAssertEqual(state.chunks, [0: Data([0])])
        try receive(1, id: "second", fail: false)
        XCTAssertEqual(acknowledgements, ["first", "second"])
        XCTAssertEqual(try reopened.load(FragmentState.self), state)
        XCTAssertEqual(state.chunks, [0: Data([0]), 1: Data([1])])
        let complete = state
        XCTAssertThrowsError(try ChatHistoryCheckpoint.commit(previous: state, mutate: {
            state.chunks.removeAll()
            throw ChatError.invalidEnvelope
        }, persist: {
            XCTFail("Invalid mutation must not persist")
        }, restore: { state = $0 }))
        XCTAssertEqual(state, complete)
        XCTAssertEqual(try reopened.load(FragmentState.self), complete)
    }

    @MainActor
    func testAuthenticatedArchiveRoundtripAndScopeIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.enc")
        let key = Data(repeating: 3, count: 32)
        let scope = Data("fixture-account-a".utf8)
        let a = try ChatHistoryArchive(file: file, scope: scope, keyData: key)
        let text = "synthetic private message"
        XCTAssertNil(try a.load([String].self))
        try a.save([text])
        let original = try Data(contentsOf: file)
        XCTAssertNil(original.range(of: Data(text.utf8)))
        let reopened = try ChatHistoryArchive(file: file, scope: scope, keyData: key)
        XCTAssertEqual(try reopened.load([String].self), [text])
        let foreign = try ChatHistoryArchive(file: file, scope: Data("fixture-account-b".utf8), keyData: key)
        XCTAssertThrowsError(try foreign.load([String].self))
        let wrong = try ChatHistoryArchive(file: file, scope: scope, keyData: Data(repeating: 4, count: 32))
        XCTAssertThrowsError(try wrong.load([String].self))
        try a.save([text])
        XCTAssertNotEqual(original, try Data(contentsOf: file))
        var corrupt = try Data(contentsOf: file)
        corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: file)
        XCTAssertThrowsError(try reopened.load([String].self))
    }
}
