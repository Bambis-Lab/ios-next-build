import AVFoundation
import Foundation
import Observation

private final class PCMAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()
    private(set) var sampleRate: Double = 48_000

    func reset(sampleRate: Double) {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        self.sampleRate = sampleRate
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let channel = channels[0]
        var encoded = Data(capacity: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
        for index in 0..<Int(buffer.frameLength) {
            var sample = Int16(max(-1, min(1, channel[index])) * Float(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &sample) { encoded.append(contentsOf: $0) }
        }
        lock.lock()
        samples.append(encoded)
        lock.unlock()
    }

    func wavData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let byteRate = UInt32(sampleRate) * 2
        var result = Data()
        result.appendASCII("RIFF")
        result.appendLE(UInt32(36 + samples.count))
        result.appendASCII("WAVEfmt ")
        result.appendLE(UInt32(16))
        result.appendLE(UInt16(1))
        result.appendLE(UInt16(1))
        result.appendLE(UInt32(sampleRate))
        result.appendLE(byteRate)
        result.appendLE(UInt16(2))
        result.appendLE(UInt16(16))
        result.appendASCII("data")
        result.appendLE(UInt32(samples.count))
        result.append(samples)
        return result
    }
}

@MainActor
@Observable
final class InMemoryVoiceRecorder {
    var isRecording = false
    var isPreparing = false
    var duration: TimeInterval = 0

    private var engine: AVAudioEngine?
    private let accumulator = PCMAccumulator()
    private var timer: Timer?
    private var startedAt: Date?

    func start() async throws {
        guard !isRecording, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        guard await microphonePermission() else { throw ChatError.microphoneDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        accumulator.reset(sampleRate: format.sampleRate)
        try input.installAudioTap(onBus: 0, bufferSize: 1_024, format: format) { [accumulator] buffer, _ in
            accumulator.append(AVAudioPCMBuffer(copying: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
        } catch {
            engine.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        startedAt = .now
        duration = 0
        isRecording = true
        timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.duration = Date.now.timeIntervalSince(startedAt)
            }
        }
    }

    func stop() -> Data? {
        guard isRecording else { return nil }
        timer?.invalidate()
        timer = nil
        engine?.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        startedAt = nil
        let data = accumulator.wavData()
        duration = 0
        return data.count > 44 ? data : nil
    }

    private func microphonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii) ?? Data())
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
