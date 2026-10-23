import Foundation
import SwiftUI

enum ProductAcceptanceScreen: String, CaseIterable {
    case home
    case rooms
    case chat
    case media
    case system
    case light
    case mediaDetail = "media-detail"
    case owner
    case runner
    case projects

    var initialTab: AppTab? {
        switch self {
        case .home: .home
        case .rooms: .rooms
        case .chat: .chat
        case .media: .media
        case .system: .system
        case .light, .mediaDetail, .owner, .runner, .projects: nil
        }
    }
}

private struct ProductAcceptanceOptions {
    let initialDarkMode: Bool
    let switcherEnabled: Bool

    init(arguments: [String]) {
        initialDarkMode = arguments.contains("--product-ui-test-dark")
        switcherEnabled = arguments.contains("--product-ui-test-switcher")
    }
}

struct ProductAcceptanceRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let options: ProductAcceptanceOptions
    @State private var screen: ProductAcceptanceScreen
    @State private var isDarkMode: Bool
    @State private var appModel: AppModel
    @State private var chatModel = ChatModel.preview

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialScreen = Self.screen(from: arguments)
        let options = ProductAcceptanceOptions(arguments: arguments)
        self.options = options
        let fixtureModel = AppModel.preview
        #if DEBUG
        if arguments.contains("--product-ui-test-unverified") {
            fixtureModel.seedUnverifiedFamilyPreview()
        }
        #endif
        _appModel = State(initialValue: fixtureModel)
        _screen = State(initialValue: initialScreen)
        _isDarkMode = State(initialValue: options.initialDarkMode)
    }

    var body: some View {
        Group {
            if let tab = screen.initialTab {
                AppShellView(appModel: appModel, chatModel: chatModel, initialTab: tab)
                    .id("shell-\(screen.rawValue)")
            } else {
                standaloneScreen
                    .id("standalone-\(screen.rawValue)")
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .overlay(alignment: .topLeading) {
            if options.switcherEnabled {
                acceptanceSwitcher
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("product-acceptance-\(screen.rawValue)")
        .accessibilityValue(accessibilityStateDescription)
        .background(alignment: .topLeading) {
            // The ready probe is a noninteractive diagnostic marker, not a
            // full-screen accessibility surface over sliders, rows or tabs.
            VisualAcceptanceReadyProbe(
                markerBaseName: "iosnext-product-screen-ready-\(screen.rawValue)-\(acceptanceAppearanceName)",
                accessibilityIdentifier: "visual-ready-product-\(screen.rawValue)-\(acceptanceAppearanceName)",
                payload: "screen=\(screen.rawValue);appearance=\(acceptanceAppearanceName)"
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
    }

    private var acceptanceAppearanceName: String {
        isDarkMode ? "dark" : "light"
    }

    private var accessibilityStateDescription: String {
        "darkMode=\(isDarkMode);reduceMotion=\(reduceMotion);reduceTransparency=\(reduceTransparency);increasedContrast=\(colorSchemeContrast == .increased);dynamicTypeAccessibility=\(dynamicTypeSize.isAccessibilitySize)"
    }

    private var acceptanceSwitcher: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(ProductAcceptanceScreen.allCases.prefix(5)), id: \.rawValue) { target in
                    acceptanceButton(for: target)
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(ProductAcceptanceScreen.allCases.dropFirst(5)), id: \.rawValue) { target in
                    acceptanceButton(for: target)
                }
                Button {
                    isDarkMode.toggle()
                } label: {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Acceptance appearance toggle")
                .accessibilityIdentifier("acceptance-toggle-appearance")
            }
        }
        .zIndex(10_000)
    }

    private func acceptanceButton(for target: ProductAcceptanceScreen) -> some View {
        Button {
            screen = target
        } label: {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Acceptance screen \(target.rawValue)")
        .accessibilityIdentifier("acceptance-switch-\(target.rawValue)")
    }

    @ViewBuilder
    private var standaloneScreen: some View {
        switch screen {
        case .light:
            NavigationStack {
                EntityDetailView(entityID: "light.hintergrund_fernseher", appModel: appModel)
            }
        case .mediaDetail:
            NavigationStack {
                EntityDetailView(entityID: "media_player.schlafzimmer", appModel: appModel)
            }
        case .owner:
            AdminAreaView(appModel: appModel)
        case .runner:
#if DEBUG
            NavigationStack { G99RunnerAcceptanceFixture() }
#else
            EmptyView()
#endif
        case .projects:
#if DEBUG
            NavigationStack { G99ProjectsAcceptanceFixture() }
#else
            EmptyView()
#endif
        case .home, .rooms, .chat, .media, .system:
            EmptyView()
        }
    }

    static func screen(from arguments: [String]) -> ProductAcceptanceScreen {
        guard let argument = arguments.first(where: { $0.hasPrefix("--product-ui-test-screen=") }),
              let rawValue = argument.split(separator: "=").last.map(String.init),
              let screen = ProductAcceptanceScreen(rawValue: rawValue)
        else { return .home }
        return screen
    }
}


#if DEBUG
// Deterministic, local-only screenshot fixtures. No real Owner/Runner tokens,
// no network requests and no modification to the live Factory.
private struct G99RunnerAcceptanceFixture: View {
    @State private var model: RunnerControlModel

    init() {
        let fixture = RunnerControlModel(skipStoredConfiguration: true)
        fixture.state = .ready(
            RunnerStatus(
                vmOnline: true, serviceActive: true,
                registeredRunners: 4, idleRunners: 3, busyRunners: 1,
                cpuPercent: 31, memoryPercent: 62, diskPercent: 44,
                lastHealthCheck: Date(timeIntervalSince1970: 1_760_000_000),
                uptimeSeconds: 324_000, maintenanceMode: false,
                bridge: RunnerSubsystemStatus(
                    id: "bridge", name: "Runner Bridge", active: true,
                    version: "fixture", detail: "Lokale Testdaten", lastSeen: nil
                ),
                orchestrator: nil, commander: nil,
                services: [
                    RunnerServiceStatus(id: "queue", name: "Job Queue", active: true, detail: "Bereit"),
                    RunnerServiceStatus(id: "worker", name: "Worker", active: true, detail: "Testmodus")
                ],
                backup: nil, recentAudit: nil, runnerInstances: nil,
                activeJobs: [
                    RunnerJobStatus(
                        id: "g99-test-job", name: "iOS Next UI Acceptance",
                        workflow: "G99", repository: "Bambis-Lab/ios-next-build",
                        branch: "fix/iosnext-164-dashboard-sliders-fix01-05",
                        runnerID: "runner-01", runnerName: "Xcode 27",
                        state: "in_progress", startedAt: nil
                    )
                ]
            )
        )
        _model = State(initialValue: fixture)
    }

    var body: some View {
        RunnerDashboardView(model: model)
            .accessibilityIdentifier("g99-fixture-runner")
    }
}

private struct G99ProjectsAcceptanceFixture: View {
    @State private var model: AdminControlModel

    init() {
        let fixture = AdminControlModel()
        fixture.projectsV2 = [
            AdminProjectStatusV2(
                id: "ios-next", title: "iOS Next",
                repository: "Bambis-Lab/ios-next", dispatchCount: 5,
                activeJobs: 1, latestDispatchState: "in_progress",
                ci: AdminCIStatusV2(
                    status: "success", conclusion: "success",
                    headSHA: "25b1176ecd930bff8db04f804d62acf550af83c7",
                    workflow: "iPhone G99", updatedAt: Date(timeIntervalSince1970: 1_760_000_000),
                    error: nil
                )
            ),
            AdminProjectStatusV2(
                id: "factory", title: "Master Control Factory",
                repository: "Bambis-Lab/master-control-factory", dispatchCount: 8,
                activeJobs: 0, latestDispatchState: "completed", ci: nil
            ),
            AdminProjectStatusV2(
                id: "research", title: "CIR/KISA Forschung",
                repository: "Bambis-Lab/Forschung", dispatchCount: 3,
                activeJobs: 0, latestDispatchState: "failed",
                ci: AdminCIStatusV2(
                    status: "failure", conclusion: "failure",
                    headSHA: "1234567890abcdef", workflow: "Research CI",
                    updatedAt: Date(timeIntervalSince1970: 1_760_000_000), error: nil
                )
            )
        ]
        fixture.jobsV2 = [
            AdminJobStatusV2(
                id: "acceptance-1", ticketID: "G99-UI",
                projectID: "ios-next", state: "in_progress",
                approvedBy: "fixture", approvedAt: Date(timeIntervalSince1970: 1_760_000_000)
            )
        ]
        _model = State(initialValue: fixture)
    }

    var body: some View {
        OwnerProjectsView(model: model, capabilities: model.ownerCapabilityRegistry)
            .accessibilityIdentifier("g99-fixture-projects")
    }
}
#endif
