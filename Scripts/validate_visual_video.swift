#!/usr/bin/env swift
import AVFoundation
import CoreGraphics
import Foundation

enum ValidationMode: String {
    case cold
    case animation
}

struct FrameStats {
    let meanR: Double
    let meanG: Double
    let meanB: Double
    let mean: Double
    let deviation: Double
    let blackRatio: Double
    let whiteRatio: Double
    let dynamicRange: Double

    var isExtremeBlank: Bool {
        mean < 0.012
            || mean > 0.988
            || (blackRatio > 0.995 && deviation < 0.025)
            || (whiteRatio > 0.995 && deviation < 0.025)
    }

    var isContentRich: Bool {
        deviation >= 0.035 && dynamicRange >= 0.18
    }

    var fingerprint: String {
        let meanBucket = Int((mean * 20).rounded())
        let deviationBucket = Int((deviation * 20).rounded())
        let rangeBucket = Int((dynamicRange * 10).rounded())
        return "\(meanBucket)-\(deviationBucket)-\(rangeBucket)"
    }
}

func frameStats(_ image: CGImage) -> FrameStats? {
    let sampleWidth = 80
    let aspect = Double(image.height) / Double(max(image.width, 1))
    let sampleHeight = max(80, min(180, Int((Double(sampleWidth) * aspect).rounded())))
    let bytesPerRow = sampleWidth * 4
    var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

    guard let context = CGContext(
        data: &pixels,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

    var count = 0
    var sumR = 0.0
    var sumG = 0.0
    var sumB = 0.0
    var sum = 0.0
    var sumSquares = 0.0
    var black = 0
    var white = 0
    var minLuma = 1.0
    var maxLuma = 0.0

    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[offset]) / 255.0
        let g = Double(pixels[offset + 1]) / 255.0
        let b = Double(pixels[offset + 2]) / 255.0
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

        count += 1
        sumR += r
        sumG += g
        sumB += b
        sum += luma
        sumSquares += luma * luma
        minLuma = min(minLuma, luma)
        maxLuma = max(maxLuma, luma)
        if luma < 0.02 { black += 1 }
        if luma > 0.98 { white += 1 }
    }

    guard count > 0 else { return nil }

    let mean = sum / Double(count)
    let variance = max(0, sumSquares / Double(count) - mean * mean)

    return FrameStats(
        meanR: sumR / Double(count),
        meanG: sumG / Double(count),
        meanB: sumB / Double(count),
        mean: mean,
        deviation: sqrt(variance),
        blackRatio: Double(black) / Double(count),
        whiteRatio: Double(white) / Double(count),
        dynamicRange: maxLuma - minLuma
    )
}

func darkLaunchColor() -> (Double, Double, Double)? {
    let url = URL(fileURLWithPath: "Assets.xcassets/LaunchBackground.colorset/Contents.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let colors = root["colors"] as? [[String: Any]] else {
        return nil
    }

    for entry in colors {
        guard let appearances = entry["appearances"] as? [[String: String]],
              appearances.contains(where: {
                  $0["appearance"] == "luminosity" && $0["value"] == "dark"
              }),
              let color = entry["color"] as? [String: Any],
              let components = color["components"] as? [String: String],
              let red = components["red"].flatMap(Double.init),
              let green = components["green"].flatMap(Double.init),
              let blue = components["blue"].flatMap(Double.init) else {
            continue
        }
        return (red, green, blue)
    }

    return nil
}

guard CommandLine.arguments.count >= 3,
      let mode = ValidationMode(rawValue: CommandLine.arguments[2]) else {
    fputs("usage: validate_visual_video.swift <video.mp4> <cold|animation>\n", stderr)
    exit(64)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard FileManager.default.fileExists(atPath: path) else {
    fputs("video-validation: file missing: \(path)\n", stderr)
    exit(2)
}

let asset = AVURLAsset(url: url)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0.5 else {
    fputs("video-validation: invalid duration: \(duration)\n", stderr)
    exit(3)
}

let minimumDuration = mode == .cold ? 2.0 : 10.0
guard duration >= minimumDuration else {
    fputs("video-validation: duration too short for \(mode.rawValue): \(duration)\n", stderr)
    exit(4)
}

let expectedLaunchColor = mode == .cold ? darkLaunchColor() : nil
if mode == .cold, expectedLaunchColor == nil {
    fputs("video-validation: unable to load dark LaunchBackground asset color\n", stderr)
    exit(5)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = CMTime(seconds: 0.025, preferredTimescale: 600)
generator.requestedTimeToleranceAfter = CMTime(seconds: 0.025, preferredTimescale: 600)

let sampleInterval = mode == .cold ? 0.033 : 0.20
let startTime = min(0.05, duration / 4)
let endTime = max(startTime, duration - 0.05)

var sampleTimes: [Double] = []
var time = startTime
while time <= endTime {
    sampleTimes.append(time)
    time += sampleInterval
}

var decoded = 0
var extremeBlankFrames = 0
var contentRichFrames = 0
var fingerprints = Set<String>()
var firstExtremeBlankTime: Double?
var launchLikeFrames = 0
var contentFramesAfterLaunch = 0
var sawLaunchFrame = false

for seconds in sampleTimes {
    let requested = CMTime(seconds: seconds, preferredTimescale: 600)
    do {
        var actual = CMTime.zero
        let image = try generator.copyCGImage(at: requested, actualTime: &actual)
        guard let stats = frameStats(image) else { continue }

        decoded += 1
        fingerprints.insert(stats.fingerprint)

        if stats.isExtremeBlank {
            extremeBlankFrames += 1
            if firstExtremeBlankTime == nil {
                firstExtremeBlankTime = CMTimeGetSeconds(actual)
            }
        }

        if mode == .cold, let expectedLaunchColor {
            let launchDistance = max(
                abs(stats.meanR - expectedLaunchColor.0),
                abs(stats.meanG - expectedLaunchColor.1),
                abs(stats.meanB - expectedLaunchColor.2)
            )
            if launchDistance <= 0.06 && stats.deviation <= 0.035 {
                launchLikeFrames += 1
                sawLaunchFrame = true
            }
        }

        if stats.isContentRich {
            contentRichFrames += 1
            if sawLaunchFrame {
                contentFramesAfterLaunch += 1
            }
        }
    } catch {
        fputs("video-validation: frame decode failed at \(String(format: "%.2f", seconds))s: \(error)\n", stderr)
    }
}

let minimumDecoded = mode == .cold ? 20 : 40
let minimumRichFrames = mode == .cold ? 1 : 8
let minimumFingerprints = mode == .cold ? 2 : 5

print(
    "video-validation: \(path) mode=\(mode.rawValue) " +
    "duration=\(String(format: "%.3f", duration)) " +
    "requested=\(sampleTimes.count) decoded=\(decoded) " +
    "blank=\(extremeBlankFrames) rich=\(contentRichFrames) " +
    "fingerprints=\(fingerprints.count) launch=\(launchLikeFrames) " +
    "contentAfterLaunch=\(contentFramesAfterLaunch)"
)

guard decoded >= minimumDecoded else {
    fputs("video-validation: too few decoded frames\n", stderr)
    exit(10)
}

guard extremeBlankFrames == 0 else {
    let timeText = firstExtremeBlankTime.map { String(format: "%.3f", $0) } ?? "unknown"
    fputs("video-validation: extreme blank/black frame detected near \(timeText)s\n", stderr)
    exit(11)
}

guard contentRichFrames >= minimumRichFrames else {
    fputs("video-validation: insufficient rendered content variation\n", stderr)
    exit(12)
}

if mode == .cold {
    guard launchLikeFrames >= 1 else {
        fputs("video-validation: dark Launch Screen color was not observed\n", stderr)
        exit(14)
    }

    guard contentFramesAfterLaunch >= 1 else {
        fputs("video-validation: no rendered app content observed after Launch Screen\n", stderr)
        exit(15)
    }
}

guard fingerprints.count >= minimumFingerprints else {
    fputs("video-validation: video appears visually static\n", stderr)
    exit(13)
}
