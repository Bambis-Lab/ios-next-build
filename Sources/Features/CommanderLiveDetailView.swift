import SwiftUI

struct CommanderLiveDetailView: View {
    let model: RunnerControlModel

    private var snapshot: MasterRuntimeSnapshot { model.masterRuntimeSnapshot }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                metrics
                runnerSection
                activeJobsSection
                sourceSection
                securityNotice
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle("Master Runtime")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Master Runtime").font(.title3.weight(.bold))
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusBadge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusTint.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusTint)
            }

            if let updatedAt = snapshot.updatedAt {
                LabeledContent("Aktualisiert", value: updatedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .ios27ContentSurface(radius: 28, elevated: true)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOS27SectionHeader(title: "System")
            HStack(spacing: 10) {
                metric("Vorgänge", "\(snapshot.activeOperations)", "bolt.horizontal.fill")
                metric("CPU", String(format: "%.1f%%", snapshot.cpuPercent), "cpu")
            }
            HStack(spacing: 10) {
                metric("RAM", String(format: "%.1f%%", snapshot.memoryPercent), "memorychip")
                metric("Disk", snapshot.diskPercent.map { String(format: "%.1f%%", $0) } ?? "—", "internaldrive")
            }
            metric("Uptime", formatUptime(snapshot.uptimeSeconds), "clock.arrow.circlepath")
        }
    }

    private var runnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOS27SectionHeader(title: "Runner")
            HStack(spacing: 10) {
                metric("Registriert", "\(snapshot.registeredRunners)", "server.rack")
                metric("Idle", "\(snapshot.idleRunners)", "pause.circle")
                metric("Busy", "\(snapshot.busyRunners)", "bolt.circle")
            }
        }
    }

    @ViewBuilder
    private var activeJobsSection: some View {
        if !snapshot.activeJobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                IOS27SectionHeader(title: "Aktive Jobs", subtitle: "Sanitisierte Runner-Daten")
                ForEach(snapshot.activeJobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(job.state.localizedCapitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let workflow = job.workflow { detail("Workflow", workflow) }
                        if let repository = job.repository { detail("Repo", repository) }
                        if let branch = job.branch { detail("Branch", branch) }
                        if let runner = job.runnerName ?? job.runnerID { detail("Runner", runner) }
                        if let startedAt = job.startedAt {
                            detail("Gestartet", startedAt.formatted(date: .omitted, time: .standard))
                        }
                    }
                    .padding(14)
                    .ios27ContentSurface(radius: 20)
                }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            IOS27SectionHeader(title: "Quelle")
            LabeledContent("Runtime-Pfad", value: snapshot.source == .native ? "Native Master Runtime" : "Compatibility Adapter")
            LabeledContent("Status", value: statusBadge)
            if let updatedAt = snapshot.updatedAt {
                LabeledContent("Freshness", value: relativeAge(updatedAt))
            }
        }
        .font(.caption)
        .padding(14)
        .ios27ContentSurface(radius: 20)
    }

    private var securityNotice: some View {
        IOS27StatusCard(
            title: "Sicherheit",
            value: "Sanitisierte Runtime-Daten",
            symbol: "lock.shield.fill",
            tint: .green,
            detail: "Es werden ausschließlich sanitisierte Runtime-Metriken und Job-Metadaten angezeigt. Befehle, Argumente, Tokens und Dateiinhalte werden nicht übertragen."
        )
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .ios27ContentSurface(radius: 20)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):").foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.secondary).lineLimit(2)
        }
        .font(.caption2)
    }

    private var statusText: String {
        switch snapshot.availability {
        case .ready: "Bereit"
        case .degraded: "Eingeschränkt"
        case .unavailable: "Nicht verfügbar"
        }
    }

    private var statusBadge: String {
        switch snapshot.availability {
        case .ready: "LIVE"
        case .degraded: "DEGRADED"
        case .unavailable: "OFFLINE"
        }
    }

    private var statusTint: Color {
        switch snapshot.availability {
        case .ready: .green
        case .degraded: .orange
        case .unavailable: .secondary
        }
    }

    private func relativeAge(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "gerade eben" }
        if seconds < 60 { return "vor \(seconds)s" }
        if seconds < 3_600 { return "vor \(seconds / 60)m" }
        return "vor \(seconds / 3_600)h"
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
