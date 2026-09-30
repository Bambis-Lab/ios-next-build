import SwiftUI
import UIKit

struct IOS27SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

struct IOS27LightCard: View {
    @State private var showControls = false
    let entity: HomeAssistantEntity
    let appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(entity.ios27LightTint)
                    .frame(width: 42, height: 42)
                    .background(entity.ios27LightTint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entity.displayName).font(.headline)
                    Text(entity.isOn ? "Eingeschaltet" : "Ausgeschaltet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await appModel.toggle(entity) }
                } label: {
                    Image(systemName: "power")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                }
                .ios27GlassButton()
                .tint(entity.ios27LightTint)
                .accessibilityLabel(entity.isOn ? "Ausschalten" : "Einschalten")
                .accessibilityHint("Schaltet \(entity.displayName) um")
            }

            if let brightness = entity.brightness {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: Binding(
                        get: { min(max(brightness, 0), 1) },
                        set: { value in Task { await appModel.setBrightness(value, for: entity) } }
                    ))
                    .accessibilityLabel("Helligkeit")
                    .accessibilityValue("\(Int((brightness) * 100)) Prozent")
                    Image(systemName: "sun.max.fill").foregroundStyle(entity.ios27LightTint).accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .ios27ContentSurface(radius: 24)
        .ios27HoldAction {
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            LightControlSheet(entityID: entity.entityID, appModel: appModel)
        }
    }
}

struct IOS27MediaCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showControls = false
    let player: HomeAssistantEntity
    let appModel: AppModel
    var volumePlayer: HomeAssistantEntity? = nil

    private var effectiveVolumePlayer: HomeAssistantEntity { volumePlayer ?? player }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.13), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.displayName).font(.headline)
                    Text(player.mediaTitle ?? player.stateDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                Spacer()
                Text(player.stateDisplayText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(player.state == "playing" ? .green : .secondary)
            }

            if player.isAvailable && (player.supportsPreviousTrack || player.supportsPlay || player.supportsPause || player.supportsNextTrack) {
                IOS27GlassControlGroup(spacing: 18) {
                    HStack(spacing: 18) {
                        if player.supportsPreviousTrack {
                            mediaButton("backward.end.fill", "Vorheriger Titel", "media_previous_track")
                        }
                        if (player.state == "playing" && player.supportsPause) || (player.state != "playing" && player.supportsPlay) {
                            mediaButton(
                                player.state == "playing" ? "pause.fill" : "play.fill",
                                "Wiedergabe",
                                player.state == "playing" ? "media_pause" : "media_play",
                                prominent: true
                            )
                        }
                        if player.supportsNextTrack {
                            mediaButton("forward.end.fill", "Nächster Titel", "media_next_track")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if player.isAvailable, effectiveVolumePlayer.isAvailable, let volume = effectiveVolumePlayer.volumeLevel {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: Binding(
                        get: { volume },
                        set: { value in Task { await appModel.setVolume(value, for: effectiveVolumePlayer) } }
                    ))
                    .accessibilityLabel("Lautstärke")
                    .accessibilityValue("\(Int(volume * 100)) Prozent")
                    if effectiveVolumePlayer.supportsVolumeMute {
                        Button {
                            Task {
                                await appModel.callService(
                                    for: effectiveVolumePlayer,
                                    service: "volume_mute",
                                    data: ["is_volume_muted": effectiveVolumePlayer.isMuted != true]
                                )
                            }
                        } label: {
                            Image(systemName: effectiveVolumePlayer.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .ios27GlassButton()
                        .accessibilityLabel(effectiveVolumePlayer.isMuted == true ? "Ton einschalten" : "Stummschalten")
                    }
                }
            }
        }
        .padding(16)
        .ios27ContentSurface(radius: 24)
        .contentShape(Rectangle())
        .ios27HoldAction {
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            if appModel.isFireTVCompanion(player) {
                FireTVCompanionControlSheet(entityID: player.entityID, appModel: appModel)
            } else {
                MediaControlSheet(
                    entityID: player.entityID,
                    appModel: appModel,
                    volumePlayerID: volumePlayer?.entityID,
                    outputLabel: volumePlayer?.displayName
                )
            }
        }
    }

    private func mediaButton(_ symbol: String, _ label: String, _ service: String, prominent: Bool = false) -> some View {
        Button {
            Task { await appModel.callService(for: player, service: service) }
        } label: {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(width: prominent ? 54 : 44, height: prominent ? 54 : 44)
        }
        .ios27GlassButton(prominent: prominent)
        .tint(.blue)
        .accessibilityLabel(label)
        .disabled(!player.isAvailable)
    }
}

struct IOS27StatusCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var detail: String? = nil

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 13))
        layout {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(value).font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption2).foregroundStyle(colorSchemeContrast == .increased ? .secondary : .tertiary) }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        }
        .padding(14)
        .ios27ContentSurface(radius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

struct IOS27MediaZoneCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPlayerID: String?

    let title: String
    let subtitle: String
    let players: [HomeAssistantEntity]
    let masterState: HomeAssistantEntity?
    let masterScript: HomeAssistantEntity?
    let appModel: AppModel
    var coupledPlaybackPlayerID: String? = nil
    var coupledOutputPlayerID: String? = nil
    var playerNameOverrides: [String: String] = [:]

    private var coupledPlaybackPlayer: HomeAssistantEntity? {
        guard let coupledPlaybackPlayerID else { return nil }
        return players.first { $0.entityID == coupledPlaybackPlayerID }
    }

    private var coupledOutputPlayer: HomeAssistantEntity? {
        guard let coupledOutputPlayerID else { return nil }
        return players.first { $0.entityID == coupledOutputPlayerID }
    }

    private var secondaryPlayers: [HomeAssistantEntity] {
        players.filter {
            $0.entityID != coupledPlaybackPlayerID && $0.entityID != coupledOutputPlayerID
        }
    }

    private var zonePowered: Bool {
        masterState?.isOn ?? players.contains(where: \.isOn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            headerLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if let masterState {
                    HStack(spacing: 5) {
                        Image(systemName: masterState.isOn ? "dot.radiowaves.left.and.right" : "moon.fill")
                            .foregroundStyle(masterState.isOn ? Color.green : Color.indigo)
                        Text(masterState.isOn ? "Aktiv" : "Bereit")
                            .foregroundStyle(masterState.isOn ? Color.green : Color.secondary)
                    }
                    .font(.caption2.weight(.semibold))
                }
            }

            if let playback = coupledPlaybackPlayer, let output = coupledOutputPlayer {
                VStack(spacing: 0) {
                    playerRow(
                        playback,
                        role: "Wiedergabe",
                        detail: playback.mediaTitle ?? playback.stateDisplayText
                    )
                    Divider().padding(.leading, 46)
                    playerRow(
                        output,
                        role: "Ausgabe",
                        detail: outputDetail(output)
                    )
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if zonePowered {
                    transportControls(playback)
                    volumeControls(output)
                }

                if !secondaryPlayers.isEmpty {
                    Text("Separat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(secondaryPlayers) { player in
                        playerRow(player, role: nil, detail: player.mediaTitle ?? player.stateDisplayText)
                    }
                }
            } else {
                ForEach(players) { player in
                    playerRow(player, role: nil, detail: player.mediaTitle ?? player.stateDisplayText)
                }
            }

            if let masterScript {
                Button {
                    Task { await appModel.activateScript(masterScript) }
                } label: {
                    Label(zonePowered ? "Alle Medien ausschalten" : "Alle Medien anschalten", systemImage: "power.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .ios27GlassButton(prominent: true)
                .tint(.blue)
            }
        }
        .padding(18)
        .ios27ContentSurface(radius: 28, elevated: true)
        .sheet(isPresented: Binding(
            get: { selectedPlayerID != nil },
            set: { if !$0 { selectedPlayerID = nil } }
        )) {
            if let id = selectedPlayerID, let selected = players.first(where: { $0.entityID == id }) {
                if appModel.isFireTVCompanion(selected) {
                    FireTVCompanionControlSheet(entityID: id, appModel: appModel)
                } else {
                    MediaControlSheet(
                        entityID: id,
                        appModel: appModel,
                        volumePlayerID: id == coupledPlaybackPlayerID ? coupledOutputPlayerID : nil,
                        outputLabel: id == coupledPlaybackPlayerID
                            ? coupledOutputPlayer.map { playerNameOverrides[$0.entityID] ?? $0.displayName }
                            : nil
                    )
                }
            }
        }
    }

    private func playerRow(_ player: HomeAssistantEntity, role: String?, detail: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 11))
        return layout {
            Image(systemName: player.iconName)
                .foregroundStyle(player.state == "playing" ? .blue : .secondary)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(player.state == "playing" ? 0.14 : 0.06), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(playerNameOverrides[player.entityID] ?? player.displayName)
                    .font(.subheadline.weight(.semibold))
                Text([role, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text(player.stateDisplayText)
                .font(.caption2)
                .foregroundStyle(colorSchemeContrast == .increased ? .secondary : .tertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .ios27HoldAction { selectedPlayerID = player.entityID }
    }

    private func outputDetail(_ player: HomeAssistantEntity) -> String {
        var values: [String] = []
        if let source = player.source, !source.isEmpty { values.append(source) }
        if let volume = player.volumeLevel { values.append("\(Int((volume * 100).rounded())) %") }
        return values.isEmpty ? player.stateDisplayText : values.joined(separator: " · ")
    }

    @ViewBuilder
    private func transportControls(_ player: HomeAssistantEntity) -> some View {
        if player.isAvailable && (player.supportsPreviousTrack || player.supportsPlay || player.supportsPause || player.supportsNextTrack) {
            IOS27GlassControlGroup(spacing: 18) {
                HStack(spacing: 18) {
                    if player.supportsPreviousTrack {
                        zoneMediaButton("backward.end.fill", "Vorheriger Titel", "media_previous_track", player)
                    }
                    if (player.state == "playing" && player.supportsPause) || (player.state != "playing" && player.supportsPlay) {
                        zoneMediaButton(
                            player.state == "playing" ? "pause.fill" : "play.fill",
                            "Wiedergabe",
                            player.state == "playing" ? "media_pause" : "media_play",
                            player,
                            prominent: true
                        )
                    }
                    if player.supportsNextTrack {
                        zoneMediaButton("forward.end.fill", "Nächster Titel", "media_next_track", player)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func volumeControls(_ player: HomeAssistantEntity) -> some View {
        if player.isAvailable && (player.supportsVolumeSet || player.supportsVolumeMute) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(playerNameOverrides[player.entityID] ?? player.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let volume = player.volumeLevel {
                        Text("\(Int((volume * 100).rounded())) %")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    if player.supportsVolumeSet, let volume = player.volumeLevel {
                        Slider(value: Binding(
                            get: { volume },
                            set: { value in Task { await appModel.setVolume(value, for: player) } }
                        ))
                        .accessibilityLabel("Lautstärke \(playerNameOverrides[player.entityID] ?? player.displayName)")
                        .accessibilityValue("\(Int(volume * 100)) Prozent")
                    }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    if player.supportsVolumeMute {
                        Button {
                            Task {
                                await appModel.callService(
                                    for: player,
                                    service: "volume_mute",
                                    data: ["is_volume_muted": player.isMuted != true]
                                )
                            }
                        } label: {
                            Image(systemName: player.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .ios27GlassButton()
                        .accessibilityLabel(player.isMuted == true ? "Ton einschalten" : "Stummschalten")
                    }
                }
            }
        }
    }

    private func zoneMediaButton(
        _ symbol: String,
        _ label: String,
        _ service: String,
        _ player: HomeAssistantEntity,
        prominent: Bool = false
    ) -> some View {
        Button {
            Task { await appModel.callService(for: player, service: service) }
        } label: {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(width: prominent ? 54 : 44, height: prominent ? 54 : 44)
        }
        .ios27GlassButton(prominent: prominent)
        .tint(.blue)
        .accessibilityLabel(label)
        .disabled(!player.isAvailable)
    }
}

struct IOS27FireTVCompanionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var showControls = false
    let player: HomeAssistantEntity
    let appModel: AppModel

    private var companionSubtitle: String {
        if player.companionSupportsForegroundApp,
           let app = player.attributes["foreground_app"]?.stringValue,
           !app.isEmpty {
            return app
        }
        return player.mediaTitle ?? player.stateDisplayText
    }

    private var hasPrimaryControls: Bool {
        player.isAvailable && ((player.companionSupportsStandbyControl && player.isOn && player.supportsTurnOff)
            || (player.companionSupportsWakeControl && !player.isOn && player.supportsTurnOn)
            || (player.companionSupportsPlayerControl
                && (player.supportsPreviousTrack || player.supportsPlay || player.supportsPause || player.supportsNextTrack)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 13))
            headerLayout {
                Image(systemName: "tv.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.displayName).font(.title3.weight(.bold))
                    Text(companionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                if differentiateWithoutColor {
                    Image(systemName: player.isAvailable ? (player.isOn ? "checkmark.circle.fill" : "minus.circle.fill") : "exclamationmark.triangle.fill")
                        .foregroundStyle(player.isAvailable ? (player.isOn ? .green : .secondary) : .red)
                        .accessibilityLabel(player.isAvailable ? (player.isOn ? "Aktiv" : "Inaktiv") : "Nicht verfügbar")
                } else {
                    Circle()
                        .fill(player.isAvailable ? (player.isOn ? Color.green : Color.secondary) : Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(player.isAvailable ? (player.isOn ? "Aktiv" : "Inaktiv") : "Nicht verfügbar")
                }
            }

            if hasPrimaryControls {
                IOS27GlassControlGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        if player.isOn,
                           player.companionSupportsStandbyControl,
                           player.supportsTurnOff {
                            companionButton("moon.zzz.fill", "Standby") {
                                Task { await appModel.callService(for: player, service: "turn_off") }
                            }
                        } else if !player.isOn,
                                  player.companionSupportsWakeControl,
                                  player.supportsTurnOn {
                            companionButton("power", "Aufwecken") {
                                Task { await appModel.callService(for: player, service: "turn_on") }
                            }
                        }
                        if player.companionSupportsPlayerControl, player.supportsPreviousTrack {
                            companionButton("gobackward.10", "10 Sekunden zurück") {
                                Task { await appModel.callService(for: player, service: "media_previous_track") }
                            }
                        }
                        if player.companionSupportsPlayerControl,
                           (player.state == "playing" && player.supportsPause)
                            || (player.state != "playing" && player.supportsPlay) {
                            companionButton(player.state == "playing" ? "pause.fill" : "play.fill", "Wiedergabe", prominent: true) {
                                Task { await appModel.callService(for: player, service: player.state == "playing" ? "media_pause" : "media_play") }
                            }
                        }
                        if player.companionSupportsPlayerControl, player.supportsNextTrack {
                            companionButton("goforward.10", "10 Sekunden vor") {
                                Task { await appModel.callService(for: player, service: "media_next_track") }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Verfügbar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { verifiedCapabilityLabels }
                    VStack(alignment: .leading, spacing: 8) { verifiedCapabilityLabels }
                }
            }

            if player.isAvailable, player.supportsVolumeSet, let volume = player.volumeLevel {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: Binding(
                        get: { volume },
                        set: { value in Task { await appModel.setVolume(value, for: player) } }
                    ))
                    .accessibilityLabel("Lautstärke")
                    .accessibilityValue("\(Int(volume * 100)) Prozent")
                    if player.companionSupportsMuteControl, player.supportsVolumeMute {
                        Button {
                            Task { await appModel.callService(for: player, service: "volume_mute", data: ["is_volume_muted": player.isMuted != true]) }
                        } label: {
                            Image(systemName: player.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .ios27GlassButton()
                        .accessibilityLabel(player.isMuted == true ? "Ton einschalten" : "Stummschalten")
                    }
                }
            }
        }
        .padding(18)
        .ios27ContentSurface(radius: 28, elevated: true)
        .contentShape(Rectangle())
        .ios27HoldAction {
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            FireTVCompanionControlSheet(entityID: player.entityID, appModel: appModel)
        }
    }

    private func companionButton(_ symbol: String, _ label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(width: prominent ? 52 : 44, height: prominent ? 52 : 44)
        }
        .ios27GlassButton(prominent: prominent)
        .tint(.orange)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var verifiedCapabilityLabels: some View {
        if player.companionSupportsPlayerControl && (player.supportsPlay || player.supportsPause) { capabilityLabel("Player", "play.fill") }
        if player.companionSupportsPlayerControl && player.supportsSeek { capabilityLabel("±10 s", "goforward.10") }
        if player.companionSupportsVolumeControl && player.supportsVolumeSet { capabilityLabel("Lautstärke", "speaker.wave.2.fill") }
        if player.companionSupportsMuteControl && player.supportsVolumeMute { capabilityLabel("Mute", "speaker.slash.fill") }
    }

    private func capabilityLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Unterstützt: \(text)")
    }
}
