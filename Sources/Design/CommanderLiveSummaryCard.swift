import SwiftUI

struct CommanderLiveSummaryCard: View {
    let state: CommanderLiveViewState

    private var snapshot: CommanderSnapshot? {
        state.effectiveSnapshot
    }

    private var title: String {
        "Master Runtime"
    }

    private var statusText: String {
        switch state.connection {
        case .live:
            return "Live"
        case .syncing, .connecting:
            return "Verbinden"
        case .reconnecting:
            return "Neu verbinden"
        case .degraded:
            return "Eingeschränkt"
        case .disconnected:
            return snapshot == nil ? "Offline" : "Letzter Stand"
        case .unconfigured:
            return "Nicht konfiguriert"
        }
    }

    private var tint: Color {
        switch state.connection {
        case .live:
            return .green
        case .syncing, .connecting, .reconnecting:
            return .blue
        case .degraded:
            return .orange
        case .disconnected, .unconfigured:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let snapshot {
                    Text("\(snapshot.activeCount) Vorgänge · CPU \(Int((snapshot.cpuPercent ?? 0).rounded())) % · RAM \(Int((snapshot.memoryPercent ?? 0).rounded())) %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .ios27ContentSurface(radius: 24, elevated: true)
    }
}
