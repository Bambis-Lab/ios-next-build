import SwiftUI

/// Static, synthetic simulator fixture only. This is NOT a real HA login or E2E enrollment.
struct FamilyAcceptanceView: View {
    let profile: HomeProfile

    private var definition: ProfileDefinition { ProfileCatalog.definition(for: profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Testprofil – keine Live-Registrierung", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fam-synthetic-fixture")
                    Text("Willkommen, \(profile.title)")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("fam-profile-title")
                    Text("Deine Geräte bleiben über Räume und Suche erreichbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(definition.roomNames, id: \.self) { room in
                        HStack {
                            Image(systemName: "house")
                            Text(room)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    Label("Member · keine Owner-Verwaltung", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fam-member-only")
                }
                .padding(20)
            }
            .navigationTitle("iOS Next")
        }
    }
}
