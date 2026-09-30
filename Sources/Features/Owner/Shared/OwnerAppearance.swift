import SwiftUI

struct OwnerBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(.systemGroupedBackground)
            }
            LinearGradient(
                colors: [
                    Color.indigo.opacity(reduceTransparency ? 0.06 : 0.11),
                    Color.blue.opacity(reduceTransparency ? 0.02 : 0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.indigo.opacity(reduceTransparency ? 0.025 : 0.06), .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct OwnerPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: IOSNextLayout.pageMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.bottom, 28)
        .background(Color.clear)
    }
}

private struct OwnerManagementBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

extension View {
    func ownerManagementBackground() -> some View {
        modifier(OwnerManagementBackgroundModifier())
    }
}
