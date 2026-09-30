import SwiftUI

enum IOSNextLayout {
    static let pageSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 14
    static let cardRadius: CGFloat = 24
    static let compactRadius: CGFloat = 18
    static let pageMaxWidth: CGFloat = 760
}

enum IOSNextMotion {
    static let micro = Animation.smooth(duration: 0.20)
    static let state = Animation.smooth(duration: 0.28)
    static let navigation = Animation.smooth(duration: 0.34)
    static let emphasis = Animation.spring(duration: 0.42, bounce: 0.14)
}

struct IOSNextBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color("LaunchBackground")

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.105),
                    Color.indigo.opacity(colorScheme == .dark ? 0.105 : 0.045),
                    Color.cyan.opacity(colorScheme == .dark ? 0.085 : 0.030),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.105 : 0.035),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 24,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct IOSNextPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            IOSNextBackground()
            ScrollView {
                content
                    .frame(maxWidth: IOSNextLayout.pageMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct IOSNextSectionHeader: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConnectionStatusLabel: View {
    let state: AppModel.ConnectionState

    var body: some View {
        Label(state.statusText, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityLabel("Home Assistant: \(state.statusText)")
    }

    private var icon: String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .notConfigured, .failed: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .notConfigured, .failed: .red
        }
    }
}

struct IOSNextMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(value)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(16)
        .iosNextCard()
        .accessibilityElement(children: .combine)
    }
}

struct EntityRow: View {
    let entity: HomeAssistantEntity
    var isWorking = false
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(iconTint.opacity(entity.isOn ? 0.17 : 0.09))
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(entity.isAvailable ? iconTint : .secondary)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entity.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(entity.stateDisplayName)
                    .font(.footnote)
                    .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
            }
            Spacer(minLength: 8)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Aktion läuft")
            } else if let action {
                Button(action: action) {
                    Image(systemName: entity.isOn ? "power.circle.fill" : "power.circle")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!entity.isAvailable)
                .accessibilityLabel("\(entity.displayName) \(entity.isOn ? "ausschalten" : "einschalten")")
            } else {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }

    private var icon: String {
        switch entity.domain {
        case "light": entity.isOn ? "lightbulb.fill" : "lightbulb"
        case "media_player": "play.rectangle.fill"
        case "scene": "sparkles"
        case "switch": "switch.2"
        case "climate": "thermometer.medium"
        case "cover": "window.shade.open"
        case "camera": "video.fill"
        case "lock": entity.isOn ? "lock.open.fill" : "lock.fill"
        case "binary_sensor": "sensor.fill"
        default: "circle.grid.2x2.fill"
        }
    }

    private var iconTint: Color {
        guard entity.isAvailable else { return Color.secondary }
        return switch entity.domain {
        case "light": entity.isOn ? Color.yellow : Color.secondary
        case "media_player": Color.purple
        case "scene": Color.indigo
        case "climate": Color.orange
        case "cover": Color.blue
        case "camera", "lock": Color.red
        default: entity.isOn ? Color.accentColor : Color.secondary
        }
    }
}

struct EmptyFeatureView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct IOSNextErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("Schließen", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fehlermeldung schließen")
            }
        }
        .padding(14)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct IOSNextContentSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: IOSNextLayout.cardRadius, style: .continuous)

        content
            .background {
                shape.fill(Color("ContentSurface"))
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055),
                    lineWidth: 0.5
                )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035),
                radius: colorScheme == .dark ? 12 : 8,
                x: 0,
                y: colorScheme == .dark ? 5 : 2
            )
    }
}

private struct IOSNextFunctionalGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: shape)
    }
}

private struct IOSNextManagementBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(IOSNextBackground())
    }
}

extension View {
    func iosNextSurface() -> some View {
        modifier(IOSNextContentSurfaceModifier())
    }

    func iosNextFunctionalGlass<S: Shape>(in shape: S) -> some View {
        modifier(IOSNextFunctionalGlassModifier(shape: shape))
    }

    func iosNextCard() -> some View {
        iosNextSurface()
    }

    func iosNextManagementBackground() -> some View {
        modifier(IOSNextManagementBackgroundModifier())
    }
}
