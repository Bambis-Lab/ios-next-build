import Observation

@MainActor
@Observable
final class IOSNextRuntime {
    static let shared = IOSNextRuntime()

    let chatModel: ChatModel
    let lifecycleCoordinator: AppServiceLifecycleCoordinator

    // Administrative services restore their own credentials and can be expensive.
    // Keep them uninitialized until the corresponding feature is first opened.
    @ObservationIgnored private var runnerModelStorage: RunnerControlModel?
    @ObservationIgnored private var liveOperationsModelStorage: LiveOperationsModel?
    @ObservationIgnored private var factoryWorkspaceStorage: FactoryWorkspaceCoordinator?

    var runnerModel: RunnerControlModel {
        if let runnerModelStorage { return runnerModelStorage }
        let model = RunnerControlModel()
        runnerModelStorage = model
        return model
    }

    var liveOperationsModel: LiveOperationsModel {
        if let liveOperationsModelStorage { return liveOperationsModelStorage }
        let model = LiveOperationsModel()
        liveOperationsModelStorage = model
        return model
    }

    var factoryWorkspace: FactoryWorkspaceCoordinator {
        if let factoryWorkspaceStorage { return factoryWorkspaceStorage }
        let coordinator = FactoryWorkspaceCoordinator()
        factoryWorkspaceStorage = coordinator
        return coordinator
    }

    private var runnerPollingTask: Task<Void, Never>?
    private var runnerPollingSources: Set<String> = []

    private init() {
        let trace = IOSNextPerformance.begin("Runtime.Initialize")
        defer { IOSNextPerformance.end("Runtime.Initialize", trace) }
        self.chatModel = ChatModel()
        self.lifecycleCoordinator = AppServiceLifecycleCoordinator(chat: self.chatModel)
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
