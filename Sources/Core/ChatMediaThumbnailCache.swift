import Foundation
import ImageIO
import UIKit

/// Bounded RAM-only chat-image previews. No original or decrypted image bytes
/// are ever written to an unencrypted cache directory.
@MainActor
final class ChatMediaThumbnailCache {
    static let shared = ChatMediaThumbnailCache()

    private let thumbnails = NSCache<NSString, UIImage>()
    private let maxPixelSize = 640

    private init() {
        thumbnails.countLimit = 36
        thumbnails.totalCostLimit = 24 * 1024 * 1024
    }

    func thumbnail(messageID: String, decryptedImageBytes imageBytes: Data) -> UIImage? {
        let key = messageID as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }

        // ImageIO downsamples before UIKit has to allocate a full-resolution
        // bitmap. Failed/corrupt payloads return nil without a disk fallback.
        guard let source = CGImageSourceCreateWithData(imageBytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary) else { return nil }
        let preview = UIImage(cgImage: image)
        let decodedCost = image.bytesPerRow * image.height
        thumbnails.setObject(preview, forKey: key, cost: decodedCost)
        return preview
    }

    func clear() {
        thumbnails.removeAllObjects()
    }
}
