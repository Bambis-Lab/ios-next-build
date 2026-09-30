import SwiftUI

struct ReconnectStatusOverlay: View {
    let state: AppModel.ConnectionState
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible {
                Label("Verbindung wird wiederhergestellt …", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isVisible)
        .task(id: taskIdentity) {
            isVisible = false
            guard isReconnectState else { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isVisible = true
        }
    }

    private var isReconnectState: Bool {
        switch state {
        case .reconnecting, .connecting:
            true
        default:
            false
        }
    }

    private var taskIdentity: String {
        switch state {
        case .notConfigured: "not-configured"
        case .connecting: "connecting"
        case .connected: "connected"
        case let .reconnecting(attempt): "reconnecting-\(attempt)"
        case let .failed(message): "failed-\(message)"
        }
    }
}
