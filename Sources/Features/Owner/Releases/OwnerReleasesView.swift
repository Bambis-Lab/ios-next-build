import SwiftUI

struct OwnerReleasesView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    @State private var pendingAction: AdminRemoteAction?
    @State private var pendingReleaseID: String?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                IOSNextSectionHeader(
                    title: "Releases",
                    subtitle: "Installierter Stand, Update-Bereitschaft und Rollback ohne UI-Wildwuchs",
                    symbol: "shippingbox.fill"
                )
                if !model.releasesV2.contains(where: { $0.id == "ios-next" }) {
                    OwnerStatusRow(
                        title: "iOS Next",
                        detail: "Installierte App-Version",
                        symbol: "iphone.gen3",
                        value: appVersion
                    )
                }

                if capabilities.supports(.releaseInventory), !model.releasesV2.isEmpty {
                    ForEach(model.releasesV2) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            OwnerStatusRow(
                                title: release.title,
                                detail: releaseDetail(release),
                                symbol: release.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill",
                                value: release.updateAvailable ? "Update" : "Aktuell",
                                tint: release.updateAvailable ? .orange : .green
                            )
                            if let action = preferredAction(for: release) {
                                Button(action.title, systemImage: action.id == "release.rollback" ? "arrow.uturn.backward.circle" : "arrow.down.circle.fill") {
                                    pendingReleaseID = release.id
                                    pendingAction = actionForDisplay(action)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isLoading)
                            }
                        }
                    }
                    OwnerAlertBanner(
                        title: "Deployments bleiben workflow-gesteuert",
                        message: "Eine Update-Aktion wird erst angeboten, wenn Backup, Teststatus, Migration und Rollback serverseitig vollständig vorbereitet sind.",
                        symbol: "checkmark.shield.fill",
                        tint: .green
                    )
                } else {
                    if let backend = model.backendStatus {
                        OwnerStatusRow(title: "Owner Backend", detail: backend.environment, symbol: "server.rack", value: backend.version)
                    }
                    OwnerCapabilityUnavailableView(
                        title: "Update-Katalog",
                        detail: "Das verbundene Backend liefert noch keine Release-Inventar-Capability."
                    )
                }
            }
        }
        .navigationTitle("Releases")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshStatusV2() }
        .sheet(item: $pendingAction) { displayAction in
            OwnerRemoteActionSheet(action: displayAction, isExecuting: model.isLoading) { parameters in
                guard let releaseID = pendingReleaseID,
                      let action = releaseActions.first(where: { $0.id == displayAction.id }) else { return }
                var resolved = parameters
                resolved["release_id"] = releaseID
                Task { await model.performRemoteActionV2(action, parameters: resolved) }
            }
        }
    }

    private var releaseActions: [AdminRemoteAction] {
        (model.v2Capabilities?.actions ?? []).filter { $0.available && $0.category == "releases" }
    }

    private func preferredAction(for release: AdminReleaseItemV2) -> AdminRemoteAction? {
        if release.updateAvailable { return releaseActions.first(where: { $0.id == "release.deploy" }) }
        if release.rollbackAvailable { return releaseActions.first(where: { $0.id == "release.rollback" }) }
        return nil
    }

    private func actionForDisplay(_ action: AdminRemoteAction) -> AdminRemoteAction {
        AdminRemoteAction(
            id: action.id,
            title: action.title,
            category: action.category,
            risk: action.risk,
            available: action.available,
            requiresBiometrics: action.requiresBiometrics,
            requiresConfirmation: action.requiresConfirmation,
            requiresBreakGlass: action.requiresBreakGlass,
            parameters: action.parameters?.filter { $0.id != "release_id" }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func releaseDetail(_ release: AdminReleaseItemV2) -> String {
        let installed = release.id == "ios-next" ? appVersion : release.installedVersion
        var parts = ["Installiert \(installed)"]
        if let available = release.availableVersion, available != installed, available != release.installedVersion {
            parts.append("verfügbar \(available)")
        }
        if release.rollbackAvailable { parts.append("Rollback vorhanden") }
        if release.testsPassing == true { parts.append("Tests grün") }
        if release.testsPassing == false { parts.append("Tests fehlgeschlagen") }
        if release.id == "ios-next", release.installedVersion != installed {
            parts.append("Backend-Inventar abweichend")
        }
        return parts.joined(separator: " · ")
    }
}
