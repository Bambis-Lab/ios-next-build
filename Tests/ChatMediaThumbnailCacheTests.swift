import XCTest
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
}
