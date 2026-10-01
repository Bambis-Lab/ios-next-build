import SwiftUI

struct CommanderLiveSummaryCard: View {
    let state: CommanderLiveViewState

    private var snapshot: CommanderSnapshot? {
        state.effectiveSnapshot
    }

    private var title: String { "Master Runtime" }

    private var statusText: String {
        switch state.connection {
        case .live: "Live"
        case .syncing, .connecting: "Verbinden"
        case .reconnecting: "Neu verbinden"
        case .degraded: "Eingeschränkt"
        case .disconnected: snapshot == nil ? "Offline" : "Letzter Stand"
        case .unconfigured: "Nicht konfiguriert"
        }
    }

    private var tint: Color {
        switch state.connection {
        case .live: .green
        case .syncing, .connecting, .reconnecting: .blue
        case .degraded: .orange
        case .disconnected, .unconfigured: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let snapshot {
                    HStack(spacing: 6) {
                        Text("\(snapshot.activeCount) Vorgänge")
                        Text("·")
                        Text("CPU \(Int((snapshot.cpuPercent ?? 0).rounded())) %")
                        Text("·")
                        Text("RAM \(Int((snapshot.memoryPercent ?? 0).rounded())) %")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text("Warte auf Runtime-Daten")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .ios27ContentSurface(radius: 24, elevated: true)
        .accessibilityElement(children: .combine)
    }
}
