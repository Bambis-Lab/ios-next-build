import SwiftUI

/// Native, intentionally quiet iOS 27 Factory World.
/// ONE shared, frozen Blender camera. Entire city is visible at 100%.
/// No orbiting 3D camera, no invented live packets, no new backend actions.
struct FactoryWorldView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBuilding: BuildingSelection?
    @State private var scale: CGFloat = 1
    @State private var pinchedStartScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var draggedStartOffset: CGSize = .zero
    @State private var showBuildingList = false

    private let pack = FactoryWorldBundle.load()
    private let minimumZoom: CGFloat = 0.85
    private let maximumZoom: CGFloat = 2.5

    private let names: [String: String] = [
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("FACTORY WORLD", systemImage: "building.2.crop.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Master Factory").font(.title2.bold())
                }
                Spacer()
                Text("STADTANSICHT")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let pack {
                let theme = colorScheme == .dark ? "dark" : "light"
                if let composite = FactoryWorldBundle.composite(for: theme) {
                    cityViewport(composite, pack: pack)
                    zoomControls
                    Text("15 Gebäude · maßstabsgetreues Blender-Gesamtbild · keine Live-Simulation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Gebäudeübersicht", isExpanded: $showBuildingList) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                            ForEach(pack.buildings.keys.sorted(), id: \.self) { id in
                                Button {
                                    selectedBuilding = BuildingSelection(id: id)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(id).font(.caption.monospacedDigit())
                                        Text(names[id] ?? id).font(.caption).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(id) – \(names[id] ?? "Factory-Gebäude")")
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.subheadline)
                } else {
                    ContentUnavailableView(
                        "Blender-Gesamtbild nicht installiert",
                        systemImage: "photo",
                        description: Text("Die originale Factory-Welt erscheint, sobald das geprüfte Bildpaket eingebunden ist.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "Factory-Welt wird vorbereitet",
                    systemImage: "building.2",
                    description: Text("Noch kein verifiziertes Blender-Bildpaket enthalten. Die bestehende Factory bleibt unverändert.")
                )
            }
        }
        .padding(16)
        .ios27ContentSurface(radius: 28)
        .sheet(item: $selectedBuilding) { choice in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text(names[choice.id] ?? choice.id).font(.title.bold())
                    Text(choice.id)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Label("Statische Factory-Vorschau", systemImage: "photo")
                        .foregroundStyle(.secondary)
                    Text("Die live animierten Produktionsübergaben werden erst nach verifizierter Datenanbindung ergänzt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
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

    @ViewBuilder
    private func cityViewport(_ image: UIImage, pack: FactoryWorldPack) -> some View {
        let renderWidth = pack.camera.resolution_px[0]
        let renderHeight = pack.camera.resolution_px[1]
        GeometryReader { geometry in
            let viewport = geometry.size
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: viewport.width, height: viewport.height)
                    .accessibilityHidden(true)
                // At normal overview zoom the complete static architecture remains unobstructed.
                // 44pt buttons appear only once there is sufficient screen space.
                if scale >= 1.6 {
                    ForEach(pack.buildings.keys.sorted(), id: \.self) { id in
                        if let p = pack.buildings[id], p.uv_center.count == 2 {
                            Button {
                                selectedBuilding = BuildingSelection(id: id)
                            } label: {
                                Text(id.replacingOccurrences(of: "HB-", with: ""))
                                    .font(.caption2.weight(.bold))
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                                    .overlay(Circle().strokeBorder(.indigo.opacity(0.7), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .position(x: viewport.width * CGFloat(p.uv_center[0]),
                                      y: viewport.height * CGFloat(p.uv_center[1]))
                            .accessibilityLabel("\(id) – \(names[id] ?? "Factory-Gebäude")")
                        }
                    }
                }
            }
            .frame(width: viewport.width, height: viewport.height)
            .scaleEffect(scale)
            .offset(bounded(offset, in: viewport, at: scale))
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let next = clamped(pinchedStartScale * value.magnification)
                        scale = next
                        offset = bounded(offset, in: viewport, at: next)
                    }
                    .onEnded { value in
                        scale = clamped(pinchedStartScale * value.magnification)
                        pinchedStartScale = scale
                        offset = bounded(offset, in: viewport, at: scale)
                        draggedStartOffset = offset
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = bounded(CGSize(width: draggedStartOffset.width + value.translation.width,
                                                height: draggedStartOffset.height + value.translation.height),
                                         in: viewport, at: scale)
                    }
                    .onEnded { _ in
                        draggedStartOffset = offset
                    }
            )
            .onTapGesture(count: 2) { reset() }
            .accessibilityLabel("Statische Gesamtansicht aller 15 Factory-Gebäude")
            .accessibilityHint("Vergrößern oder verkleinern. Gebäude sind auch über die Gebäudeübersicht erreichbar.")
            .accessibilityAddTraits(.isImage)
        }
        .aspectRatio(CGFloat(renderWidth) / CGFloat(renderHeight), contentMode: .fit)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button {
                adjustScale(by: -0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(scale <= minimumZoom)
            .accessibilityLabel("Factory verkleinern")

            Spacer(minLength: 0)
            Text("\(Int((scale * 100).rounded())) %")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Zoom \(Int((scale * 100).rounded())) Prozent")
            Spacer(minLength: 0)

            Button {
                adjustScale(by: 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(scale >= maximumZoom)
            .accessibilityLabel("Factory vergrößern")

            Button {
                reset()
            } label: {
                Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(scale == 1 && offset == .zero)
            .accessibilityLabel("Gesamtansicht wiederherstellen")
        }
    }

    private func adjustScale(by amount: CGFloat) {
        scale = clamped(scale + amount)
        pinchedStartScale = scale
        if scale <= 1 {
            offset = .zero
            draggedStartOffset = .zero
        }
    }

    private func reset() {
        scale = 1
        pinchedStartScale = 1
        offset = .zero
        draggedStartOffset = .zero
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumZoom), maximumZoom)
    }

    private func bounded(_ value: CGSize, in bounds: CGSize, at scale: CGFloat) -> CGSize {
        let x = max(0, (scale - 1) * bounds.width * 0.5)
        let y = max(0, (scale - 1) * bounds.height * 0.5)
        return CGSize(width: min(max(value.width, -x), x),
                      height: min(max(value.height, -y), y))
    }

    private struct BuildingSelection: Identifiable {
        let id: String
    }
}
