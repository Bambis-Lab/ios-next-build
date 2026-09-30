import SwiftUI
import UIKit

struct LightControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entityID: String
    let appModel: AppModel
    var canTurnOn: Bool = true
    var turnOnBlockedReason: String? = nil

    @State private var selectedColor = Color.white
    @State private var brightness = 1.0
    @State private var colorTemperature = 3000.0
    @State private var favorites: [LightColorFavorite] = []
    @State private var selectedSegments: Set<Int> = []

    private var entity: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == entityID }
    }

    private var segmentBridge: LightSegmentBridgeSnapshot? {
        guard let entity else { return nil }
        return appModel.lightSegmentBridge(for: entity)
    }

    private let palette: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple, .pink, .white
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                IOS27HomeBackground(style: .neutral)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let entity {
                            IOS27StatusCard(
                                title: entity.displayName,
                                value: entity.stateDisplayText,
                                symbol: "lightbulb.fill",
                                tint: entity.ios27LightTint,
                                detail: segmentBridge == nil ? "Lichtsteuerung" : "Lichtsteuerung · Segmente verfügbar"
                            )

                            lightSection(entity)
                            if entity.supportsColor { colorSection(entity) }
                            if let bridge = segmentBridge { segmentSection(entity, bridge: bridge) }
                            if entity.supportsColorTemperature { temperatureSection(entity) }
                            if entity.supportsEffects { effectsSection(entity) }
                        } else {
                            ContentUnavailableView("Licht nicht verfügbar", systemImage: "lightbulb.slash")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .ios27ScrollBottomClearance()
            }
            .navigationTitle(entity?.displayName ?? "Licht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { syncFromEntity() }
            .onChange(of: entity?.state) { _, _ in syncFromEntity() }
            .onChange(of: segmentBridge) { _, bridge in
                if bridge == nil { selectedSegments.removeAll() }
            }
        }
    }

    private func lightSection(_ entity: HomeAssistantEntity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IOS27SectionHeader(title: "Licht", subtitle: selectedSegments.isEmpty ? "Ein/Aus und Helligkeit" : "Ausgewählte Segmente")
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Eingeschaltet", isOn: toggleBinding(entity))
                    .disabled(!entity.isAvailable || (!canTurnOn && !entity.isOn))
                if !canTurnOn, !entity.isOn, let turnOnBlockedReason {
                    Label(turnOnBlockedReason, systemImage: "tv")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if entity.supportsBrightness {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Helligkeit", value: "\(Int(brightness * 100)) %")
                        HStack(spacing: 10) {
                            Image(systemName: "sun.min.fill").foregroundStyle(.secondary)
                            Slider(value: $brightness, in: 0...1) { editing in
                                if !editing { Task { await applyBrightness(entity) } }
                            }
                            .disabled(!entity.isAvailable)
                            Image(systemName: "sun.max.fill").foregroundStyle(entity.ios27LightTint)
                        }
                    }
                }
            }
            .padding(16)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func colorSection(_ entity: HomeAssistantEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IOS27SectionHeader(title: "Farbe", subtitle: selectedSegments.isEmpty ? "Palette und Favoriten" : "Farbe für Segmentauswahl")
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selectedColor.gradient)
                    .frame(height: 84)
                    .overlay(alignment: .bottomLeading) {
                        Text(selectedSegments.isEmpty ? "Gesamtlicht" : "\(selectedSegments.count) Segment(e)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }

                ColorPicker("Lichtfarbe", selection: $selectedColor, supportsOpacity: false)
                    .disabled(!entity.isAvailable)
                    .onChange(of: selectedColor) { _, value in
                        Task { await applyColor(value, entity: entity) }
                    }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(palette.enumerated()), id: \.offset) { _, color in
                            Button { selectedColor = color } label: {
                                Circle().fill(color).frame(width: 38, height: 38)
                                    .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Farbe auswählen")
                        }
                    }
                }

                HStack {
                    Button("Weiß", systemImage: "sun.max.fill") {
                        Task { await applyWhite(entity) }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Favorit sichern", systemImage: "star") {
                        if let rgb = selectedColor.homeAssistantLightColor {
                            favorites = LightColorFavoritesStore.add(rgb, for: entity.entityID)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(favorites.count >= 6)
                }

                if !favorites.isEmpty {
                    Divider()
                    Text("Favoriten").font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(favorites) { favorite in
                                VStack(spacing: 6) {
                                    Button {
                                        selectedColor = Color(
                                            red: favorite.red,
                                            green: favorite.green,
                                            blue: favorite.blue
                                        )
                                    } label: {
                                        Circle()
                                            .fill(Color(red: favorite.red, green: favorite.green, blue: favorite.blue))
                                            .frame(width: 42, height: 42)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        favorites = LightColorFavoritesStore.remove(favorite.id, for: entity.entityID)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func segmentSection(_ entity: HomeAssistantEntity, bridge: LightSegmentBridgeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            IOS27SectionHeader(title: "Segmente", subtitle: bridge.provider.map { "Provider: \($0)" } ?? "Mehrfachauswahl möglich")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Gesamtlicht") { selectedSegments.removeAll() }
                        .buttonStyle(.bordered)
                    Button("Alle Segmente") { selectedSegments = Set(bridge.segmentIndices) }
                        .buttonStyle(.bordered)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(bridge.segmentIndices, id: \.self) { index in
                        Button("\(index + 1)") {
                            if selectedSegments.contains(index) { selectedSegments.remove(index) }
                            else { selectedSegments.insert(index) }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedSegments.contains(index) ? .accentColor : .secondary)
                    }
                }
                if let reason = bridge.reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func temperatureSection(_ entity: HomeAssistantEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IOS27SectionHeader(title: "Farbtemperatur", subtitle: "Warm bis kühl")
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Temperatur", value: "\(Int(colorTemperature)) K")
                Slider(value: $colorTemperature, in: temperatureRange(for: entity), step: 50) { editing in
                    if !editing, entity.isAvailable, selectedSegments.isEmpty {
                        Task { await appModel.setColorTemperatureKelvin(colorTemperature, for: entity) }
                    }
                }
                .disabled(!entity.isAvailable || !selectedSegments.isEmpty)
            }
            .padding(16)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func effectsSection(_ entity: HomeAssistantEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IOS27SectionHeader(title: "Effekte", subtitle: "Vom Gerät gemeldete Effekte")
            VStack(spacing: 0) {
                ForEach(entity.effectList, id: \.self) { effect in
                    Button {
                        Task { await appModel.setEffect(effect, for: entity) }
                    } label: {
                        HStack {
                            Text(effect).foregroundStyle(.primary)
                            Spacer()
                            if entity.currentEffect == effect {
                                Image(systemName: "checkmark").foregroundStyle(entity.ios27LightTint)
                            }
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(!entity.isAvailable || !selectedSegments.isEmpty)
                    if effect != entity.effectList.last { Divider() }
                }
            }
            .padding(.horizontal, 16)
            .ios27ContentSurface(radius: 24)
        }
    }

    private func toggleBinding(_ entity: HomeAssistantEntity) -> Binding<Bool> {
        Binding(
            get: { entity.isOn },
            set: { value in
                guard value != entity.isOn else { return }
                guard !value || canTurnOn else { return }
                guard entity.isAvailable else { return }
                Task { await appModel.toggle(entity) }
            }
        )
    }

    private func applyColor(_ color: Color, entity: HomeAssistantEntity) async {
        guard entity.isAvailable, let rgb = color.homeAssistantLightColor else { return }
        if !selectedSegments.isEmpty, let hs = color.homeAssistantHSColor {
            await appModel.setLightSegments(
                indices: Array(selectedSegments),
                hue: hs.hue,
                saturation: hs.saturation,
                brightness: brightness * 100,
                for: entity
            )
        } else {
            await appModel.setRGBColor(rgb, for: entity)
        }
    }

    private func applyBrightness(_ entity: HomeAssistantEntity) async {
        guard entity.isAvailable else { return }
        if !selectedSegments.isEmpty, let hs = selectedColor.homeAssistantHSColor {
            await appModel.setLightSegments(
                indices: Array(selectedSegments),
                hue: hs.hue,
                saturation: hs.saturation,
                brightness: brightness * 100,
                for: entity
            )
        } else {
            await appModel.setBrightness(brightness, for: entity)
        }
    }

    private func applyWhite(_ entity: HomeAssistantEntity) async {
        selectedColor = .white
        if !selectedSegments.isEmpty {
            await appModel.setLightSegments(
                indices: Array(selectedSegments),
                hue: 0,
                saturation: 0,
                brightness: brightness * 100,
                for: entity
            )
        } else if entity.supportsColorTemperature {
            let range = temperatureRange(for: entity)
            let neutral = min(max(4000, range.lowerBound), range.upperBound)
            colorTemperature = neutral
            await appModel.setColorTemperatureKelvin(neutral, for: entity)
        } else {
            await appModel.setRGBColor(HomeAssistantLightColor(red: 1, green: 1, blue: 1), for: entity)
        }
    }

    private func temperatureRange(for entity: HomeAssistantEntity) -> ClosedRange<Double> {
        let minimum = entity.minColorTemperatureKelvin ?? 2000
        let maximum = entity.maxColorTemperatureKelvin ?? 6500
        return min(minimum, maximum)...max(minimum, maximum)
    }

    private func syncFromEntity() {
        guard let entity else { return }
        brightness = entity.brightnessFraction ?? brightness
        colorTemperature = entity.colorTemperatureKelvin ?? colorTemperature
        favorites = LightColorFavoritesStore.favorites(for: entity.entityID)
        if let color = entity.lightColor {
            selectedColor = Color(red: color.red, green: color.green, blue: color.blue)
        }
    }
}

private extension Color {
    var homeAssistantLightColor: HomeAssistantLightColor? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return HomeAssistantLightColor(red: Double(red), green: Double(green), blue: Double(blue))
    }

    var homeAssistantHSColor: (hue: Double, saturation: Double)? {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return nil }
        return (Double(hue) * 360, Double(saturation) * 100)
    }
}
