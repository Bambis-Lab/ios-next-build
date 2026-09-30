import SwiftUI

enum IOS27AmbientBackgroundStyle {
    case home
    case nico(mediaActive: Bool)
    case juli(lightAccent: Color?)
    case mika
    case wohnzimmer
    case timo
    case huette
    case pool
    case rasen
    case handys
    case neutral

    static func room(named name: String, juliAccent: Color? = nil, nicoMediaActive: Bool = false) -> Self {
        switch name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) {
        case "nico zimmer": return .nico(mediaActive: nicoMediaActive)
        case "juli zimmer": return .juli(lightAccent: juliAccent)
        case "mika zimmer": return .mika
        case "wohnzimmer": return .wohnzimmer
        case "timo zimmer": return .timo
        case "hutte", "hutte master": return .huette
        case "pool": return .pool
        case "rasen": return .rasen
        case "handys": return .handys
        default: return .neutral
        }
    }

    fileprivate var palette: (primary: Color, secondary: Color, tertiary: Color, intensity: Double) {
        switch self {
        case .home:
            return (.indigo, .blue, .purple, 1.06)
        case .nico(let mediaActive):
            return (.indigo, mediaActive ? .cyan : .blue, .purple, mediaActive ? 1.18 : 1.10)
        case .juli(let lightAccent):
            return (lightAccent ?? .blue, .purple, .pink, lightAccent == nil ? 1.04 : 1.16)
        case .mika:
            return (.cyan, .blue, .indigo, 1.08)
        case .wohnzimmer:
            return (.indigo, .orange, .brown, 1.00)
        case .timo:
            return (.blue, .teal, .indigo, 1.00)
        case .huette:
            return (.teal, .green, .orange, 1.00)
        case .pool:
            return (.cyan, .blue, .teal, 1.10)
        case .rasen:
            return (.green, .teal, .mint, 1.04)
        case .handys:
            return (.indigo, .blue, .cyan, 0.98)
        case .neutral:
            return (.indigo, .blue, .purple, 0.88)
        }
    }
}

struct IOS27HomeBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var style: IOS27AmbientBackgroundStyle = .home

    var body: some View {
        let palette = style.palette
        let accessibilityFactor = reduceTransparency ? 0.72 : 1.0
        let intensity = palette.intensity * accessibilityFactor

        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    palette.primary.opacity(0.44 * intensity),
                    palette.secondary.opacity(0.18 * intensity),
                    palette.tertiary.opacity(0.34 * intensity),
                    Color.black.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [palette.secondary.opacity(0.32 * intensity), .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 520
            )
            RadialGradient(
                colors: [palette.tertiary.opacity(0.26 * intensity), .clear],
                center: .bottomLeading,
                startRadius: 18,
                endRadius: 620
            )
            LinearGradient(
                colors: [Color.black.opacity(0.02), Color.black.opacity(0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct IOS27Surface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let radius: CGFloat
    let tint: Color
    let elevated: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .shadow(
                    color: elevated ? tint.opacity(0.12) : .clear,
                    radius: elevated ? 20 : 0,
                    y: elevated ? 10 : 0
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        }
    }
}

extension View {
    func ios27Surface(radius: CGFloat = 24, tint: Color = .clear, elevated: Bool = false) -> some View {
        modifier(IOS27Surface(radius: radius, tint: tint, elevated: elevated))
    }
}

struct IOS27ContentSurface: ViewModifier {
    let radius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .background(Color(.secondarySystemGroupedBackground), in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.055), lineWidth: 0.5))
            .contentShape(shape)
            .shadow(color: elevated ? Color.black.opacity(0.10) : .clear, radius: elevated ? 14 : 0, y: elevated ? 7 : 0)
    }
}

extension View {
    func ios27ContentSurface(radius: CGFloat = 24, elevated: Bool = false) -> some View {
        modifier(IOS27ContentSurface(radius: radius, elevated: elevated))
    }
}

struct OwnerHomeHeader: View {
    let connectionState: AppModel.ConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nico")
                        .font(.largeTitle.weight(.bold))
                    Text("Dein Zuhause")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HomeConnectionPill(state: connectionState)
            }
        }
        .padding(.top, 2)
    }
}

struct HomeConnectionPill: View {
    let state: AppModel.ConnectionState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(state.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.82))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.6))
        .accessibilityLabel("Home Assistant: \(state.statusText)")
    }

    private var tint: Color {
        switch state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .notConfigured, .failed: .red
        }
    }
}

struct HomeStatusChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.90))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.7))
    }
}

struct HomeMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 86)
    }
}

// Adjacent glass controls share one rendering container. Add glassEffectID only when a control actually morphs between distinct glass views; static groups intentionally do not use IDs.
struct IOS27GlassControlGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

struct IOS27GlassButtonStyle: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    func ios27GlassButton(prominent: Bool = false) -> some View {
        modifier(IOS27GlassButtonStyle(prominent: prominent))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

private struct IOS27HoldActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressing = false

    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isPressing ? 0.98 : 1))
            .opacity(reduceMotion ? 1 : (isPressing ? 0.96 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isPressing)
            .onLongPressGesture(
                minimumDuration: 0.45,
                maximumDistance: 12,
                perform: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                },
                onPressingChanged: { pressing in
                    isPressing = pressing
                }
            )
    }
}

extension View {
    func ios27HoldAction(_ action: @escaping () -> Void) -> some View {
        modifier(IOS27HoldActionModifier(action: action))
    }
}

private struct IOS27ScrollBottomClearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.top, 4)
            .safeAreaPadding(.bottom, 36)
    }
}

extension View {
    func ios27ScrollBottomClearance() -> some View {
        modifier(IOS27ScrollBottomClearance())
    }
}

extension HomeAssistantEntity {
    var ios27LightTint: Color {
        guard isOn else { return .secondary }
        guard domain == "light", let color = lightColor else { return .yellow }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}
