import SwiftUI

/// Factory-native Owner routing. The caller MUST pass an already unlocked
/// AdminControlModel; this view never creates or bypasses an Owner session.
struct FactoryOwnerDirectoryView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    let appModel: AppModel?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                IOSNextSectionHeader(
                    title: "Owner & Projekte",
                    subtitle: "Berechtigte Verwaltung ohne Master-Platform-Zwischenebenen",
                    symbol: "person.badge.key.fill"
                )
                destination("Projekte & CI", "Repositories, CI, Workflows und Dispatch",
                            "folder.badge.gearshape") {
                    OwnerProjectsView(model: model, capabilities: capabilities)
                }
                if capabilities.supports(.tickets) {
                    destination("Tickets", "Offene Anfragen, Antworten und Dispatch",
                                "ticket.fill") {
                        OwnerTicketInboxView(model: model)
                    }
                }
                destination("Betrieb", "Backups, Diagnose und Wartung", "wrench.adjustable") {
                    OwnerOperationsView(model: model, capabilities: capabilities)
                }
                destination("Systeme", "Owner-Backend und Infrastruktur", "server.rack") {
                    OwnerSystemsView(model: model, capabilities: capabilities, appModel: appModel)
                }
                destination("Sicherheit", "Gerätebindung, Sitzungen und Audit", "lock.shield.fill") {
                    OwnerSecurityView(model: model, capabilities: capabilities)
                }
                destination("Kommunikation", "Chat Relay und Geräte", "bubble.left.and.bubble.right.fill") {
                    OwnerCommunicationView(model: model, capabilities: capabilities)
                }
                destination("Releases", "Versionen und genehmigte Rollbacks", "shippingbox.fill") {
                    OwnerReleasesView(model: model, capabilities: capabilities)
                }
                OwnerOperationProgressView(model: model)
            }
            .padding(16)
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .accessibilityIdentifier("factory-owner-direct-directory")
        .refreshable { await model.refreshStatusV2() }
    }

    private func destination<Content: View>(
        _ name: String, _ subtitle: String, _ symbol: String,
        @ViewBuilder destination: () -> Content
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(15)
            .ios27ContentSurface(radius: 20)
        }
        .buttonStyle(.plain)
    }
}
