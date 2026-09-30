import SwiftUI

enum RunnerMetricDestination: Hashable {
    case registered
    case idle
    case busy
    case cpu
    case memory
    case disk

    var title: String {
        switch self {
        case .registered: "Registrierte Runner"
        case .idle: "Freie Runner"
        case .busy: "Beschäftigte Runner"
        case .cpu: "CPU"
        case .memory: "Arbeitsspeicher"
        case .disk: "Speicher"
        }
    }

    var symbol: String {
        switch self {
        case .registered: "server.rack"
        case .idle: "checkmark.circle.fill"
        case .busy: "hammer.fill"
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .disk: "internaldrive.fill"
        }
    }
}
struct RunnerMetricDetailView: View {
    let metric: RunnerMetricDestination
    let status: RunnerStatus

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                hero
                relatedMetrics
                runnerInventory
                explanation
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground(style: .neutral))
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: metric.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: 54)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title).font(.title2.bold())
                    Text(primaryValue).font(.system(size: 42, weight: .bold, design: .rounded))
                }
                Spacer(minLength: 0)
            }
            if let progress = progressValue {
                ProgressView(value: progress)
                    .tint(tint)
                Text(progressCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .ios27ContentSurface(radius: 28, elevated: true)
    }

    @ViewBuilder
    private var relatedMetrics: some View {
        IOS27SectionHeader(title: "Details")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            switch metric {
            case .registered:
                IOS27StatusCard(title: "Frei", value: "\(status.idleRunners)", symbol: "checkmark.circle.fill", tint: .green)
                IOS27StatusCard(title: "Beschäftigt", value: "\(status.busyRunners)", symbol: "hammer.fill", tint: .orange)
            case .idle:
                IOS27StatusCard(title: "Registriert", value: "\(status.registeredRunners)", symbol: "server.rack", tint: .blue)
                IOS27StatusCard(title: "Auslastung", value: percent(busyRatio), symbol: "gauge.with.dots.needle.67percent", tint: busyRatio >= 0.8 ? .orange : .blue)
            case .busy:
                IOS27StatusCard(title: "Registriert", value: "\(status.registeredRunners)", symbol: "server.rack", tint: .blue)
                IOS27StatusCard(title: "Frei", value: "\(status.idleRunners)", symbol: "checkmark.circle.fill", tint: .green)
            case .cpu:
                IOS27StatusCard(title: "Auslastung", value: percent((status.cpuPercent ?? 0) / 100), symbol: "cpu.fill", tint: tint)
            case .memory:
                IOS27StatusCard(title: "Belegt", value: percent((status.memoryPercent ?? 0) / 100), symbol: "memorychip.fill", tint: tint)
                IOS27StatusCard(title: "Frei", value: percent(max(0, 1 - (status.memoryPercent ?? 0) / 100)), symbol: "checkmark.circle.fill", tint: .green)
            case .disk:
                IOS27StatusCard(title: "Belegt", value: percent((status.diskPercent ?? 0) / 100), symbol: "internaldrive.fill", tint: tint)
                IOS27StatusCard(title: "Frei", value: percent(max(0, 1 - (status.diskPercent ?? 0) / 100)), symbol: "externaldrive.fill", tint: .green)
            }
        }
    }

    @ViewBuilder
    private var runnerInventory: some View {
        if let runners = visibleRunners, !runners.isEmpty {
            IOS27SectionHeader(title: "Runner", subtitle: "Vom Backend pro Instanz geliefert")
            VStack(spacing: 0) {
                ForEach(Array(runners.enumerated()), id: \.element.id) { index, runner in
                    runnerRow(runner)
                    if index != runners.indices.last { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 14)
            .ios27ContentSurface(radius: 24)
        }

        if metric == .busy, let jobs = status.activeJobs, !jobs.isEmpty {
            IOS27SectionHeader(title: "Aktive Jobs", subtitle: "Workflow- und Runner-Zuordnung")
            VStack(spacing: 0) {
                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                    jobRow(job)
                    if index != jobs.indices.last { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 14)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func runnerRow(_ runner: RunnerInstanceStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: runner.busy ? "hammer.fill" : "checkmark.circle.fill")
                .foregroundStyle(runner.online ? (runner.busy ? Color.orange : Color.green) : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(runner.name).font(.subheadline.weight(.semibold))
                Text(runnerDetail(runner)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(runner.online ? (runner.busy ? "Beschäftigt" : "Frei") : "Offline")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(runner.online ? (runner.busy ? Color.orange : Color.green) : Color.secondary)
        }
        .padding(.vertical, 10)
    }

    private func jobRow(_ job: RunnerJobStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hammer.circle.fill").foregroundStyle(.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).font(.subheadline.weight(.semibold))
                Text(jobDetail(job)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(job.state).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
        }
        .padding(.vertical, 10)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(explanationTitle).font(.headline)
            Text(explanationText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .ios27ContentSurface(radius: 20)
    }

    private var primaryValue: String {
        switch metric {
        case .registered: "\(status.registeredRunners)"
        case .idle: "\(status.idleRunners)"
        case .busy: "\(status.busyRunners)"
        case .cpu: status.cpuPercent.map { "\(Int($0.rounded())) %" } ?? "—"
        case .memory: status.memoryPercent.map { "\(Int($0.rounded())) %" } ?? "—"
        case .disk: status.diskPercent.map { "\(Int($0.rounded())) %" } ?? "—"
        }
    }

    private var progressValue: Double? {
        switch metric {
        case .registered: registeredRatio
        case .idle: idleRatio
        case .busy: busyRatio
        case .cpu: status.cpuPercent.map { min(max($0 / 100, 0), 1) }
        case .memory: status.memoryPercent.map { min(max($0 / 100, 0), 1) }
        case .disk: status.diskPercent.map { min(max($0 / 100, 0), 1) }
        }
    }

    private var progressCaption: String {
        switch metric {
        case .registered: "Gesamtkapazität des aktuell erkannten Runner-Pools"
        case .idle: "\(status.idleRunners) von \(status.registeredRunners) Runnern sind frei"
        case .busy: "\(status.busyRunners) von \(status.registeredRunners) Runnern sind beschäftigt"
        case .cpu: "Aktuelle CPU-Auslastung der Runner-VM"
        case .memory: "Aktuelle RAM-Auslastung der Runner-VM"
        case .disk: "Aktuelle Belegung des Root-Dateisystems der Runner-VM"
        }
    }

    private var tint: Color {
        switch metric {
        case .registered: return .blue
        case .idle: return .green
        case .busy: return .orange
        case .cpu:
            let value = status.cpuPercent ?? 0
            return value >= 85 ? .red : .blue
        case .memory:
            let value = status.memoryPercent ?? 0
            return value >= 85 ? .red : .purple
        case .disk:
            let value = status.diskPercent ?? 0
            return value >= 85 ? .red : .cyan
        }
    }

    private var registeredRatio: Double {
        status.registeredRunners > 0 ? 1 : 0
    }

    private var idleRatio: Double {
        guard status.registeredRunners > 0 else { return 0 }
        return min(max(Double(status.idleRunners) / Double(status.registeredRunners), 0), 1)
    }

    private var busyRatio: Double {
        guard status.registeredRunners > 0 else { return 0 }
        return min(max(Double(status.busyRunners) / Double(status.registeredRunners), 0), 1)
    }

    private var visibleRunners: [RunnerInstanceStatus]? {
        guard let runners = status.runnerInstances else { return nil }
        switch metric {
        case .registered: return runners
        case .idle: return runners.filter { $0.online && !$0.busy }
        case .busy: return runners.filter { $0.online && $0.busy }
        case .cpu, .memory, .disk: return nil
        }
    }

    private func runnerDetail(_ runner: RunnerInstanceStatus) -> String {
        var parts: [String] = []
        if let os = runner.operatingSystem { parts.append(os) }
        if let arch = runner.architecture { parts.append(arch) }
        if let labels = runner.labels, !labels.isEmpty { parts.append(labels.joined(separator: " · ")) }
        if let job = runner.currentJobID { parts.append("Job \(job)") }
        return parts.isEmpty ? "Keine zusätzlichen Metadaten" : parts.joined(separator: " · ")
    }

    private func jobDetail(_ job: RunnerJobStatus) -> String {
        var parts: [String] = []
        if let workflow = job.workflow { parts.append(workflow) }
        if let repository = job.repository { parts.append(repository) }
        if let branch = job.branch { parts.append(branch) }
        if let runner = job.runnerName { parts.append("Runner: \(runner)") }
        return parts.isEmpty ? "Keine zusätzlichen Metadaten" : parts.joined(separator: " · ")
    }

    private var explanationTitle: String {
        switch metric {
        case .registered: "Runner-Pool"
        case .idle: "Verfügbare Kapazität"
        case .busy: "Aktive Jobs"
        case .cpu: "CPU der Ubuntu-VM"
        case .memory: "RAM der Ubuntu-VM"
        case .disk: "Speicher der Ubuntu-VM"
        }
    }

    private var explanationText: String {
        switch metric {
        case .registered:
            "Zeigt alle vom Runner-Control-Dienst erkannten GitHub-Runner. Sobald das Backend runner_instances liefert, erscheinen Namen, Status, Labels, Plattform und aktuelle Job-Zuordnung automatisch."
        case .idle:
            "Freie Runner können neue Jobs übernehmen. Die Quote wird relativ zur aktuell registrierten Runner-Zahl berechnet."
        case .busy:
            "Beschäftigte Runner führen gerade Jobs aus. Wenn das Backend active_jobs liefert, erscheinen Workflow, Repository, Branch und Runner-Zuordnung direkt darunter."
        case .cpu:
            "Die CPU-Auslastung stammt direkt von der Ubuntu-VM. Ab 85 Prozent wird die Darstellung als kritisch markiert."
        case .memory:
            "Die RAM-Auslastung stammt direkt von der Ubuntu-VM. Ab 85 Prozent wird die Darstellung als kritisch markiert."
        case .disk:
            "Die Speicheranzeige beschreibt die Belegung des Root-Dateisystems. Ab 85 Prozent wird sie als kritisch markiert."
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
    }
}
