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
    case wireguard

    var initialTab: AppTab? {
        switch self {
        case .home: .home
        case .rooms: .rooms
        case .chat: .chat
        case .media: .media
        case .system: .system
        case .light, .mediaDetail, .owner, .wireguard: nil
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
    @State private var appModel = AppModel.preview
    @State private var chatModel = ChatModel.preview

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let initialScreen = Self.screen(from: arguments)
        let options = ProductAcceptanceOptions(arguments: arguments)
        self.options = options
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
        .background {
            VisualAcceptanceReadyProbe(
                markerBaseName: "iosnext-product-screen-ready-\(screen.rawValue)-\(acceptanceAppearanceName)",
                accessibilityIdentifier: "visual-ready-product-\(screen.rawValue)-\(acceptanceAppearanceName)",
                payload: "screen=\(screen.rawValue);appearance=\(acceptanceAppearanceName)"
            )
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
        case .wireguard:
            NavigationStack {
                WireGuardView()
            }
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
