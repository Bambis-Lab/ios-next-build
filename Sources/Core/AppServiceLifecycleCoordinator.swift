import Foundation

/// App-scoped lifecycle arbitration. Each service retains its own transport,
/// identity and authentication; this class never shares credentials across
/// Chat, Home Assistant, Owner, Runner or Factory.
@MainActor
final class AppServiceLifecycleCoordinator {
    private let chat: ChatModel
    private var appForeground = true
    private var homeAssistantConnected = false
    private var visibleChatCount = 0
    private var chatStartup: Task<Void, Never>?
    private var chatStartupToken: UUID?
    private var lifecycleGeneration: UInt64 = 0

    init(chat: ChatModel) { self.chat = chat }

    /// Synchronously invalidate the old identity before HA OAuth/account
    /// changes; a still-open ChatView must never display another user's data.
    func invalidateForAccountTransition() {
        lifecycleGeneration &+= 1
        homeAssistantConnected = false
        chatStartup?.cancel()
        chatStartup = nil
        chatStartupToken = nil
        chat.forgetConfiguration()
    }

    func homeAssistantConnectionChanged(_ connected: Bool, appModel: AppModel) async {
        lifecycleGeneration &+= 1
        homeAssistantConnected = connected
        await reconcileChat(appModel: appModel)
    }

    func chatViewAppeared(appModel: AppModel) async {
        lifecycleGeneration &+= 1
        visibleChatCount += 1
        await reconcileChat(appModel: appModel)
    }

    func chatViewDisappeared() {
        lifecycleGeneration &+= 1
        visibleChatCount = max(0, visibleChatCount - 1)
        ChatMediaThumbnailCache.shared.clear()
        if !homeAssistantConnected && visibleChatCount == 0 {
            chat.stop()
        }
    }

    func applicationPhaseChanged(isActive: Bool, appModel: AppModel) {
        lifecycleGeneration &+= 1
        appForeground = isActive
        if !isActive {
            chat.stop()
        } else {
            Task { [weak self] in await self?.reconcileChat(appModel: appModel) }
        }
    }

    private func reconcileChat(appModel: AppModel) async {
        guard appForeground, homeAssistantConnected || visibleChatCount > 0 else {
            chat.stop()
            return
        }
        // ChatView and AppRoot can ask for the same connection concurrently.
        // Register exactly one startup task and await it without rebuilding
        // a second authenticated relay session.
        if let existingChatStartup = chatStartup {
            let observedToken = chatStartupToken
            let generationAtWait = lifecycleGeneration
            await existingChatStartup.value
            if chatStartupToken == observedToken {
                chatStartup = nil
                chatStartupToken = nil
            }
            guard appForeground, homeAssistantConnected || visibleChatCount > 0 else {
                chat.stop()
                return
            }
            if case .online = chat.state { return }
            // Retry only if the desired lifecycle changed while this flight was
            // in progress. A genuine relay error must not create an endless retry loop.
            if lifecycleGeneration != generationAtWait, chatStartup == nil {
                await reconcileChat(appModel: appModel)
            }
            return
        }
        let token = UUID()
        chatStartupToken = token
        let startup = Task { [chat] in await chat.start(using: appModel) }
        chatStartup = startup
        await startup.value
        if chatStartupToken == token {
            chatStartup = nil
            chatStartupToken = nil
        }
        if !appForeground || (!homeAssistantConnected && visibleChatCount == 0) {
            chat.stop()
        }
    }
}
