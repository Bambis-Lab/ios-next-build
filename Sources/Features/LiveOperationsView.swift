import SwiftUI

struct LiveOperationsView: View {
    @State private var runtime = IOSNextRuntime.shared

    private var model: LiveOperationsModel { runtime.liveOperationsModel }

    var body: some View {
        Group {
            if model.connectionState == .unconfigured {
                ContentUnavailableView {
                    Label("Master Runtime Live nicht verfügbar", systemImage: "waveform.path.ecg")
                } description: {
                    Text("Die Live-Verbindung wird automatisch aus der bestehenden Runner-/Master-Konfiguration übernommen. Es ist kein zweiter Endpoint und kein zusätzliches Token erforderlich.")
                }
            } else {
                dashboard
            }
        }
        .background(IOS27HomeBackground(style: .neutral))
        .navigationTitle("Master Runtime Live")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.refreshRuntimeConfiguration()
            model.startIfNeeded()
        }
        .onDisappear { model.stop(reset: false) }
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                statusCard

                if !model.activeOperations.isEmpty {
                    IOS27SectionHeader(title: "Aktive Vorgänge", subtitle: "Master MCP")
                    ForEach(model.activeOperations) { operation in
                        operationCard(operation)
                    }
                }

                IOS27SectionHeader(title: "Letzte Vorgänge", subtitle: "Sanitisierte Runtime-Ereignisse")
                if model.recentOperations.isEmpty {
                    IOS27StatusCard(
                        title: "Keine abgeschlossenen Vorgänge",
                        value: "Bereit",
                        symbol: "checkmark.circle",
                        tint: .secondary,
                        detail: "Neue Master-Runtime-Ereignisse erscheinen hier automatisch."
                    )
                } else {
                    ForEach(model.recentOperations) { operation in
                        operationCard(operation)
                    }
                }

                if let error = model.lastError, !error.isEmpty {
                    IOS27StatusCard(
                        title: "Verbindung",
                        value: "Eingeschränkt",
                        symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        detail: error
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(statusTint)
                .frame(width: 44, height: 44)
                .background(statusTint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Master Runtime").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.activeOperations.count) aktiv")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .ios27ContentSurface(radius: 22, elevated: true)
    }

    private func operationCard(_ operation: LiveOperation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(operation.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                Text(operation.state.rawValue.localizedCapitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(operation.state == .failed ? .red : .secondary)
            }
            if let subtitle = operation.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let repository = operation.repository, !repository.isEmpty {
                Label(repository, systemImage: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .ios27ContentSurface(radius: 20)
    }

    private var statusText: String {
        switch model.connectionState {
        case .unconfigured: "Nicht konfiguriert"
        case .connecting: "Verbinden …"
        case .syncing: "Synchronisieren …"
        case .live: "Live verbunden"
        case .reconnecting: "Erneut verbinden …"
        case .degraded: "Eingeschränkt"
        case .offline: "Offline"
        }
    }

    private var statusSymbol: String {
        switch model.connectionState {
        case .live: "waveform.path.ecg"
        case .connecting, .syncing, .reconnecting: "arrow.triangle.2.circlepath"
        case .degraded: "exclamationmark.triangle.fill"
        case .unconfigured, .offline: "circle.slash"
        }
    }

    private var statusTint: Color {
        switch model.connectionState {
        case .live: .green
        case .connecting, .syncing, .reconnecting: .blue
        case .degraded: .orange
        case .unconfigured, .offline: .secondary
        }
    }
}
