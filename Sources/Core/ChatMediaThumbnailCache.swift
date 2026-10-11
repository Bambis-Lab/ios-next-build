import Foundation
import ImageIO
import UIKit

/// Bounded RAM-only chat-image previews. No original or decrypted image bytes
/// are ever written to an unencrypted cache directory.
private struct ChatThumbnailPayload: @unchecked Sendable {
    let cgImage: CGImage
}

@MainActor
final class ChatMediaThumbnailCache {
    static let shared = ChatMediaThumbnailCache()

    private let thumbnails = NSCache<NSString, UIImage>()
    private let maxPixelSize = 640

    private init() {
        thumbnails.countLimit = 36
        thumbnails.totalCostLimit = 24 * 1024 * 1024
    }

    /// Decodes off the main actor. Only the downsampled immutable CGImage is
    /// sent back; caching and UIImage presentation remain on the main actor.
    func thumbnail(messageID: String, decryptedImageBytes imageBytes: Data) async -> UIImage? {
        let key = messageID as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let trace = IOSNextPerformance.begin("Chat.ThumbnailDecode")
        defer { IOSNextPerformance.end("Chat.ThumbnailDecode", trace) }
        let limit = maxPixelSize
        let payload = await Task.detached(priority: .userInitiated) {
            Self.makeThumbnail(data: imageBytes, maxPixelSize: limit)
        }.value
        guard !Task.isCancelled, let payload else { return nil }
        if let raced = thumbnails.object(forKey: key) { return raced }
        let preview = UIImage(cgImage: payload.cgImage)
        let decodedCost = payload.cgImage.bytesPerRow * payload.cgImage.height
        thumbnails.setObject(preview, forKey: key, cost: decodedCost)
        return preview
    }

    func clear() {
        thumbnails.removeAllObjects()
    }

    private nonisolated static func makeThumbnail(
        data: Data, maxPixelSize: Int
    ) -> ChatThumbnailPayload? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { return nil }
        return ChatThumbnailPayload(cgImage: image)
    }
}
