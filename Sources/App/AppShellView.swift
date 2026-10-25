import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case rooms
    case chat
    case media
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Zuhause"
        case .rooms: "Räume"
        case .chat: "Chat"
        case .media: "Medien"
        case .system: "System"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "square.grid.2x2.fill"
        case .chat: "message.fill"
        case .media: "play.tv.fill"
        case .system: "ellipsis.circle.fill"
        }
    }
}

struct AppShellView: View {
    let appModel: AppModel
    let chatModel: ChatModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab?
    @State private var navigationPaths: [AppTab: NavigationPath]

    init(appModel: AppModel, chatModel: ChatModel, initialTab: AppTab = .home) {
        self.appModel = appModel
        self.chatModel = chatModel
        let requested = UserDefaults.standard.string(forKey: "iosnext.requestedAppTab")
        _selectedTab = State(initialValue: requested.flatMap(AppTab.init(rawValue:)) ?? initialTab)
        if requested != nil {
            UserDefaults.standard.removeObject(forKey: "iosnext.requestedAppTab")
        }
        _navigationPaths = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: AppTab.allCases.map { ($0, NavigationPath()) }
            )
        )
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                tabletShell
            } else {
                phoneShell
            }
        }
        .tint(.accentColor)
        .overlay(alignment: .bottom) {
            if JarvisEngine.shared.state.isListening {
                JarvisListeningPill(engine: JarvisEngine.shared)
                    .padding(.horizontal, 16)
                    .padding(.bottom, horizontalSizeClass == .regular ? 22 : 62)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: JarvisEngine.shared.state.isListening)
        .alert("Aktion fehlgeschlagen", isPresented: errorBinding) {
            Button("OK") { appModel.dismissActionError() }
        } message: {
            Text(appModel.lastActionError ?? "Unbekannter Fehler")
        }
        .onAppear { consumeNavigationRequest() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeNavigationRequest() }
        }
    }

    private var phoneShell: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: navigationPathBinding(for: tab)) {
                    content(for: tab)
                }
                .tabItem { Label(tab.title, systemImage: tab.icon) }
                .tag(tab)
                .accessibilityIdentifier("app-tab-\(tab.rawValue)")
            }
        }
    }

    private var tabletShell: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: selectedTabOptionalBinding) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
                    .accessibilityIdentifier("app-tab-\(tab.rawValue)")
            }
            .navigationTitle("iOS Next")
        } detail: {
            let tab = selectedTab ?? .home
            NavigationStack(path: navigationPathBinding(for: tab)) {
                content(for: tab)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            if !appModel.familyBrokerConfigured || appModel.registeredFamilyProfile != nil {
                HomeView(appModel: appModel)
            } else {
                VStack(spacing: 8) {
                    Label("Familienprofil noch nicht bestätigt", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    RoomsView(appModel: appModel)
                }
            }
        case .rooms: RoomsView(appModel: appModel)
        case .chat: ChatInboxView(appModel: appModel, chatModel: chatModel)
        case .media: MediaView(appModel: appModel)
        case .system: SystemView(appModel: appModel)
        }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab ?? .home },
            set: { select($0) }
        )
    }

    private var selectedTabOptionalBinding: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { value in
                guard let value else {
                    selectedTab = nil
                    return
                }
                select(value)
            }
        )
    }

    private func navigationPathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { navigationPaths[tab] ?? NavigationPath() },
            set: { navigationPaths[tab] = $0 }
        )
    }

    private func consumeNavigationRequest() {
        guard let raw = UserDefaults.standard.string(forKey: "iosnext.requestedAppTab"),
              let tab = AppTab(rawValue: raw) else { return }
        UserDefaults.standard.removeObject(forKey: "iosnext.requestedAppTab")
        select(tab)
    }

    private func select(_ tab: AppTab) {
        if selectedTab == tab {
            navigationPaths[tab] = NavigationPath()
            return
        }
        IOSNextFeedbackCenter.shared.play(.selection)
        selectedTab = tab
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appModel.lastActionError != nil },
            set: { if !$0 { appModel.dismissActionError() } }
        )
    }
}
