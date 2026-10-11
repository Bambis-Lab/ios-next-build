import SwiftUI

/// Scoped to the native Control Center and Runner. The shared home/room
/// backgrounds are intentionally not touched.
enum FactoryAmbientKind {
    case owner
    case factory
    case runner

    var accents: (Color, Color) {
        switch self {
        case .owner: (.indigo, .blue)
        case .factory: (.indigo, .purple)
        case .runner: (.blue, .cyan)
        }
    }
}

struct FactoryAmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let kind: FactoryAmbientKind

    var body: some View {
        let accent = kind.accents
        ZStack {
            Color(.systemGroupedBackground)
            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        accent.0.opacity(scheme == .dark ? 0.18 : 0.07),
                        accent.1.opacity(scheme == .dark ? 0.065 : 0.035),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        accent.1.opacity(scheme == .dark ? 0.08 : 0.045),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 28,
                    endRadius: 520
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
