import SwiftUI

struct OwnerBackground: View {
    var body: some View {
        FactoryAmbientBackground(kind: .owner)
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
