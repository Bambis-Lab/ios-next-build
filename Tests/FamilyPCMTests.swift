import XCTest
@testable import IOSNext

final class FamilyPCMTests: XCTestCase {
    func testPCMEncodingAndNonfiniteSamples() throws {
        var frame = [Float](repeating: 0, count: FamilyPCM.samples)
        frame[0] = 1
        frame[1] = -1
        frame[2] = .nan
        frame[3] = .infinity
        let encoded = try FamilyPCM.encode(frame)
        XCTAssertEqual(encoded.count, 640)
        XCTAssertEqual(Array(encoded.prefix(8)), [255,127,1,128,0,0,0,0])
        let decoded = try FamilyPCM.decode(encoded)
        XCTAssertEqual(decoded[0], 1)
        XCTAssertEqual(decoded[1], -1)
        XCTAssertEqual(decoded[2], 0)
        XCTAssertEqual(decoded[3], 0)
        XCTAssertThrowsError(try FamilyPCM.decode(Data()))
        XCTAssertThrowsError(try FamilyPCM.encode([0]))
    }

    func testCaptureFramingBoundAndMute() throws {
        let queue = FamilyPCMQueue()
        queue.append(Array(repeating: 0.2, count: 100))
        XCTAssertNil(queue.take())
        queue.append(Array(repeating: 0.2, count: 220))
        XCTAssertEqual(queue.take()?.count, 640)
        queue.append(Array(repeating: 0.2, count: 320 * 15))
        for _ in 0..<10 { XCTAssertNotNil(queue.take()) }
        XCTAssertNil(queue.take())
        queue.append(Array(repeating: 0.3, count: 320))
        queue.setMuted(true)
        queue.append(Array(repeating: 1, count: 320))
        XCTAssertNil(queue.take())
        queue.setMuted(false)
        XCTAssertNil(queue.take())
        queue.close()
        queue.append(Array(repeating: 1, count: 320))
        XCTAssertNil(queue.take())
    }

    func testPlayoutPrefillLossAndReplay() throws {
        var buffer = FamilyPCMPlayout()
        let one = Data(repeating: 1, count: 640)
        let two = Data(repeating: 2, count: 640)
        try buffer.insert(sequence: 0, frame: one)
        try buffer.insert(sequence: 2, frame: two)
        XCTAssertNil(buffer.next())
        try buffer.insert(sequence: 3, frame: one)
        XCTAssertEqual(buffer.next(), one)
        XCTAssertEqual(buffer.next(), FamilyPCM.silence)
        XCTAssertEqual(buffer.next(), two)
        XCTAssertEqual(buffer.next(), one)
        XCTAssertEqual(buffer.next(), FamilyPCM.silence)
        XCTAssertEqual(buffer.next(), FamilyPCM.silence)
        XCTAssertNil(buffer.next())
        XCTAssertThrowsError(try buffer.insert(sequence: 2, frame: two))
        for sequence in 10...25 { try buffer.insert(sequence: UInt64(sequence), frame: one) }
        XCTAssertEqual(buffer.bufferedCount, 10)
        XCTAssertEqual(buffer.next(), one)
    }
}
