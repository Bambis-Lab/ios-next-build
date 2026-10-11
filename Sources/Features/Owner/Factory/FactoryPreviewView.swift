import SwiftUI

/// Safe visual tour before Owner or MCP configuration.
/// No privileged models, Runner commands, credentials or live data.
struct FactoryPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("CONTROL CENTER / FACTORY", systemImage: "network")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Master Factory")
                        .font(.largeTitle.bold())
                    Text("Dein mobiler Factory-Arbeitsbereich – die Oberfläche ist bereits vorhanden. Für echte Betriebsdaten wird eine autorisierte Verbindung benötigt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                FactoryCommandDeck(
                    factoryConnected: false, ownerConnected: false,
                    runnerConnected: false, reportedSources: 0
                )
                Label("Vorschau ohne sensible Daten", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                section("Organisation & Projekte", "Verifizierte Projekt- und Repository-Zuordnung", "folder.badge.gearshape")
                section("CI & Jobs", "Runs, Runner-Belegung und Status", "gearshape.2.fill")
                section("Runner & Infrastruktur", "CPU, Speicher, Mounts und Dienste", "server.rack")
                section("Governance & Diagnose", "Leserechte, Authority und sichere Diagnose", "checkmark.shield.fill")
                Text("Die Vorschau startet keine Netzwerkanfrage. Zum Verbinden zuerst Control Center einrichten, anschließend Factory im entsperrten Owner-Bereich öffnen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Factory Vorschau")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func section(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.fill").foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(17)
        .ios27ContentSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }
}
