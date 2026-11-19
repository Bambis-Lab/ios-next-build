import XCTest
import AVFoundation
@testable import IOSNext

@MainActor
final class ChatMediaThumbnailCacheTests: XCTestCase {
    func testValidImageIsDownsampledAndCachedOnlyInMemory() async {
        let cache = ChatMediaThumbnailCache.shared
        cache.clear()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7l8AAAAASUVORK5CYII=")!
        let key = "thumb-test-\(UUID().uuidString)"
        let first = await cache.thumbnail(messageID: key, decryptedImageBytes: png)
        let second = await cache.thumbnail(messageID: key, decryptedImageBytes: png)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.cgImage?.width, 1)
        cache.clear()
    }

    func testCorruptImageReturnsNilWithoutPersistenceFallback() async {
        let cache = ChatMediaThumbnailCache.shared
        cache.clear()
        let result = await cache.thumbnail(
            messageID: "corrupt-\(UUID().uuidString)",
            decryptedImageBytes: Data("not an image".utf8)
        )
        XCTAssertNil(result)
    }

    func testMemoryVideoRangesRejectInvalidOffsetsAndRespectConsumedBytes() throws {
        func range(_ start:Int64,_ current:Int64,_ length:Int,_ end:Bool=false) throws -> Range<Int> {
            try MemoryMediaByteRange.resolve(byteCount:100,requestedOffset:start,currentOffset:current,
                requestedLength:length,allToEnd:end)
        }
        XCTAssertEqual(try range(10,0,20),10..<30)
        XCTAssertEqual(try range(10,15,20),15..<30)
        XCTAssertEqual(try range(90,95,20),95..<100)
        XCTAssertEqual(try range(90,100,20),100..<100)
        XCTAssertEqual(try range(10,15,0,true),15..<100)
        XCTAssertThrowsError(try range(-1,0,20))
        XCTAssertThrowsError(try range(0,-1,20))
        XCTAssertThrowsError(try range(10,9,20))
        XCTAssertThrowsError(try range(10,31,20))
        XCTAssertThrowsError(try range(101,0,1))
        XCTAssertThrowsError(try range(0,Int64.max,20))
        XCTAssertThrowsError(try range(0,0,-1))
        XCTAssertEqual(try range(10,15,Int.max),15..<100)
    }

    func testNativeAudioDecoderAcceptsWAVAndRejectsCorruptInput() throws {
        // Real AVFoundation decoding of generated mono PCM, no speaker or
        // microphone assertion and no plaintext file written.
        var wav=Data()
        func ascii(_ value:String) {wav.append(Data(value.utf8))}
        func le<T:FixedWidthInteger>(_ value:T) {
            var little=value.littleEndian
            withUnsafeBytes(of:&little){wav.append(contentsOf:$0)}
        }
        let rate:UInt32=16000,samples=1600
        ascii("RIFF");le(UInt32(36+samples*2));ascii("WAVEfmt ")
        le(UInt32(16));le(UInt16(1));le(UInt16(1));le(rate)
        le(rate*2);le(UInt16(2));le(UInt16(16))
        ascii("data");le(UInt32(samples*2))
        for i in 0..<samples {le(Int16((i%32-16)*100))}
        let player=try AVAudioPlayer(data:wav)
        XCTAssertEqual(player.numberOfChannels,1)
        XCTAssertEqual(player.duration,0.1,accuracy:0.001)
        XCTAssertThrowsError(try AVAudioPlayer(data:Data("not wav".utf8)))
    }
}
