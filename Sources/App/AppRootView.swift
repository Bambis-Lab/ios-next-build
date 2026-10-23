import SwiftUI

struct AppRootView: View {
    let appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime = IOSNextRuntime.shared
    @State private var initialService: PreConnectionService?
    @State private var didCompleteStartupReveal = false

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--fam-acceptance-mika") {
                FamilyAcceptanceView(profile: .mika)
            } else if ProcessInfo.processInfo.arguments.contains("--fam-acceptance-juli") {
                FamilyAcceptanceView(profile: .juli)
            } else if ProcessInfo.processInfo.arguments.contains("--nico-room-layout-acceptance") {
                NicoRoomVisualAcceptanceView()
            } else if isMotionAcceptanceMode {
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
            runtime.lifecycleCoordinator.applicationPhaseChanged(isActive: phase == .active, appModel: appModel)
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
            guard !isTestHarnessMode else { return }
            await runtime.lifecycleCoordinator.homeAssistantConnectionChanged(
                appModel.isConnected, appModel: appModel
            )
        }
        .task(id: appModel.registeredFamilyProfile) {
            guard !isTestHarnessMode, appModel.registeredFamilyProfile != nil else { return }
            await runtime.lifecycleCoordinator.homeAssistantConnectionChanged(
                appModel.isConnected, appModel: appModel
            )
        }
        .sheet(isPresented: Bindable(appModel).isPresentingConnection) {
            ConnectionSetupView(appModel: appModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $initialService) { service in
            switch service {
            case .chat:
                StandaloneChatView(appModel: appModel, chatModel: runtime.chatModel)
            case .controlCenter:
                AdminAreaView(appModel: appModel)
            case .runner:
                NavigationStack {
                    RunnerDashboardView(model: runtime.runnerModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Schließen") { initialService = nil }
                            }
                        }
                }
            case .factory:
                NavigationStack {
                    FactoryStandaloneView(appModel: appModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Schließen") { initialService = nil }
                            }
                        }
                }
            }
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
            ConnectionLandingView(appModel: appModel) { selected in
                initialService = selected
            }
            .transition(.opacity)
        }
    }

    private var connectedShell: some View {
        AppShellView(appModel: appModel, chatModel: runtime.chatModel)
            .transition(.opacity)
    }

    private var isTestHarnessMode: Bool {
        isLiveCardTestMode || isAnimationAcceptanceMode || isProductAcceptanceMode
            || isMotionAcceptanceMode || ProcessInfo.processInfo.arguments.contains("--preconnect-ui-acceptance")
            || ProcessInfo.processInfo.arguments.contains("--factory-workspace-acceptance")
            || ProcessInfo.processInfo.arguments.contains("--fam-acceptance-mika")
            || ProcessInfo.processInfo.arguments.contains("--fam-acceptance-juli")
            || ProcessInfo.processInfo.arguments.contains("--nico-room-layout-acceptance")
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

private enum PreConnectionService: String, Identifiable {
    case chat
    case controlCenter
    case runner
    case factory

    var id: String { rawValue }
}

private struct ConnectionLandingView: View {
    let appModel: AppModel
    let openService: (PreConnectionService) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.indigo)
                        .frame(width: 58, height: 58)
                        .background(Color.indigo.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iOS Next").font(.largeTitle.bold())
                        Text("Deine Dienste. Unabhängig verbunden.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 30)

                Text("Chat Relay und Factory sind bereits vor der Home-Assistant-Verbindung erreichbar. Owner, Runner und Live-Vorgänge findest du im Factory Workspace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if case let .failed(message) = appModel.connectionState {
                    IOSNextErrorBanner(message: message)
                }

                VStack(alignment: .leading, spacing: 13) {
                    Text("Home Assistant")
                        .font(.title3.bold())
                    Text("Zuhause, Räume, Szenen und Medien verbinden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appModel.isPresentingConnection = true
                    } label: {
                        Label("Home Assistant verbinden", systemImage: "link")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("preconnect-ha")
                }
                .padding(18)
                .ios27ContentSurface(radius: 24)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Weitere Dienste").font(.title3.bold())
                    Text("Ohne Home Assistant einrichten, ansehen oder verwalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !appModel.familyBrokerConfigured {
                        service("Chat Relay", detail: "Verschlüsselter Chat · eigener Zugang",
                                symbol: "message.badge.shield.fill", route: .chat)
                    }
                    // Legacy screenshots exercise these historical routes without network access.
                    // Production exposes a single admin entry; no Owner or Runner entitlement is merged.
                    if ProcessInfo.processInfo.arguments.contains("--preconnect-ui-acceptance") {
                        service("Control Center", detail: "Owner-Zugang · sichere Einrichtung",
                                symbol: "slider.horizontal.3", route: .controlCenter)
                        service("Runner", detail: "Runner-Dienst · Ressourcen und Steuerung",
                                symbol: "server.rack", route: .runner)
                    }
                    if !appModel.familyBrokerConfigured {
                        service("Factory", detail: "Owner · Runner · Live · MCP und Governance",
                                symbol: "network", route: .factory)
                    }
                }

                Label("Kein Login für die Navigation erforderlich. Live-Aktionen benötigen ihre jeweiligen Berechtigungen.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 670)
            .frame(maxWidth: .infinity)
        }
        .background(IOSNextBackground())
        .accessibilityIdentifier("preconnect-service-hub")
    }

    private func service(_ name: String, detail: String, symbol: String,
                         route: PreConnectionService) -> some View {
        Button {
            openService(route)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(Color.indigo.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(13)
            .ios27ContentSurface(radius: 19)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preconnect-\(route.rawValue)")
        .accessibilityLabel(route == .chat ? "Verschlüsselten Chat öffnen" : name)
        .accessibilityHint("Dienst ohne Home-Assistant-Verbindung öffnen")
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
