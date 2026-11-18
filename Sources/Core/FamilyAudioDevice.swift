import AVFoundation
import Foundation

enum FamilyAudioDeviceError: Error {
    case busy, unavailable, cancelled
}

/// An input tap owns its converter. Conversion and copying complete inside
/// the tap callback; no AVAudioPCMBuffer crosses into an asynchronous task.
private final class FamilyCaptureConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let queue: FamilyPCMQueue

    init?(input: AVAudioFormat, output: AVAudioFormat, queue: FamilyPCMQueue) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        self.output = output
        self.queue = queue
    }

    func consume(_ input: AVAudioPCMBuffer) {
        guard input.frameLength > 0, input.format.sampleRate > 0 else { return }
        let capacity = ceil(Double(input.frameLength) * output.sampleRate / input.format.sampleRate) + 64
        guard capacity > 0, capacity <= 16_000,
              let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(capacity)) else { return }
        var supplied = false
        var problem: NSError?
        let status = converter.convert(to: result, error: &problem) { _, state in
            if supplied {
                state.pointee = .noDataNow
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard status != .error, problem == nil,
              let channel = result.floatChannelData?[0], result.frameLength > 0 else { return }
        queue.append(Array(UnsafeBufferPointer(start: channel, count: Int(result.frameLength))))
    }
}

/// Foreground, in-memory microphone and speaker adapter. The call controller
/// must own this object, call stop on every exit, and stop on interruptions.
/// No automatic microphone start, no recording files, no permission bypass.
@MainActor
final class FamilyAudioDevice {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var queue: FamilyPCMQueue?
    private var format: AVAudioFormat?
    private var lease: UUID?
    private var generation = UUID()
    private var preparing = false
    private var scheduled = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private let maxScheduled = 3

    var isRunning: Bool { engine != nil }

    func start(onInterrupted: @escaping @MainActor () -> Void) async throws {
        guard !preparing, !isRunning, !AppAudioCoordinator.shared.isBusy else {
            throw FamilyAudioDeviceError.busy
        }
        preparing = true
        let attempt = generation
        defer { preparing = false }
        let permitted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        try Task.checkCancellation()
        guard attempt == generation else { throw FamilyAudioDeviceError.cancelled }
        guard permitted else { throw ChatError.microphoneDenied }
        guard !AppAudioCoordinator.shared.isBusy else { throw FamilyAudioDeviceError.busy }
        let session = AVAudioSession.sharedInstance()
        lease = AppAudioCoordinator.shared.begin(.familyCall)
        let audio = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let frames = FamilyPCMQueue()
        var tapInstalled = false
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: FamilyPCM.rate, channels: 1, interleaved: false) else {
                throw FamilyAudioDeviceError.unavailable
            }
            let input = audio.inputNode
            let native = input.outputFormat(forBus: 0)
            guard native.sampleRate > 0, native.channelCount > 0,
                  let conversion = FamilyCaptureConverter(input: native, output: target, queue: frames) else {
                throw FamilyAudioDeviceError.unavailable
            }
            audio.attach(node)
            audio.connect(node, to: audio.mainMixerNode, format: target)
            input.installTap(onBus: 0, bufferSize: 1024, format: native) { buffer, _ in
                conversion.consume(buffer)
            }
            tapInstalled = true
            audio.prepare()
            try audio.start()
            node.play()
            engine = audio
            player = node
            queue = frames
            format = target
            scheduled = 0
            let center = NotificationCenter.default
            interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification,
                object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == attempt, self.isRunning else { return }
                    self.stop()
                    onInterrupted()
                }
            }
            routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification,
                object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == attempt, self.isRunning else { return }
                    self.stop()
                    onInterrupted()
                }
            }
        } catch {
            frames.close()
            if tapInstalled { audio.inputNode.removeTap(onBus: 0) }
            node.stop()
            audio.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            AppAudioCoordinator.shared.end(lease)
            lease = nil
            throw error
        }
    }

    func setMuted(_ value: Bool) { queue?.setMuted(value) }
    func takeCapture() -> Data? { queue?.take() }

    /// False signals backpressure; the caller must drop stale playout.
    @discardableResult
    func play(_ data: Data) throws -> Bool {
        guard let player, let format, scheduled < maxScheduled,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(FamilyPCM.samples)),
              let samples = buffer.floatChannelData?[0] else { return false }
        let decoded = try FamilyPCM.decode(data)
        buffer.frameLength = AVAudioFrameCount(FamilyPCM.samples)
        for i in decoded.indices { samples[i] = decoded[i] }
        scheduled += 1
        let attempt = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == attempt else { return }
                self.scheduled = max(0, self.scheduled - 1)
            }
        }
        return true
    }

    func stop() {
        generation = UUID()
        let center = NotificationCenter.default
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        if let routeObserver { center.removeObserver(routeObserver) }
        interruptionObserver = nil
        routeObserver = nil
        queue?.close()
        queue = nil
        player?.stop()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        player = nil
        format = nil
        scheduled = 0
        if lease != nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AppAudioCoordinator.shared.end(lease)
            lease = nil
        }
    }
}
