#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("usage: validate_visual_capture.swift <png>\n", stderr)
    exit(64)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path) as CFURL
guard let source = CGImageSourceCreateWithURL(url, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("visual-validation: cannot decode \(path)\n", stderr)
    exit(2)
}

guard image.width >= 300, image.height >= 500 else {
    fputs("visual-validation: unexpected dimensions \(image.width)x\(image.height)\n", stderr)
    exit(3)
}

let width = image.width
let height = image.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("visual-validation: cannot create bitmap context\n", stderr)
    exit(4)
}

context.interpolationQuality = .none
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

let step = max(1, min(width, height) / 160)
var count = 0
var sum = 0.0
var sumSquares = 0.0
var nearBlack = 0
var nearWhite = 0
var minLuma = 1.0
var maxLuma = 0.0

for y in stride(from: 0, to: height, by: step) {
    for x in stride(from: 0, to: width, by: step) {
        let offset = y * bytesPerRow + x * 4
        let r = Double(pixels[offset]) / 255.0
        let g = Double(pixels[offset + 1]) / 255.0
        let b = Double(pixels[offset + 2]) / 255.0
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        count += 1
        sum += luma
        sumSquares += luma * luma
        minLuma = min(minLuma, luma)
        maxLuma = max(maxLuma, luma)
        if luma < 0.02 { nearBlack += 1 }
        if luma > 0.98 { nearWhite += 1 }
    }
}

let mean = sum / Double(count)
let variance = max(0, sumSquares / Double(count) - mean * mean)
let deviation = sqrt(variance)
let blackRatio = Double(nearBlack) / Double(count)
let whiteRatio = Double(nearWhite) / Double(count)
let dynamicRange = maxLuma - minLuma

print(String(
    format: "visual-validation: %@ mean=%.4f stddev=%.4f black=%.4f white=%.4f range=%.4f samples=%d",
    path, mean, deviation, blackRatio, whiteRatio, dynamicRange, count
))

let blank = mean < 0.015 || mean > 0.985
let flat = deviation < 0.025 || dynamicRange < 0.12
let dominated = (blackRatio > 0.985 || whiteRatio > 0.985) && deviation < 0.07

if blank || flat || dominated {
    fputs("visual-validation: rejected blank/flat capture \(path)\n", stderr)
    exit(10)
}
