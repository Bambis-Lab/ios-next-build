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
                    VStack(spacing: 6) {
                        Text("Live Operations nicht eingerichtet")
                        Text("Die Live-Verbindung wird automatisch aus der bestehenden Runner-/Master-Konfiguration übernommen. Es ist kein zweiter Endpoint und kein zusätzliches Token erforderlich.")
                    }
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
                    IOS27SectionHeader(title: "Aktive Vorgänge", subtitle: "Sanitisierte Master-Ereignisse")
                    ForEach(model.activeOperations) { operation in
                        operationCard(operation)
                    }
                }

                IOS27SectionHeader(title: "Letzte Vorgänge", subtitle: "Bis zu 50 abgeschlossene Ereignisse")
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
                if let lastEventAt = model.lastEventAt {
                    Text("Datenstand · \(relativeAge(lastEventAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(operation.source.title) · \(operation.kind)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(operation.state.rawValue.localizedCapitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(operation.state == .failed ? .red : .secondary)
            }

            if let subtitle = operation.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            operationDetails(operation)
            provenanceDetails(operation)

            HStack {
                Label(operation.durationText, systemImage: "clock")
                Spacer()
                Text("\(operation.freshnessStateText) · \(operation.freshnessText)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .ios27ContentSurface(radius: 20)
    }

    @ViewBuilder
    private func operationDetails(_ operation: LiveOperation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let repository = operation.repository, !repository.isEmpty {
                detailRow("Repo", repository, "shippingbox")
            }
            if let branch = operation.branchName {
                detailRow("Branch", branch, "arrow.triangle.branch")
            }
            if let workflow = operation.workflowName {
                detailRow("Workflow", workflow, "point.3.connected.trianglepath.dotted")
            }
            if let job = operation.jobName {
                detailRow("Job", job, "hammer")
            }
            if let phase = operation.phaseName {
                detailRow("Phase", phase, "square.stack.3d.up")
            }
            if let step = operation.stepName {
                detailRow("Step", step, "list.bullet.rectangle")
            }
            if let runner = operation.runnerName {
                detailRow("Runner", runner, "server.rack")
            }
            if let lastEvent = operation.lastEvent {
                detailRow("Letztes Event", lastEvent, "clock.arrow.circlepath")
            }
            if let nextEvent = operation.nextExpectedEvent {
                detailRow("Als Nächstes", nextEvent, "arrow.right.circle")
            }
        }
    }

    private func provenanceDetails(_ operation: LiveOperation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().opacity(0.5)
            detailRow("Quelle", operation.evidenceSource, "dot.radiowaves.left.and.right")
            detailRow("Authority", operation.authorityName, "checkmark.seal")
            detailRow("Evidence", operation.verificationText, "checkmark.shield")
            detailRow("Capability", operation.capabilityName, "lock.shield")
        }
    }

    private func detailRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).frame(width: 14)
            Text("\(title):")
            Text(value).lineLimit(2)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
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

    private func relativeAge(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "gerade eben" }
        if seconds < 60 { return "vor \(seconds)s" }
        if seconds < 3_600 { return "vor \(seconds / 60)m" }
        return "vor \(seconds / 3_600)h"
    }
}
