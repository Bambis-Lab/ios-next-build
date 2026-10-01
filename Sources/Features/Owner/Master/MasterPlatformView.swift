import SwiftUI

struct MasterPlatformView: View {
    let model: AdminControlModel
    let runnerModel: RunnerControlModel

    private var runnerStatus: RunnerStatus? {
        if case let .ready(status) = runnerModel.state { return status }
        return nil
    }

    private var snapshot: MasterDataPlaneSnapshot {
        MasterDataPlaneSnapshot.compatibility(
            projects: model.projectsV2,
            runnerStatus: runnerStatus,
            observedAt: runnerStatus?.lastHealthCheck
        )
    }

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                header
                sourceHealth
                repositories
                ciSection
                runners
                governance
                diagnostics
                releaseIntegrity
                governedActions
            }
        }
        .navigationTitle("Master Platform")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refreshStatusV2()
            await runnerModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            IOSNextSectionHeader(
                title: "Master Data Plane",
                subtitle: "Repositories, CI, Runner, Governance und Diagnose in einer lesenden Sicht",
                symbol: "square.3.layers.3d"
            )
            HStack(spacing: 8) {
                metric("Repos", snapshot.repositories.count)
                metric("CI", snapshot.ciRuns.count)
                metric("Runner", snapshot.runners.count)
                metric("Jobs", snapshot.runnerJobs.count)
            }
            OwnerStatusRow(
                title: "Authority",
                detail: snapshot.governance.actionsServerControlled ? "Produktive Capabilities bleiben serverseitig kontrolliert." : "Authority-Status prüfen.",
                symbol: "checkmark.shield.fill",
                value: snapshot.governance.authority,
                tint: .green
            )
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sourceHealth: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Quellen", subtitle: "Teilfehler degradieren nur die betroffene Quelle", symbol: "point.3.connected.trianglepath.dotted")
            ForEach(snapshot.sourceHealth) { source in
                OwnerStatusRow(
                    title: source.title,
                    detail: "\(source.authority.rawValue) · \(source.detail)",
                    symbol: source.state == .healthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    value: source.state.title,
                    tint: source.state == .healthy ? .green : .orange
                )
            }
        }
    }

    private var repositories: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Repositories", subtitle: "Kanonische Zuordnung mit Legacy-Fallback", symbol: "folder.badge.gearshape")
            if snapshot.repositories.isEmpty {
                OwnerStatusRow(title: "Repository-Inventar", detail: "Die aktuelle Quelle liefert noch keine Repositories.", symbol: "folder", value: "Keine Daten", tint: .orange)
            } else {
                ForEach(MasterRepositoryCategory.allCases, id: \.rawValue) { category in
                    let records = snapshot.repositories.filter { $0.category == category }
                    if !records.isEmpty {
                        Text(category.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(records) { repository in
                            OwnerStatusRow(
                                title: repository.name,
                                detail: "\(repository.fullName) · \(repository.role) · \(repository.lifecycle)",
                                symbol: repository.canonical ? "checkmark.seal.fill" : "folder",
                                value: repository.currentSHA.map(shortSHA) ?? repository.defaultBranch ?? "—",
                                tint: repository.verification == .verified ? .green : .indigo
                            )
                        }
                    }
                }
            }
        }
    }

    private var ciSection: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "CI", subtitle: "Workflow-Stand pro Repository", symbol: "gearshape.2.fill")
            if snapshot.ciRuns.isEmpty {
                OwnerStatusRow(title: "CI", detail: "Backend liefert aktuell keine CI-Snapshots.", symbol: "gearshape.2", value: "Nicht geliefert", tint: .orange)
            } else {
                ForEach(snapshot.ciRuns.prefix(12)) { run in
                    OwnerStatusRow(
                        title: run.workflow,
                        detail: "\(run.repository)\(run.headSHA.map { " · \(shortSHA($0))" } ?? "")",
                        symbol: ciSymbol(run.state),
                        value: ciTitle(run.state),
                        tint: ciTint(run.state)
                    )
                }
            }
        }
    }

    private var runners: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Runner", subtitle: "Ein kanonischer Runner- und Jobbestand", symbol: "server.rack")
            if snapshot.runners.isEmpty {
                let registered = runnerStatus?.registeredRunners ?? 0
                OwnerStatusRow(
                    title: "Runner-Inventar",
                    detail: registered > 0 ? "\(registered) registriert, Instanzdetails werden von dieser Quelle nicht geliefert." : "Keine Runner-Instanzen geliefert.",
                    symbol: "server.rack",
                    value: registered > 0 ? "\(registered)" : "Keine Daten",
                    tint: registered > 0 ? .green : .orange
                )
            } else {
                ForEach(snapshot.runners) { runner in
                    let job = snapshot.runnerJobs.first { $0.runnerID == runner.id || $0.runnerName == runner.name }
                    OwnerStatusRow(
                        title: runner.name,
                        detail: job.map { "\($0.repository ?? "Unbekannt") · \($0.workflow ?? $0.name)" } ?? runner.labels.joined(separator: " · "),
                        symbol: runner.busy ? "gearshape.2.fill" : "checkmark.circle.fill",
                        value: runner.online ? (runner.busy ? "Busy" : "Idle") : "Offline",
                        tint: runner.online ? (runner.busy ? .orange : .green) : .red
                    )
                }
            }
        }
    }

    private var governance: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Governance", subtitle: "Fail-closed Capability-Status", symbol: "lock.shield.fill")
            ForEach(MasterCapability.allCases) { capability in
                let active = capability == .readOnly || serverCapabilityActive(capability)
                OwnerStatusRow(
                    title: capability.rawValue,
                    detail: capabilityDetail(capability, active: active),
                    symbol: active ? "checkmark.shield.fill" : "lock.fill",
                    value: active ? "Aktiv" : "Gesperrt",
                    tint: active ? .green : .secondary
                )
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Diagnostics v3", subtitle: "Source Health, Runtime und Storage ohne Secrets", symbol: "stethoscope")
            if let diagnostics = model.diagnosticsV2 {
                ForEach(diagnostics.checks.prefix(12)) { check in
                    OwnerStatusRow(
                        title: check.title,
                        detail: MasterDiagnosticRedactor.sanitized(check.detail),
                        symbol: check.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        value: check.ok ? "OK" : check.severity.uppercased(),
                        tint: check.ok ? .green : .orange
                    )
                }
            } else {
                OwnerStatusRow(title: "Diagnostics", detail: "Keine Diagnosequelle verfügbar.", symbol: "stethoscope", value: "Nicht verfügbar", tint: .orange)
            }

            if let disk = runnerStatus?.diskPercent {
                let mount = MasterStorageMount(id: "system", title: "Systemplatte", mountPath: "/", usedPercent: disk, totalBytes: nil, freeBytes: nil)
                OwnerStatusRow(
                    title: mount.title,
                    detail: mount.mountPath,
                    symbol: "internaldrive.fill",
                    value: "\(Int(disk.rounded())) %",
                    tint: storageTint(mount.severity)
                )
            }
            ForEach(["Runner Data", "Runner Cache", "Runner Artifacts"], id: \.self) { title in
                OwnerStatusRow(title: title, detail: "Mount-Metrik wird von der aktuellen Quelle nicht geliefert.", symbol: "externaldrive", value: "—", tint: .secondary)
            }
        }
    }

    private var releaseIntegrity: some View {
        let runningVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let runningBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let backend = model.releasesV2.first(where: { $0.id == "ios-next" })
        let drift = MasterReleaseDrift(
            runningVersion: runningVersion,
            runningBuild: runningBuild,
            backendInstalledVersion: backend?.installedVersion,
            backendAvailableVersion: backend?.availableVersion
        )
        return VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Release Integrity", subtitle: "Laufendes Bundle ist die installierte Wahrheit", symbol: "shippingbox.fill")
            OwnerStatusRow(
                title: "Installiert",
                detail: drift.hasBackendDrift ? "Backend-Inventar weicht ab: \(backend?.installedVersion ?? "—")" : "Bundle und Backend ohne erkannte Abweichung",
                symbol: drift.hasBackendDrift ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                value: "\(runningVersion) (\(runningBuild))",
                tint: drift.hasBackendDrift ? .orange : .green
            )
            if let available = backend?.availableVersion {
                OwnerStatusRow(title: "Backend verfügbar", detail: "Nur Vergleichsquelle", symbol: "arrow.down.circle", value: available, tint: .secondary)
            }
        }
    }

    private var governedActions: some View {
        VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
            IOSNextSectionHeader(title: "Governed Owner Actions", subtitle: "Plan → Precheck → Approval → Execute → Verify → Rollback", symbol: "checkmark.shield.fill")
            ForEach([MasterCapability.sourceWrite, .runnerWrite, .runtimeWrite]) { capability in
                let active = serverCapabilityActive(capability)
                OwnerStatusRow(
                    title: capability.rawValue,
                    detail: active ? "Source unterstützt den governeden Lifecycle; Ausführung benötigt einen frischen Server-Plan." : "Source vorbereitet; Server-Capability bleibt gesperrt.",
                    symbol: active ? "checkmark.circle.fill" : "lock.fill",
                    value: active ? "Server aktiv" : "Locked",
                    tint: active ? .green : .secondary
                )
            }
            OwnerStatusRow(title: "LIVE_WRITE / HOST_CONTROL", detail: "Keine freie Shell, kein sudo, kein freies Process- oder Service-Control.", symbol: "hand.raised.fill", value: "Gesperrt", tint: .secondary)
        }
    }

    private func serverCapabilityActive(_ capability: MasterCapability) -> Bool {
        guard capability != .readOnly else { return true }
        let values = model.v2Capabilities?.capabilities ?? []
        let raw = capability.rawValue
        return values.contains(raw) || values.contains(raw.lowercased()) || values.contains(raw.lowercased().replacingOccurrences(of: "_", with: "."))
    }

    private func capabilityDetail(_ capability: MasterCapability, active: Bool) -> String {
        if capability == .readOnly { return "Diagnose, Repositories, CI, Runner und Governance" }
        if MasterActionPolicy.alwaysLockedCapabilities.contains(capability) { return "In 1.4.0 absichtlich nicht ausführbar" }
        return active ? "Vom Server freigegeben; governeder Action-Lifecycle erforderlich" : "Serverseitig nicht freigegeben"
    }

    private func shortSHA(_ value: String) -> String { String(value.prefix(8)) }

    private func ciTitle(_ state: MasterCIState) -> String {
        switch state {
        case .queued: "Queued"
        case .running: "Running"
        case .success: "Success"
        case .failure: "Failure"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        case .unknown: "Unbekannt"
        }
    }

    private func ciSymbol(_ state: MasterCIState) -> String {
        switch state {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .running: "gearshape.2.fill"
        case .queued: "clock.fill"
        case .cancelled, .skipped, .unknown: "circle.dashed"
        }
    }

    private func ciTint(_ state: MasterCIState) -> Color {
        switch state {
        case .success: .green
        case .failure: .red
        case .running, .queued: .blue
        case .cancelled, .skipped, .unknown: .secondary
        }
    }

    private func storageTint(_ severity: MasterStorageSeverity) -> Color {
        switch severity {
        case .normal: .green
        case .notice: .yellow
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
