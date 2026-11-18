import Foundation

/// Experimental audio v1 media format: mono signed little-endian PCM16,
/// 16 kHz, 320 samples (20 ms) per frame. No files or audio metadata.
enum FamilyPCM {
    static let rate: Double = 16_000
    static let samples = 320
    static let bytes = 640
    static let silence = Data(repeating: 0, count: bytes)

    static func encode(_ input: [Float]) throws -> Data {
        guard input.count == samples else { throw FamilyAudioError.invalidFrame }
        var data = Data(capacity: bytes)
        for value in input {
            let clamped = value.isFinite ? max(-1, min(1, value)) : 0
            let sample = UInt16(bitPattern: Int16(clamped * Float(Int16.max)))
            data.append(UInt8(truncatingIfNeeded: sample))
            data.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return data
    }

    static func decode(_ data: Data) throws -> [Float] {
        guard data.count == bytes else { throw FamilyAudioError.invalidFrame }
        let raw = Array(data)
        return stride(from: 0, to: bytes, by: 2).map { i in
            let sample = Int16(bitPattern: UInt16(raw[i]) | (UInt16(raw[i + 1]) << 8))
            return max(-1, Float(sample) / Float(Int16.max))
        }
    }
}

/// A bounded producer/consumer crossing the audio tap and main actor.
/// Stale frames are dropped rather than accumulating latency.
final class FamilyPCMQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Float] = []
    private var frames: [Data] = []
    private var muted = false
    private var closed = false
    private let maxFrames = 10

    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, !muted, samples.count <= 16_000 else { return }
        pending.append(contentsOf: samples)
        while pending.count >= FamilyPCM.samples {
            let block = Array(pending.prefix(FamilyPCM.samples))
            pending.removeFirst(FamilyPCM.samples)
            if let data = try? FamilyPCM.encode(block) { frames.append(data) }
            if frames.count > maxFrames { frames.removeFirst(frames.count - maxFrames) }
        }
    }

    func take() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !frames.isEmpty, !closed, !muted else { return nil }
        return frames.removeFirst()
    }

    func setMuted(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        muted = value
        // Never send capture buffered before a mute transition.
        frames.removeAll()
        pending.removeAll()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
        frames.removeAll()
        pending.removeAll()
    }
}

/// Receives authenticated frames only. Playout is driven by the consumer's
/// 20 ms clock; at most ten frames and two consecutive concealment frames.
/// A long gap re-buffers instead of synthesizing an unbounded silence queue.
struct FamilyPCMPlayout {
    private var frames: [UInt64: Data] = [:]
    private var expected: UInt64?
    private var highest: UInt64?
    private var started = false
    private var misses = 0
    private let prefill = 3
    private let capacity = 10

    var bufferedCount: Int { frames.count }

    mutating func insert(sequence: UInt64, frame: Data) throws {
        guard sequence <= UInt64(Int64.max), frame.count == FamilyPCM.bytes else {
            throw FamilyAudioError.invalidFrame
        }
        if let highest, sequence <= highest { throw FamilyAudioError.replay }
        highest = sequence
        if let expected, sequence < expected { return }
        frames[sequence] = frame
        if frames.count > capacity, let oldest = frames.keys.min() {
            frames.removeValue(forKey: oldest)
            expected = frames.keys.min()
            started = false
            misses = 0
        }
    }

    mutating func next() -> Data? {
        if !started {
            guard frames.count >= prefill, let first = frames.keys.min() else { return nil }
            expected = first
            started = true
            misses = 0
        }
        guard let sequence = expected else { return nil }
        if let frame = frames.removeValue(forKey: sequence) {
            expected = sequence + 1
            misses = 0
            return frame
        }
        if misses < 2 {
            misses += 1
            expected = sequence + 1
            return FamilyPCM.silence
        }
        expected = nil
        started = false
        misses = 0
        return nil
    }
}
