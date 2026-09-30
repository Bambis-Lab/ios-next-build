import SwiftUI

struct AppRootView: View {
    let appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime = IOSNextRuntime.shared
    @State private var isPresentingStandaloneChat = false
    @State private var didCompleteStartupReveal = false

    var body: some View {
        Group {
            if isMotionAcceptanceMode {
                MotionAcceptanceView()
            } else if isProductAcceptanceMode {
                ProductAcceptanceRootView()
            } else if isAnimationAcceptanceMode {
                AnimationAcceptanceView()
            } else if isLiveCardTestMode {
                LiveHACardTestModeView()
            } else {
                productionRoot
            }
        }
        .animation(IOSNextMotion.navigation, value: appModel.isConnected)
        .onChange(of: scenePhase) { _, phase in
            appModel.setApplicationActive(phase == .active)
            if phase != .active {
                JarvisEngine.shared.stopWakeListening()
            }
        }
        .task {
            if !isTestHarnessMode {
                await appModel.restoreConnection()
            }
        }
        .task {
            if !isTestHarnessMode {
                await appModel.monitorNetworkChanges()
            }
        }
        .task(id: appModel.isConnected) {
            if !isTestHarnessMode, appModel.isConnected {
                await runtime.chatModel.start(using: appModel)
            } else if !appModel.isConnected {
                runtime.chatModel.stop()
            }
        }
        .sheet(isPresented: Bindable(appModel).isPresentingConnection) {
            ConnectionSetupView(appModel: appModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isPresentingStandaloneChat) {
            StandaloneChatView(appModel: appModel, chatModel: runtime.chatModel)
        }
    }

    @ViewBuilder
    private var productionRoot: some View {
        switch appModel.connectionState {
        case .connected:
            if didCompleteStartupReveal {
                connectedShell
            } else {
                IOSNextStartupRevealHost(onFinished: {
                    didCompleteStartupReveal = true
                }) {
                    connectedShell
                }
            }
        case .connecting where !appModel.entities.isEmpty, .reconnecting where !appModel.entities.isEmpty:
            AppShellView(appModel: appModel, chatModel: runtime.chatModel)
                .overlay(alignment: .top) {
                    ReconnectStatusOverlay(state: appModel.connectionState)
                }
        default:
            ConnectionLandingView(appModel: appModel) {
                isPresentingStandaloneChat = true
            }
            .transition(.opacity)
        }
    }

    private var connectedShell: some View {
        AppShellView(appModel: appModel, chatModel: runtime.chatModel)
            .transition(.opacity)
    }

    private var isTestHarnessMode: Bool {
        isLiveCardTestMode || isAnimationAcceptanceMode || isProductAcceptanceMode || isMotionAcceptanceMode
    }

    private var isMotionAcceptanceMode: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--motion-acceptance-sequence=") }
    }

    private var isLiveCardTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--live-card-test-mode")
    }

    private var isAnimationAcceptanceMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--animation-acceptance-mode")
    }

    private var isProductAcceptanceMode: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--product-ui-test-screen=") }
    }
}

private struct ConnectionLandingView: View {
    let appModel: AppModel
    let openChat: () -> Void

    var body: some View {
        ZStack {
            IOSNextBackground()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.tint.opacity(0.14))
                    Image(systemName: "house.lodge.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .frame(width: 108, height: 108)
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("iOS Next")
                        .font(.largeTitle.bold())
                    Text("Dein Zuhause. Nativ auf iPhone und iPad.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if case let .failed(message) = appModel.connectionState {
                    IOSNextErrorBanner(message: message)
                        .frame(maxWidth: 520)
                }

                Spacer()
                Button("Home Assistant verbinden", systemImage: "link") {
                    appModel.isPresentingConnection = true
                }
                .font(.headline)
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .accessibilityHint("Öffnet die sichere Einrichtung der Home-Assistant-Verbindung.")
                Button("Verschlüsselten Chat öffnen", systemImage: "message.badge.shield.fill", action: openChat)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StandaloneChatView: View {
    let appModel: AppModel
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatView(appModel: appModel, chatModel: chatModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
    }
}
