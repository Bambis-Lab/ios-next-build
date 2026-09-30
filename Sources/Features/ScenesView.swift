import SwiftUI

struct ScenesView: View {
    let appModel: AppModel

    private var scenes: [HomeAssistantEntity] { appModel.entities(inDomain: "scene") }
    private var scripts: [HomeAssistantEntity] { appModel.entities(inDomain: "script") }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                actionGroup(title: "Szenen", subtitle: "Licht- und Raumstimmungen", entities: scenes, symbol: "circle.hexagongrid.fill", tint: .purple) { entity in
                    await appModel.activate(entity)
                }

                actionGroup(title: "Scripts", subtitle: "Zentrale Abläufe und Master-Aktionen", entities: scripts, symbol: "scroll.fill", tint: .blue) { entity in
                    await appModel.activateScript(entity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle("Szenen")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func actionGroup(
        title: String,
        subtitle: String,
        entities: [HomeAssistantEntity],
        symbol: String,
        tint: Color,
        action: @escaping (HomeAssistantEntity) async -> Void
    ) -> some View {
        IOS27SectionHeader(title: title, subtitle: subtitle)
        if entities.isEmpty {
            EmptyFeatureView(
                title: "Keine \(title) geladen",
                symbol: symbol,
                message: "Home-Assistant-\(title) werden nach der Verbindung hier angezeigt."
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(entities) { entity in
                    Button {
                        Task { await action(entity) }
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: symbol)
                                .font(.headline)
                                .foregroundStyle(tint)
                                .frame(width: 42, height: 42)
                                .background(tint.opacity(0.13), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entity.displayName).font(.subheadline.weight(.semibold))
                                Text(entity.isAvailable ? "Bereit zum Aktivieren" : "Nicht verfügbar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: entity.isAvailable ? "play.fill" : "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(entity.isAvailable ? tint : .secondary)
                        }
                        .padding(14)
                        .ios27ContentSurface(radius: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!entity.isAvailable)
                }
            }
        }
    }
}
