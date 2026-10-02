import AVFoundation
import UIKit

enum IOSNextFeedbackEvent {
    case selection
    case stateChanged
    case success
    case warning
    case error
    case criticalConfirmation
    case controlCenterUnlock
    case jarvisWake
    case jarvisReady
}

@MainActor
final class IOSNextFeedbackCenter {
    static let shared = IOSNextFeedbackCenter()

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func play(_ event: IOSNextFeedbackEvent) {
        if hapticsEnabled {
            playHaptic(event)
        }
        if soundsEnabled, let profile = soundProfile(for: event) {
            playSound(profile)
        }
    }

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "iosnext.feedback.haptics.enabled") as? Bool ?? true
    }

    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: "iosnext.feedback.sounds.enabled") as? Bool ?? true
    }

    private func playHaptic(_ event: IOSNextFeedbackEvent) {
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .stateChanged, .jarvisWake:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.72)
        case .success, .controlCenterUnlock, .jarvisReady:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .criticalConfirmation:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.92)
        }
    }

    private struct SoundProfile {
        let duration: Double
        let primaryFrequency: Double
        let secondaryFrequency: Double
        let secondaryMix: Double
        let attack: Double
        let level: Double
        let silenceLead: Double
    }

    private func soundProfile(for event: IOSNextFeedbackEvent) -> SoundProfile? {
        switch event {
        case .controlCenterUnlock:
            nil
        case .success, .jarvisReady:
            SoundProfile(duration: 0.15, primaryFrequency: 523.25, secondaryFrequency: 783.99, secondaryMix: 0.24, attack: 0.006, level: 0.12, silenceLead: 0.008)
        case .warning:
            SoundProfile(duration: 0.17, primaryFrequency: 392, secondaryFrequency: 466.16, secondaryMix: 0.18, attack: 0.006, level: 0.11, silenceLead: 0.006)
        case .error:
            SoundProfile(duration: 0.18, primaryFrequency: 329.63, secondaryFrequency: 246.94, secondaryMix: 0.28, attack: 0.005, level: 0.12, silenceLead: 0.004)
        case .jarvisWake:
            SoundProfile(duration: 0.13, primaryFrequency: 587.33, secondaryFrequency: 880, secondaryMix: 0.20, attack: 0.005, level: 0.10, silenceLead: 0.004)
        case .selection, .stateChanged, .criticalConfirmation:
            nil
        }
    }

    private func playSound(_ profile: SoundProfile) {
        do {
            let data = Self.waveData(profile: profile)
            let player = try AVAudioPlayer(data: data)
            player.volume = 1
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            // Sound is supplementary feedback; failures must never block an action.
        }
    }

    private static func waveData(profile: SoundProfile) -> Data {
        let sampleRate = 48_000
        let sampleCount = max(1, Int(profile.duration * Double(sampleRate)))
        var pcm = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let activeTime = max(0, time - profile.silenceLead)
            let isSilent = time < profile.silenceLead
            let attack = min(1, activeTime / max(profile.attack, 0.001))
            let releaseStart = max(profile.silenceLead + profile.attack, profile.duration * 0.34)
            let release = time <= releaseStart ? 1 : max(0, 1 - (time - releaseStart) / max(profile.duration - releaseStart, 0.001))
            let envelope = isSilent ? 0 : attack * release * release
            let primary = sin(2 * .pi * profile.primaryFrequency * activeTime)
            let secondary = sin(2 * .pi * profile.secondaryFrequency * activeTime) * profile.secondaryMix
            let normalized = max(-1, min(1, (primary + secondary) * profile.level * envelope))
            var sample = Int16((normalized * Double(Int16.max)).rounded()).littleEndian
            Swift.withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + pcm.count))
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * 2))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
