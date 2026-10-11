import Foundation

enum AppAudioActivity: Hashable {
    case chatVoicePlayback
    case voiceRecording
}

/// Coordinates ownership, not audio samples. AVAudioPlayer/AVAudioEngine remain
/// their existing specialized implementations. A lease is released on stop,
/// finish, error or view lifecycle cleanup; the coordinator owns no audio data.
@MainActor
final class AppAudioCoordinator {
    static let shared = AppAudioCoordinator()

    private var activities: [UUID: AppAudioActivity] = [:]
    private let busyChanged: @MainActor (Bool) -> Void
    private var lastPublishedBusy = false

    init() {
        self.busyChanged = { busy in JarvisEngine.shared.setExternalAudioBusy(busy) }
    }

    init(busyChanged: @escaping @MainActor (Bool) -> Void) {
        self.busyChanged = busyChanged
    }

    var isBusy: Bool { !activities.isEmpty }

    @discardableResult
    func begin(_ activity: AppAudioActivity) -> UUID {
        let wasBusy = isBusy
        let id = UUID()
        activities[id] = activity
        publishIfNeeded(previouslyBusy: wasBusy)
        return id
    }

    func end(_ id: UUID?) {
        guard let id else { return }
        let wasBusy = isBusy
        guard activities.removeValue(forKey: id) != nil else { return }
        publishIfNeeded(previouslyBusy: wasBusy)
    }

    func endAll(_ activity: AppAudioActivity) {
        let wasBusy = isBusy
        activities = activities.filter { $0.value != activity }
        publishIfNeeded(previouslyBusy: wasBusy)
    }

    private func publishIfNeeded(previouslyBusy: Bool) {
        let nowBusy = isBusy
        guard previouslyBusy != nowBusy, lastPublishedBusy != nowBusy else { return }
        busyChanged(nowBusy)
        lastPublishedBusy = nowBusy
    }
}
