import AVFoundation
import Foundation
import Observation
import Speech

enum JarvisState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listeningForWakeWord
    case wakeDetected
    case listening
    case transcribing
    case thinking
    case speaking
    case unavailable(String)
    case error(String)

    var title: String {
        switch self {
        case .idle: "Bereit"
        case .requestingPermission: "Berechtigung wird geprüft"
        case .listeningForWakeWord: "Wartet auf „Jarvis“"
        case .wakeDetected: "Jarvis erkannt"
        case .listening: "Jarvis hört zu"
        case .transcribing: "Wird verstanden"
        case .thinking: "Wird verarbeitet"
        case .speaking: "Jarvis spricht"
        case let .unavailable(message): message
        case let .error(message): message
        }
    }

    var isListening: Bool {
        switch self {
        case .listeningForWakeWord, .wakeDetected, .listening, .transcribing:
            true
        default:
            false
        }
    }
}

enum JarvisSensitivity: String, CaseIterable, Identifiable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Niedrig"
        case .normal: "Normal"
        case .high: "Hoch"
        }
    }

    var minimumConfidence: Float {
        switch self {
        case .low: 0.82
        case .normal: 0.68
        case .high: 0.52
        }
    }
}

enum JarvisIntentDomain: String, Equatable, Sendable {
    case homeAssistant
    case runner
    case commander
    case media
    case appNavigation
    case research
    case conversational
}

struct JarvisIntent: Equatable, Sendable {
    let domain: JarvisIntentDomain
    let action: String
    let transcript: String
}

struct JarvisIntentRouter {
    static func route(_ transcript: String) -> JarvisIntent {
        let value = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()

        if value.contains("licht") || value.contains("lampe") || value.contains("home assistant") {
            return JarvisIntent(domain: .homeAssistant, action: "smart-home", transcript: transcript)
        }
        if value.contains("runner") {
            return JarvisIntent(domain: .runner, action: "status", transcript: transcript)
        }
        if value.contains("commander") || value.contains("code commander") {
            return JarvisIntent(domain: .commander, action: "status", transcript: transcript)
        }
        if value.contains("was läuft") || value.contains("medien") || value.contains("fernseher") || value.contains("tv") {
            return JarvisIntent(domain: .media, action: "media", transcript: transcript)
        }
        if value.contains("control center") || value.contains("öffne system") || value.contains("offne system") {
            return JarvisIntent(domain: .appNavigation, action: "control-center", transcript: transcript)
        }
        if value.contains("analys") || value.contains("forsche") || value.contains("fehler") {
            return JarvisIntent(domain: .research, action: "research", transcript: transcript)
        }
        return JarvisIntent(domain: .conversational, action: "chat", transcript: transcript)
    }
}

@MainActor
@Observable
final class JarvisEngine {
    static let shared = JarvisEngine()

    private(set) var state: JarvisState = .idle
    var sensitivity: JarvisSensitivity = .normal
    private(set) var lastWakeAt: Date?
    private(set) var lastTranscript: String?
    private(set) var latestIntent: JarvisIntent?
    private(set) var wakeEvidenceCount = 0
    private(set) var audioDropCount = 0
    private(set) var onDeviceRecognitionAvailable = false

    let wakeWord = "Jarvis"

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastEvidenceAt: Date?
    private var hasDetectedWake = false
    private var inputTapInstalled = false

    func startWakeListening() async {
        guard !state.isListening else { return }
        state = .requestingPermission

        guard await requestMicrophonePermission() else {
            state = .unavailable("Mikrofon nicht erlaubt")
            return
        }
        guard await requestSpeechPermission() else {
            state = .unavailable("Spracherkennung nicht erlaubt")
            return
        }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            onDeviceRecognitionAvailable = false
            state = .unavailable("Lokale Spracherkennung nicht verfügbar")
            return
        }

        onDeviceRecognitionAvailable = true
        self.recognizer = recognizer

        do {
            try startRecognitionSession(using: recognizer)
            state = .listeningForWakeWord
        } catch {
            stopAudioSession()
            state = .error("Jarvis Audio: \(error.localizedDescription)")
        }
    }

    func stopWakeListening() {
        stopAudioSession()
        state = .idle
        wakeEvidenceCount = 0
        lastEvidenceAt = nil
        hasDetectedWake = false
    }

    func clearLastIntent() {
        latestIntent = nil
        lastTranscript = nil
    }

    private func startRecognitionSession(using recognizer: SFSpeechRecognizer) throws {
        stopAudioSession()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        inputTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.handleRecognitionResult(result)
                }
                if let error {
                    self?.handleRecognitionError(error)
                }
            }
        }
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription
        let text = transcription.formattedString

        if !hasDetectedWake {
            let matchingSegment = transcription.segments.last { segment in
                normalized(segment.substring).contains("jarvis")
            }
            guard let matchingSegment, matchingSegment.confidence >= sensitivity.minimumConfidence else {
                if result.isFinal {
                    wakeEvidenceCount = 0
                    lastEvidenceAt = nil
                }
                return
            }

            let now = Date()
            if let lastEvidenceAt, now.timeIntervalSince(lastEvidenceAt) <= 1.2 {
                wakeEvidenceCount += 1
            } else {
                wakeEvidenceCount = 1
            }
            self.lastEvidenceAt = now

            guard wakeEvidenceCount >= 2 || (result.isFinal && matchingSegment.confidence >= 0.88) else { return }
            hasDetectedWake = true
            lastWakeAt = now
            state = .wakeDetected
            IOSNextFeedbackCenter.shared.play(.jarvisWake)

            let command = commandAfterWakeWord(in: text)
            if !command.isEmpty {
                acceptCommand(command, isFinal: result.isFinal)
            } else {
                state = .listening
            }
            return
        }

        let command = commandAfterWakeWord(in: text)
        guard !command.isEmpty else { return }
        acceptCommand(command, isFinal: result.isFinal)
    }

    private func acceptCommand(_ command: String, isFinal: Bool) {
        lastTranscript = command
        state = isFinal ? .thinking : .transcribing
        guard isFinal else { return }
        latestIntent = JarvisIntentRouter.route(command)
        stopAudioSession()
        state = .idle
        hasDetectedWake = false
        wakeEvidenceCount = 0
        lastEvidenceAt = nil
    }

    private func handleRecognitionError(_ error: Error) {
        guard state.isListening else { return }
        stopAudioSession()
        state = .error("Lokale Spracherkennung: \(error.localizedDescription)")
    }

    private func commandAfterWakeWord(in text: String) -> String {
        let lower = text.lowercased()
        guard let range = lower.range(of: wakeWord.lowercased()) else {
            return hasDetectedWake ? text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private func stopAudioSession() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
