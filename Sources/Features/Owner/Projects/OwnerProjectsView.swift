import SwiftUI

struct OwnerProjectsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry

    private var snapshots: [ProjectPresentationSnapshot] {
        model.projectsV2.presentationSnapshots(jobs: model.jobsV2)
    }

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                HStack(spacing: 12) {
                    OwnerMetricView(title: "Projekte", value: "\(projectCount)", symbol: "folder.fill")
                    OwnerMetricView(title: "Offene Tickets", value: "\(model.ownerOpenTicketCount)", symbol: "ticket.fill", tint: model.ownerOpenTicketCount > 0 ? .orange : .green)
                }

                if !model.jobsV2.isEmpty {
                    HStack(spacing: 12) {
                        OwnerMetricView(title: "Jobs", value: "\(model.jobsV2.count)", symbol: "gearshape.2.fill")
                        OwnerMetricView(title: "Aktiv", value: "\(activeJobCount)", symbol: "play.circle.fill", tint: activeJobCount > 0 ? .blue : .green)
                    }
                }

                if capabilities.supports(.tickets) {
                    NavigationLink {
                        OwnerTicketInboxView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Tickets",
                            detail: "Anfragen lesen, beantworten und gezielt dispatchen",
                            symbol: "ticket.fill",
                            value: "\(model.ownerOpenTicketCount) offen",
                            tint: .indigo
                        )
                    }
                    .buttonStyle(.plain)
                }

                IOSNextSectionHeader(
                    title: "Projekte",
                    subtitle: "Ein Snapshot pro Projekt · Repository, Dispatch, Jobs und CI",
                    symbol: "folder.fill"
                )

                if !snapshots.isEmpty {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            OwnerProjectDetailView(snapshot: snapshot)
                        } label: {
                            OwnerStatusRow(
                                title: snapshot.title,
                                detail: snapshot.repository ?? "Kein Repository gemeldet",
                                symbol: "folder.fill",
                                value: projectValue(snapshot),
                                tint: projectTint(snapshot)
                            )
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
                                symbol: "folder.fill",
                                value: "Legacy"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Projekte")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var projectCount: Int {
        snapshots.isEmpty ? model.projectRoutes.count : snapshots.count
    }

    private var activeJobCount: Int {
        model.jobsV2.filter { !["completed", "resolved", "failed"].contains($0.state) }.count
    }

    private func projectValue(_ snapshot: ProjectPresentationSnapshot) -> String {
        if snapshot.activeJobs > 0 { return "\(snapshot.activeJobs) aktiv" }
        guard snapshot.hasCISnapshot else { return "CI nicht geliefert" }
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
