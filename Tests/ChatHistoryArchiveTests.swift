import Foundation
import XCTest
@testable import IOSNext

final class ChatHistoryArchiveTests: XCTestCase {
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
