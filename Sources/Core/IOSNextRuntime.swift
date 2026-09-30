import Observation

@MainActor
@Observable
final class IOSNextRuntime {
    static let shared = IOSNextRuntime()

    let chatModel: ChatModel
    let runnerModel: RunnerControlModel
    let liveOperationsModel: LiveOperationsModel

    private var runnerPollingTask: Task<Void, Never>?
    private var runnerPollingSources: Set<String> = []

    private init() {
        self.chatModel = ChatModel()
        self.runnerModel = RunnerControlModel()
        self.liveOperationsModel = LiveOperationsModel()
    }

    func setRunnerPollingActive(_ source: String, active: Bool) {
        if active {
            runnerPollingSources.insert(source)
        } else {
            runnerPollingSources.remove(source)
        }

        if runnerPollingSources.isEmpty {
            runnerPollingTask?.cancel()
            runnerPollingTask = nil
            runnerModel.stopCommanderLive()
        } else {
            startRunnerPollingIfNeeded()
        }
    }

    private func startRunnerPollingIfNeeded() {
        guard runnerPollingTask == nil else { return }
        runnerPollingTask = Task { [weak self] in
            guard let self else { return }
            await runnerModel.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await runnerModel.refresh()
            }
        }
    }
}
