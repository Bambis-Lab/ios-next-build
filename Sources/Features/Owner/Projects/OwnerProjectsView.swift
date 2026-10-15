import SwiftUI

struct OwnerProjectsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry

    private var snapshots: [ProjectPresentationSnapshot] {
        model.projectsV2.presentationSnapshots(jobs: model.jobsV2)
    }

    private var missingCISnapshots: Int {
        snapshots.filter { !$0.hasCISnapshot }.count
    }

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Label("\(projectCount) Projekte", systemImage: "folder.fill")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Label("\(model.ownerOpenTicketCount) Tickets offen", systemImage: "ticket.fill")
                        .foregroundStyle(model.ownerOpenTicketCount > 0 ? .orange : .secondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(16)
                .iosNextSurface()

                if let error = model.ownerV2Error {
                    OwnerAlertBanner(title: "Projektdaten nicht aktuell", message: error, symbol: "wifi.exclamationmark")
                }
                if !snapshots.isEmpty && missingCISnapshots > 0 {
                    OwnerAlertBanner(
                        title: "GitHub-CI nicht vollständig verbunden",
                        message: "Für \(missingCISnapshots) von \(snapshots.count) Projekten liefert das Owner Backend keinen CI-Snapshot. Repository- und Jobdaten sind davon unabhängig.",
                        symbol: "info.circle", tint: .blue
                    )
                }
                if !model.jobsV2.isEmpty {
                    HStack(spacing: 12) {
                        Label("\(model.jobsV2.count) Jobs", systemImage: "gearshape.2.fill")
                        Spacer(minLength: 0)
                        Label("\(activeJobCount) aktiv", systemImage: "play.circle.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                if capabilities.supports(.tickets) && model.ownerOpenTicketCount > 0 {
                    NavigationLink {
                        OwnerTicketInboxView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Offene Tickets", detail: "Anfragen prüfen und bearbeiten",
                            symbol: "ticket.fill", value: "\(model.ownerOpenTicketCount)", tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
                IOSNextSectionHeader(
                    title: "Deine Projekte",
                    subtitle: "Repository, Jobs und CI aus dem Owner Backend",
                    symbol: "folder.fill"
                )
                if !snapshots.isEmpty {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            OwnerProjectDetailView(snapshot: snapshot)
                        } label: {
                            projectRow(snapshot)
                        }
                        .buttonStyle(.plain)
                    }
                } else if model.projectRoutes.isEmpty {
                    OwnerCapabilityUnavailableView(
                        title: "Projekt-Snapshot",
                        detail: capabilities.supports(.projects)
                            ? "Das Owner Backend hat noch keinen v2-Projekt-Snapshot geliefert."
                            : "Projekt-Status wird vom aktuellen Backend nicht bereitgestellt."
                    )
                } else {
                    ForEach(model.projectRoutes) { route in
                        NavigationLink {
                            OwnerLegacyProjectDetailView(route: route)
                        } label: {
                            OwnerStatusRow(
                                title: route.title,
                                detail: ProjectRegistry.canonicalRepository(for: route) ?? "Kein Repository gemeldet",
                                symbol: "folder.fill", value: "Legacy"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Projekte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshStatusV2() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Projekte aktualisieren")
            }
        }
        .refreshable { await model.refreshStatusV2() }
    }

    private func projectRow(_ snapshot: ProjectPresentationSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 36, height: 36)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(snapshot.repository ?? "Repository nicht angegeben")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Label(projectValue(snapshot), systemImage: snapshot.hasCISnapshot ? "checkmark.circle" : "info.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(projectTint(snapshot))
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(14)
        .iosNextSurface()
        .accessibilityElement(children: .combine)
    }

    private var projectCount: Int {
        snapshots.isEmpty ? model.projectRoutes.count : snapshots.count
    }

    private var activeJobCount: Int {
        model.jobsV2.filter { !["completed", "resolved", "failed"].contains($0.state) }.count
    }

    private func projectValue(_ snapshot: ProjectPresentationSnapshot) -> String {
        if snapshot.activeJobs > 0 { return "\(snapshot.activeJobs) aktiv" }
        guard snapshot.hasCISnapshot else { return "CI-Daten fehlen" }
        switch snapshot.ciStatus {
        case "repository_missing": return "Kein Repository"
        case "adapter_not_configured": return "CI nicht eingerichtet"
        case "queued": return "CI wartet"
        case "in_progress": return "CI läuft"
        case "success": return "CI grün"
        case "failure": return "CI fehlgeschlagen"
        case "cancelled": return "CI abgebrochen"
        case "no_runs": return "Keine CI-Läufe"
        case "unavailable": return "CI nicht erreichbar"
        default:
            if let conclusion = snapshot.ciConclusion { return "CI \(conclusion.localizedCapitalized)" }
            return "CI Status unbekannt"
        }
    }

    private func projectTint(_ snapshot: ProjectPresentationSnapshot) -> Color {
        if snapshot.activeJobs > 0 { return .blue }
        switch snapshot.ciStatus {
        case "success": return .green
        case "in_progress", "queued": return .blue
        case "failure": return .red
        case "cancelled", "unavailable": return .orange
        default: return .secondary
        }
    }
}

struct OwnerProjectDetailView: View {
    let snapshot: ProjectPresentationSnapshot

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(title: snapshot.title, detail: "Dispatch-Ziel", symbol: "folder.fill", value: snapshot.id)

                if let repository = snapshot.repository {
                    OwnerStatusRow(
                        title: "Repository",
                        detail: snapshot.repositoryMismatch
                            ? "Kanonische Zuordnung · Legacy-Mapping korrigiert"
                            : "Kanonische Zuordnung",
                        symbol: "chevron.left.forwardslash.chevron.right",
                        value: repository,
                        tint: .indigo
                    )
                } else {
                    OwnerCapabilityUnavailableView(title: "Repository", detail: "Für dieses Projekt ist kein Repository hinterlegt.")
                }

                OwnerStatusRow(title: "Dispatches", detail: "Persistente Owner-Freigaben", symbol: "paperplane.fill", value: "\(snapshot.dispatchCount)")
                OwnerStatusRow(title: "Aktive Jobs", detail: "Nicht abgeschlossene Dispatch-Vorgänge", symbol: "gearshape.2.fill", value: "\(snapshot.activeJobs)", tint: snapshot.activeJobs > 0 ? .blue : .green)

                if snapshot.hasCISnapshot {
                    OwnerStatusRow(
                        title: "CI",
                        detail: snapshot.ciWorkflow ?? snapshot.ciError ?? ciDetail(snapshot.ciStatus),
                        symbol: ciSymbol(snapshot.ciStatus),
                        value: ciTitle(snapshot.ciStatus),
                        tint: ciTint(snapshot.ciStatus)
                    )
                    if let sha = snapshot.ciHeadSHA {
                        OwnerStatusRow(title: "CI Commit", detail: "Head SHA", symbol: "number", value: String(sha.prefix(8)))
                    }
                    if let updatedAt = snapshot.ciUpdatedAt {
                        OwnerStatusRow(
                            title: "CI Aktualisiert",
                            detail: "Zeitstempel des Backend-Snapshots",
                            symbol: "clock.arrow.circlepath",
                            value: updatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "CI",
                        detail: "Das Backend hat für dieses Projekt keinen CI-Snapshot geliefert. Das wird nicht mehr als erfolgreicher oder leerer CI-Zustand interpretiert."
                    )
                }

                IOSNextSectionHeader(title: "Letzte Jobs", subtitle: nil, symbol: "clock.arrow.circlepath")
                if snapshot.jobs.isEmpty {
                    OwnerStatusRow(title: "Keine Jobs", detail: "Für dieses Projekt liegt noch kein Dispatch-Job im Snapshot vor.", symbol: "checkmark.circle", value: "0")
                } else {
                    ForEach(Array(snapshot.jobs.prefix(20))) { job in
                        OwnerStatusRow(
                            title: job.ticketID,
                            detail: "Freigegeben von \(job.approvedBy) · \(job.approvedAt.formatted(date: .abbreviated, time: .shortened))",
                            symbol: "paperplane.fill",
                            value: job.state.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                            tint: job.state == "failed" ? .red : .indigo
                        )
                    }
                }
            }
        }
        .navigationTitle(snapshot.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ciTitle(_ state: String?) -> String {
        switch state {
        case "repository_missing": "Kein Repository"
        case "adapter_not_configured": "Nicht eingerichtet"
        case "queued": "Wartet"
        case "in_progress": "Läuft"
        case "success": "Grün"
        case "failure": "Fehlgeschlagen"
        case "cancelled": "Abgebrochen"
        case "no_runs": "Keine Läufe"
        case "unavailable": "Nicht erreichbar"
        default: "Unbekannt"
        }
    }

    private func ciDetail(_ state: String?) -> String {
        switch state {
        case "repository_missing": "Ohne Repository kann kein CI-Status abgefragt werden."
        case "adapter_not_configured": "GitHub-CI ist im Owner Backend noch nicht eingerichtet."
        case "no_runs": "Für dieses Repository wurde noch kein GitHub-Actions-Lauf gemeldet."
        case "unavailable": "GitHub-CI konnte momentan nicht abgefragt werden."
        default: "Letzter vom Backend gelieferter GitHub-Actions-Status"
        }
    }

    private func ciSymbol(_ state: String?) -> String {
        switch state {
        case "success": "checkmark.circle.fill"
        case "failure": "xmark.circle.fill"
        case "queued": "clock.fill"
        case "in_progress": "play.circle.fill"
        case "unavailable": "wifi.exclamationmark"
        default: "hammer.fill"
        }
    }

    private func ciTint(_ state: String?) -> Color {
        switch state {
        case "success": .green
        case "queued", "in_progress": .blue
        case "failure": .red
        case "cancelled", "unavailable": .orange
        default: .secondary
        }
    }
}

struct OwnerLegacyProjectDetailView: View {
    let route: ProjectRoute

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(title: route.title, detail: "Dispatch-Ziel", symbol: "folder.fill", value: route.id)
                if let repository = ProjectRegistry.canonicalRepository(for: route) {
                    OwnerStatusRow(title: "Repository", detail: "Kanonische Fallback-Zuordnung", symbol: "chevron.left.forwardslash.chevron.right", value: repository, tint: .indigo)
                }
                OwnerCapabilityUnavailableView(
                    title: "v2 Projekt-Snapshot",
                    detail: "Der Legacy-Pfad bleibt nur als Fallback aktiv, bis das Owner Backend Repository, Jobs und CI gemeinsam liefert."
                )
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
