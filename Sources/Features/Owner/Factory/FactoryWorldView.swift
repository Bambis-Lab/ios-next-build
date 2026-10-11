import SwiftUI

/// iOS 27/ iPadOS 27 Factory World. Actual imagery must be packaged from Blender.
/// The UI cannot infer job packets or a live source merely from topology.
struct FactoryWorldView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBuilding: String?
    @State private var zoom: CGFloat = 1
    private let pack = FactoryWorldBundle.load()

    private let labels: [String: String] = [
        "HB-01": "Coordinator Hub", "HB-02": "Hermes Brain",
        "HB-03": "DevMaster Authority", "HB-04": "Worker Orchestrator",
        "HB-05": "Artifact Foundry", "HB-06": "Telemetry Observatory",
        "HB-07": "Integration Gateway", "HB-08": "CI Agent Facility",
        "HB-09": "Verifier Tower", "HB-10": "Approval Center",
        "HB-11": "Skills Workshop", "HB-12": "Memory & Knowledge Archive",
        "HB-13": "Evidence Store", "HB-14": "Audit Chain House",
        "HB-15": "Chat Gateway"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("FACTORY WORLD", systemImage: "building.2.crop.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Deine Factory-Stadt").font(.title2.bold())
                }
                Spacer()
                Text("OFFLINE · 2.5D")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let pack {
                let theme = colorScheme == .dark ? "dark" : "light"
                if let image = FactoryWorldBundle.composite(for: theme) {
                    GeometryReader { geometry in
                        let size = geometry.size
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .accessibilityHidden(true)
                            ForEach(pack.buildings.keys.sorted(), id: \.self) { id in
                                if let place = pack.buildings[id], place.uv_center.count == 2 {
                                    Button {
                                        selectedBuilding = id
                                    } label: {
                                        Circle()
                                            .fill(.regularMaterial)
                                            .overlay {
                                                Text(id.replacingOccurrences(of: "HB-", with: ""))
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.primary)
                                            }
                                            .overlay(Circle().strokeBorder(.indigo.opacity(0.75), lineWidth: 1.2))
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .position(
                                        x: size.width * CGFloat(place.uv_center[0]),
                                        y: size.height * CGFloat(place.uv_center[1])
                                    )
                                    .accessibilityLabel("\(id), \(labels[id] ?? "Factory-Gebäude")")
                                    .accessibilityHint("Öffnet die Gebäudeinformationen ohne Betriebsaktion")
                                }
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(zoom)
                        .gesture(MagnifyGesture()
                            .onChanged { value in
                                zoom = min(3, max(1, value.magnification))
                            })
                    }
                    .aspectRatio(CGFloat(pack.camera.resolution_px[0]) /
                                 CGFloat(pack.camera.resolution_px[1]),
                                 contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    ContentUnavailableView("Blender-Bilder nicht installiert",
                        systemImage: "photo",
                        description: Text("Die echte Factory-Welt wird erst nach der Asset-Abnahme eingebunden."))
                }
                Text("15 Gebäude · Keine Verbindung · Keine simulierten Live-Pakete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if reduceMotion {
                    Text("Animationen reduziert").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Factory World vorbereitet",
                    systemImage: "building.2",
                    description: Text("Das verifizierte Blender-Assetpaket ist noch nicht in dieser App-Version enthalten."))
            }
        }
        .padding(16)
        .ios27ContentSurface(radius: 28)
        .sheet(item: selectedSheet) { building in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(labels[building.id] ?? building.id).font(.title.bold())
                    Text("Gebäude \(building.id)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label("Keine bestätigten Live-Betriebsdaten", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                    Text("Paketbewegungen werden erst bei verifizierten Factory-Übergabeereignissen aktiviert.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .navigationTitle("Factory-Gebäude")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { selectedBuilding = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct Selected: Identifiable {
        let id: String
    }
    private var selectedSheet: Binding<Selected?> {
        Binding(
            get: { selectedBuilding.map { Selected(id: $0) } },
            set: { selectedBuilding = $0?.id }
        )
    }
}
