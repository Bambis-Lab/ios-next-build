import SwiftUI

struct EntityDetailView: View {
    let entityID: String
    let appModel: AppModel

    private var entity: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == entityID }
    }

    var body: some View {
        Group {
            if let entity {
                detail(for: entity)
            } else {
                ContentUnavailableView(
                    "Entität nicht mehr verfügbar",
                    systemImage: "questionmark.circle",
                    description: Text(entityID)
                )
            }
        }
        .navigationTitle(entity?.displayName ?? "Gerät")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func detail(for entity: HomeAssistantEntity) -> some View {
        switch entity.domain {
        case "light": LightDetailView(entity: entity, appModel: appModel)
        case "media_player": MediaPlayerDetailView(entity: entity, appModel: appModel)
        case "climate": ClimateDetailView(entity: entity, appModel: appModel)
        case "cover": CoverDetailView(entity: entity, appModel: appModel)
        case "scene": SceneDetailView(entity: entity, appModel: appModel)
        default: GenericEntityDetailView(entity: entity, appModel: appModel)
        }
    }
}

private struct EntityHero: View {
    let entity: HomeAssistantEntity
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(tint.opacity(0.13))
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(entity.isAvailable ? tint : .secondary)
            }
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
            Text(entity.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(entity.stateDisplayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(entity.isAvailable ? Color.secondary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .iosNextCard()
        .accessibilityElement(children: .combine)
    }
}

private struct LightDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel
    @State private var brightness = 0.5

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                EntityHero(entity: entity, symbol: entity.isOn ? "lightbulb.fill" : "lightbulb", tint: .yellow)

                VStack(alignment: .leading, spacing: 18) {
                    IOSNextSectionHeader(title: "Helligkeit", subtitle: "\(Int(brightness * 100)) Prozent", symbol: "sun.max.fill")
                    Slider(value: $brightness, in: 0...1, step: 0.01) { editing in
                        guard !editing else { return }
                        Task { await appModel.setBrightness(brightness, for: entity) }
                    }
                    .disabled(!entity.isAvailable)
                    .accessibilityIdentifier("light-brightness-slider")
                    .accessibilityValue("\(Int(brightness * 100)) Prozent")
                }
                .padding(20)
                .iosNextCard()

                Button(entity.isOn ? "Ausschalten" : "Einschalten", systemImage: "power") {
                    Task { await appModel.toggle(entity) }
                }
                .font(.headline)
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .disabled(!entity.isAvailable || appModel.activeActionEntityIDs.contains(entity.entityID))
                .accessibilityIdentifier("light-power-button")
            }
        }
        .onAppear { brightness = entity.brightness ?? (entity.isOn ? 1 : 0.5) }
        .onChange(of: entity.brightness) { _, value in
            if let value { brightness = value }
        }
    }
}

struct MediaPlayerDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel
    @State private var volume = 0.5

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                mediaHero
                transportControls
                volumeControl
                if let source = entity.source {
                    detailRow(title: "Quelle", value: source, symbol: "dot.radiowaves.left.and.right")
                }
            }
        }
        .onAppear { volume = entity.volumeLevel ?? 0.5 }
        .onChange(of: entity.volumeLevel) { _, value in
            if let value { volume = value }
        }
    }

    private var mediaHero: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.purple.opacity(0.13))
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.purple)
            }
            .frame(width: 132, height: 132)
            .accessibilityHidden(true)
            Text(entity.mediaTitle ?? entity.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let artist = entity.mediaArtist {
                Text(artist).foregroundStyle(.secondary)
            } else {
                Text(entity.stateDisplayName).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .iosNextCard()
        .accessibilityElement(children: .combine)
    }

    private var transportControls: some View {
        HStack(spacing: 18) {
            transportButton("Zurück", symbol: "backward.fill", service: "media_previous_track")
            transportButton("10 Sekunden zurück", symbol: "gobackward.10") {
                seek(relative: -10)
            }
            transportButton(
                entity.state == "playing" ? "Pause" : "Wiedergabe",
                symbol: entity.state == "playing" ? "pause.fill" : "play.fill",
                service: entity.state == "playing" ? "media_pause" : "media_play",
                prominent: true
            )
            transportButton("10 Sekunden vor", symbol: "goforward.10") {
                seek(relative: 10)
            }
            transportButton("Weiter", symbol: "forward.fill", service: "media_next_track")
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .iosNextCard()
    }

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 16) {
            IOSNextSectionHeader(title: "Lautstärke", subtitle: "\(Int(volume * 100)) Prozent", symbol: "speaker.wave.2.fill")
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").accessibilityHidden(true)
                Slider(value: $volume, in: 0...1, step: 0.01) { editing in
                    guard !editing else { return }
                    Task { await appModel.setVolume(volume, for: entity) }
                }
                Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(20)
        .iosNextCard()
    }

    @ViewBuilder
    private func transportButton(
        _ title: String,
        symbol: String,
        service: String? = nil,
        prominent: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        if prominent {
            Button {
                runTransportAction(service: service, action: action)
            } label: {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!entity.isAvailable || appModel.activeActionEntityIDs.contains(entity.entityID))
            .accessibilityLabel(title)
        } else {
            Button {
                runTransportAction(service: service, action: action)
            } label: {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!entity.isAvailable || appModel.activeActionEntityIDs.contains(entity.entityID))
            .accessibilityLabel(title)
        }
    }

    private func runTransportAction(service: String?, action: (() -> Void)?) {
        if let action {
            action()
        } else if let service {
            Task { await appModel.mediaCommand(service, for: entity) }
        }
    }

    private func seek(relative delta: Double) {
        let current = entity.attributes["media_position"]?.numberValue ?? 0
        Task { await appModel.seek(to: current + delta, for: entity) }
    }

    private func detailRow(title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(18)
        .iosNextCard()
    }
}

private struct ClimateDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel
    @State private var target = 21.0

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                EntityHero(entity: entity, symbol: "thermometer.medium", tint: .orange)
                VStack(spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(target, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                        Text("°C").font(.title2).foregroundStyle(.secondary)
                    }
                    Stepper("Zieltemperatur", value: $target, in: 5...35, step: 0.5)
                        .labelsHidden()
                        .onChange(of: target) { _, value in
                            Task { await appModel.setTemperature(value, for: entity) }
                        }
                    if let current = entity.currentTemperature {
                        Text("Aktuell \(current, format: .number.precision(.fractionLength(1))) °C")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .iosNextCard()
            }
        }
        .onAppear { target = entity.temperature ?? 21 }
    }
}

private struct CoverDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel
    @State private var position = 0.5

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                EntityHero(entity: entity, symbol: "window.shade.open", tint: .blue)
                HStack(spacing: 20) {
                    coverButton("Öffnen", symbol: "arrow.up", service: "open_cover")
                    coverButton("Stoppen", symbol: "stop.fill", service: "stop_cover")
                    coverButton("Schließen", symbol: "arrow.down", service: "close_cover")
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .iosNextCard()
                VStack(alignment: .leading, spacing: 16) {
                    IOSNextSectionHeader(title: "Position", subtitle: "\(Int(position * 100)) Prozent")
                    Slider(value: $position, in: 0...1, step: 0.01) { editing in
                        guard !editing else { return }
                        Task { await appModel.setCoverPosition(position, for: entity) }
                    }
                }
                .padding(20)
                .iosNextCard()
            }
        }
        .onAppear { position = (entity.currentPosition ?? 50) / 100 }
    }

    private func coverButton(_ title: String, symbol: String, service: String) -> some View {
        Button {
            Task { await appModel.coverCommand(service, for: entity) }
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
    }
}

private struct SceneDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                EntityHero(entity: entity, symbol: "sparkles", tint: .indigo)
                Button("Szene aktivieren", systemImage: "play.fill") {
                    Task { await appModel.activate(entity) }
                }
                .font(.headline)
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
            }
        }
    }
}

private struct GenericEntityDetailView: View {
    let entity: HomeAssistantEntity
    let appModel: AppModel

    var body: some View {
        IOSNextPage {
            VStack(spacing: IOSNextLayout.pageSpacing) {
                EntityHero(
                    entity: entity,
                    symbol: EntityPresentation.symbol(for: entity.domain)
                )
                VStack(spacing: 0) {
                    detailRow("Entity-ID", entity.entityID)
                    Divider()
                    detailRow("Zustand", entity.stateDisplayName)
                    if let unit = entity.unitOfMeasurement {
                        Divider()
                        detailRow("Einheit", unit)
                    }
                }
                .padding(.horizontal, 18)
                .iosNextCard()

                if ["switch", "input_boolean", "lock"].contains(entity.domain) {
                    Button(primaryActionTitle, systemImage: entity.domain == "lock" ? "lock.fill" : "power") {
                        Task { await appModel.toggle(entity) }
                    }
                    .font(.headline)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!entity.isAvailable)
                }
            }
        }
    }

    private var primaryActionTitle: String {
        if entity.domain == "lock" {
            return entity.state == "locked" ? "Entriegeln" : "Verriegeln"
        }
        return entity.isOn ? "Ausschalten" : "Einschalten"
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 14)
    }
}
