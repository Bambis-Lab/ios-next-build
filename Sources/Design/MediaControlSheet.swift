import SwiftUI
import UIKit

private struct MediaSheetHeader: View {
    let title: String
    let statusText: String
    let statusSymbol: String
    let statusTint: Color
    let symbol: String
    let accent: Color
    let artworkURL: URL?
    let subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            fallbackArtwork
                        }
                    }
                } else {
                    fallbackArtwork
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Label(statusText, systemImage: statusSymbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var fallbackArtwork: some View {
        Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(accent.opacity(0.12))
    }
}

private struct MediaNowPlayingSurface: View {
    let title: String
    let subtitle: String?
    let detail: String?
    var progress: Double? = nil
    var currentTime: String? = nil
    var duration: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .padding(.top, 4)
                if let currentTime, let duration {
                    HStack {
                        Text(currentTime)
                        Spacer()
                        Text(duration)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ios27ContentSurface(radius: 22)
    }
}

private struct MediaChoiceChip: View {
    let title: String
    let selected: Bool
    let symbol: String?
    var accent: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.82))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(selected ? accent.opacity(0.62) : Color.primary.opacity(0.075), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(selected ? 0.14 : 0.07), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct MediaTransportButton: View {
    let symbol: String
    let label: String
    let accent: Color
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(width: prominent ? 56 : 46, height: prominent ? 56 : 46)
        }
        .ios27GlassButton(prominent: prominent)
        .tint(accent)
        .accessibilityLabel(label)
    }
}

private struct MediaVolumeControl: View {
    let volume: Double?
    let canSetVolume: Bool
    let muted: Bool
    let canMute: Bool
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if canSetVolume, let volume {
                Slider(
                    value: Binding(get: { volume }, set: setVolume),
                    in: 0...1
                )
                .accessibilityLabel("Lautstärke")
                .accessibilityValue("\(Int(volume * 100)) Prozent")
            }
            if canMute {
                Button(action: toggleMute) {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .ios27GlassButton()
                .accessibilityLabel(muted ? "Ton einschalten" : "Stummschalten")
            }
        }
        .padding(16)
        .ios27ContentSurface(radius: 22)
    }
}

private struct FireTVLaunchApp: Identifiable, Hashable {
    let name: String
    let packageName: String

    var id: String { packageName }
}

struct MediaControlSheet: View {
    let entityID: String
    let appModel: AppModel
    var volumePlayerID: String? = nil
    var outputLabel: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var player: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == entityID }
    }

    private var outputPlayer: HomeAssistantEntity? {
        guard let volumePlayerID else { return player }
        return appModel.entities.first { $0.entityID == volumePlayerID } ?? player
    }

    private var usesSeparateOutput: Bool {
        guard let player, let outputPlayer else { return false }
        return player.entityID != outputPlayer.entityID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            mediaHeader(player)
                            if player.isAvailable {
                                nowPlaying(player)
                                timeline(player)
                                transportControls(player)
                                if let outputPlayer, outputPlayer.isAvailable {
                                    volumeControls(outputPlayer)
                                }
                                powerControls(player, outputPlayer: outputPlayer)
                                sourceControls(player, title: "Quelle")
                                if usesSeparateOutput, let outputPlayer, outputPlayer.isAvailable {
                                    sourceControls(outputPlayer, title: "Eingang")
                                }
                                moreFunctions(player, outputPlayer: outputPlayer)
                            } else {
                                IOS27StatusCard(
                                    title: "Nicht verfügbar",
                                    value: "Player derzeit nicht erreichbar",
                                    symbol: "exclamationmark.triangle.fill",
                                    tint: .orange,
                                    detail: "Steueraktionen sind deaktiviert."
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .ios27ScrollBottomClearance()
                    .background(IOS27HomeBackground(style: mediaBackgroundStyle(for: player)))
                } else {
                    ContentUnavailableView("Player nicht verfügbar", systemImage: "play.slash")
                }
            }
            .navigationTitle("Medien")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func mediaHeader(_ player: HomeAssistantEntity) -> some View {
        let artworkURL = player.mediaImageURL.flatMap { URL(string: $0) }
        return MediaSheetHeader(
            title: player.displayName,
            statusText: player.stateDisplayText,
            statusSymbol: player.state == "playing" ? "play.fill" : "circle.fill",
            statusTint: player.state == "playing" ? .green : .secondary,
            symbol: player.iconName,
            accent: .blue,
            artworkURL: artworkURL,
            subtitle: nil
        )
    }

    private func nowPlaying(_ player: HomeAssistantEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IOS27SectionHeader(
                title: "Jetzt läuft",
                subtitle: usesSeparateOutput ? "Ausgabe über \(resolvedOutputLabel)" : nil
            )
            MediaNowPlayingSurface(
                title: player.mediaTitle ?? player.stateDisplayText,
                subtitle: player.mediaArtist,
                detail: player.source
            )
        }
    }

    @ViewBuilder
    private func timeline(_ player: HomeAssistantEntity) -> some View {
        if player.supportsSeek,
           let duration = player.mediaDuration,
           duration > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Slider(
                    value: Binding(
                        get: { min(max(player.mediaPosition ?? 0, 0), duration) },
                        set: { value in Task { await appModel.seek(to: value, for: player) } }
                    ),
                    in: 0...duration
                )
                .accessibilityLabel("Wiedergabeposition")

                HStack {
                    Text(formatTime(player.mediaPosition ?? 0))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .ios27ContentSurface(radius: 22)
        }
    }

    @ViewBuilder
    private func transportControls(_ player: HomeAssistantEntity) -> some View {
        if player.supportsPreviousTrack || player.supportsPlay || player.supportsPause || player.supportsNextTrack || player.supportsSeek || player.supportsStop {
            VStack(alignment: .leading, spacing: 12) {
                IOS27SectionHeader(title: "Wiedergabe")
                IOS27GlassControlGroup(spacing: 18) {
                    HStack(spacing: 18) {
                        if player.supportsPreviousTrack {
                            mediaButton("backward.end.fill", "Zurück", "media_previous_track", player)
                        }
                        if player.supportsPlay || player.supportsPause {
                            mediaButton(
                                player.state == "playing" ? "pause.fill" : "play.fill",
                                player.state == "playing" ? "Pause" : "Play",
                                player.state == "playing" ? "media_pause" : "media_play",
                                player,
                                prominent: true
                            )
                        }
                        if player.supportsNextTrack {
                            mediaButton("forward.end.fill", "Weiter", "media_next_track", player)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { secondaryTransportControls(player) }
                    VStack(alignment: .leading, spacing: 10) { secondaryTransportControls(player) }
                }
            }
        }
    }

    @ViewBuilder
    private func secondaryTransportControls(_ player: HomeAssistantEntity) -> some View {
        if player.supportsSeek {
            MediaChoiceChip(title: "−10 s", selected: false, symbol: "gobackward.10") {
                Task { await appModel.seekRelative(-10, for: player) }
            }
            MediaChoiceChip(title: "+10 s", selected: false, symbol: "goforward.10") {
                Task { await appModel.seekRelative(10, for: player) }
            }
        }
        if player.supportsStop {
            MediaChoiceChip(title: "Stop", selected: false, symbol: "stop.fill") {
                Task { await appModel.callService(for: player, service: "media_stop") }
            }
        }
    }

    @ViewBuilder
    private func volumeControls(_ player: HomeAssistantEntity) -> some View {
        if player.supportsVolumeSet || player.supportsVolumeMute {
            VStack(alignment: .leading, spacing: 12) {
                IOS27SectionHeader(
                    title: "Lautstärke",
                    subtitle: usesSeparateOutput ? resolvedOutputLabel : nil
                )
                MediaVolumeControl(
                    volume: player.volumeLevel,
                    canSetVolume: player.supportsVolumeSet,
                    muted: player.isMuted == true,
                    canMute: player.supportsVolumeMute,
                    setVolume: { value in Task { await appModel.setVolume(value, for: player) } },
                    toggleMute: {
                        Task {
                            await appModel.callService(
                                for: player,
                                service: "volume_mute",
                                data: ["is_volume_muted": player.isMuted != true]
                            )
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func powerControls(
        _ player: HomeAssistantEntity,
        outputPlayer: HomeAssistantEntity?
    ) -> some View {
        let outputHasPower = outputPlayer.map { $0.supportsTurnOn || $0.supportsTurnOff } ?? false
        if player.supportsTurnOn || player.supportsTurnOff || (usesSeparateOutput && outputHasPower) {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Power")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        powerButton(for: player, label: "Player")
                        if usesSeparateOutput, let outputPlayer {
                            powerButton(for: outputPlayer, label: resolvedOutputLabel)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        powerButton(for: player, label: "Player")
                        if usesSeparateOutput, let outputPlayer {
                            powerButton(for: outputPlayer, label: resolvedOutputLabel)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func powerButton(for player: HomeAssistantEntity, label: String) -> some View {
        if player.isOn, player.supportsTurnOff {
            MediaChoiceChip(title: "\(label) aus", selected: false, symbol: "power") {
                Task { await appModel.callService(for: player, service: "turn_off") }
            }
        } else if !player.isOn, player.supportsTurnOn {
            MediaChoiceChip(title: "\(label) an", selected: false, symbol: "power") {
                Task { await appModel.callService(for: player, service: "turn_on") }
            }
        }
    }

    @ViewBuilder
    private func sourceControls(_ player: HomeAssistantEntity, title: String) -> some View {
        if player.supportsSourceSelection && !player.sourceList.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(player.sourceList, id: \.self) { source in
                            sourceButton(source, for: player)
                        }
                    }
                }
            }
        }
    }

    private func sourceButton(_ source: String, for player: HomeAssistantEntity) -> some View {
        MediaChoiceChip(
            title: source,
            selected: player.source == source,
            symbol: player.source == source ? "checkmark" : nil
        ) {
            selectSource(source, for: player)
        }
    }

    private func selectSource(_ source: String, for player: HomeAssistantEntity) {
        Task {
            await appModel.callService(
                for: player,
                service: "select_source",
                data: ["source": source]
            )
        }
    }

    private func moreFunctions(
        _ player: HomeAssistantEntity,
        outputPlayer: HomeAssistantEntity?
    ) -> some View {
        DisclosureGroup("Weitere Funktionen") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Status", value: player.stateDisplayText)
                if let source = player.source, !source.isEmpty {
                    LabeledContent("Quelle", value: source)
                }
                if usesSeparateOutput, let outputPlayer {
                    LabeledContent("Ausgabe", value: resolvedOutputLabel)
                    LabeledContent("Ausgabe-Status", value: outputPlayer.stateDisplayText)
                }
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .padding(14)
        .ios27ContentSurface(radius: 22)
    }

    private var resolvedOutputLabel: String {
        if let outputLabel, !outputLabel.isEmpty { return outputLabel }
        return outputPlayer?.displayName ?? "Ausgabe"
    }
    private func mediaBackgroundStyle(for player: HomeAssistantEntity) -> IOS27AmbientBackgroundStyle {
        let isNicoSystem = player.entityID.contains("nico_zimmer") || volumePlayerID == "media_player.denon_avr_x1300w"
        return isNicoSystem ? .nico(mediaActive: player.state == "playing") : .home
    }


    private func mediaButton(
        _ symbol: String,
        _ label: String,
        _ service: String,
        _ player: HomeAssistantEntity,
        prominent: Bool = false
    ) -> some View {
        MediaTransportButton(
            symbol: symbol,
            label: label,
            accent: .blue,
            prominent: prominent
        ) {
            Task { await appModel.callService(for: player, service: service) }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct FireTVCompanionControlSheet: View {
    let entityID: String
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var packageName = ""

    private var player: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == entityID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            header(player)
                            if player.isAvailable {
                                nowPlaying(player)
                                transport(player)
                                volume(player)
                                power(player)
                                queue(player)
                                appLauncher(player)
                                remote(player)
                            } else {
                                IOS27StatusCard(
                                    title: "Nicht verfügbar",
                                    value: "Fire TV derzeit nicht erreichbar",
                                    symbol: "tv.slash",
                                    tint: .orange,
                                    detail: "Wake-, Wiedergabe- und Navigationsaktionen sind deaktiviert."
                                )
                            }
                            capabilityDetails(player)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .ios27ScrollBottomClearance()
                    .background(IOS27HomeBackground(style: fireTVBackgroundStyle(for: player)))
                } else {
                    ContentUnavailableView("Fire TV nicht verfügbar", systemImage: "tv.slash")
                }
            }
            .navigationTitle("Fire TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func header(_ player: HomeAssistantEntity) -> some View {
        MediaSheetHeader(
            title: player.displayName,
            statusText: player.stateDisplayText,
            statusSymbol: player.state == "playing" ? "play.fill" : "circle.fill",
            statusTint: player.state == "playing" ? .green : .secondary,
            symbol: "tv.fill",
            accent: .orange,
            artworkURL: nil,
            subtitle: player.companionSupportsForegroundApp ? foregroundApp(player) : nil
        )
    }

    @ViewBuilder
    private func nowPlaying(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsMediaSession || player.mediaTitle != nil {
            let position = player.mediaPosition
            let duration = player.mediaDuration
            let progress: Double? = {
                guard let position, let duration, duration > 0 else { return nil }
                return position / duration
            }()
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Jetzt läuft", subtitle: foregroundApp(player))
                MediaNowPlayingSurface(
                    title: player.mediaTitle ?? player.stateDisplayText,
                    subtitle: player.attributes["media_subtitle"]?.stringValue ?? player.mediaArtist,
                    detail: player.source,
                    progress: progress,
                    currentTime: position.map { formatTime($0) },
                    duration: duration.map { formatTime($0) }
                )
            }
        }
    }

    @ViewBuilder
    private func transport(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsPlayerControl {
            let skip = Int(player.attributes["skip_interval_seconds"]?.numberValue ?? 10)
            VStack(alignment: .leading, spacing: 12) {
                IOS27SectionHeader(title: "Wiedergabe")
                IOS27GlassControlGroup(spacing: 18) {
                    HStack(spacing: 18) {
                        if player.supportsPreviousTrack {
                            mediaAction("gobackward.\(skip)", "\(skip) Sekunden zurück", "media_previous_track", player)
                        }
                        if player.supportsPlay || player.supportsPause {
                            mediaAction(
                                player.state == "playing" ? "pause.fill" : "play.fill",
                                player.state == "playing" ? "Pause" : "Play",
                                player.state == "playing" ? "media_pause" : "media_play",
                                player,
                                prominent: true
                            )
                        }
                        if player.supportsNextTrack {
                            mediaAction("goforward.\(skip)", "\(skip) Sekunden vor", "media_next_track", player)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if player.supportsStop {
                    Button("Stop", systemImage: "stop.fill") {
                        Task { await appModel.callService(for: player, service: "media_stop") }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func volume(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsVolumeControl || player.companionSupportsMuteControl {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Lautstärke")
                MediaVolumeControl(
                    volume: player.volumeLevel,
                    canSetVolume: player.companionSupportsVolumeControl && player.supportsVolumeSet,
                    muted: player.isMuted == true,
                    canMute: player.companionSupportsMuteControl && player.supportsVolumeMute,
                    setVolume: { value in Task { await appModel.setVolume(value, for: player) } },
                    toggleMute: {
                        Task {
                            await appModel.callService(
                                for: player,
                                service: "volume_mute",
                                data: ["is_volume_muted": player.isMuted != true]
                            )
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func power(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsWakeControl || player.companionSupportsStandbyControl || player.companionSupportsPowerControl {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Power")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { powerButtons(player) }
                    VStack(alignment: .leading, spacing: 10) { powerButtons(player) }
                }
            }
        }
    }

    @ViewBuilder
    private func powerButtons(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsWakeControl, player.supportsTurnOn {
            Button("Aufwecken", systemImage: "power") {
                Task { await appModel.callService(for: player, service: "turn_on") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(player.isOn)
        }
        if player.companionSupportsStandbyControl, player.supportsTurnOff {
            Button("Standby", systemImage: "moon.zzz.fill") {
                Task { await appModel.callService(for: player, service: "turn_off") }
            }
            .buttonStyle(.bordered)
            .disabled(!player.isOn)
        }
    }

    @ViewBuilder
    private func remote(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsDirectionalNavigation || player.companionSupportsGlobalNavigation {
            VStack(alignment: .leading, spacing: 12) {
                IOS27SectionHeader(title: "Fernbedienung", subtitle: "D-Pad & globale Navigation")

                if player.companionSupportsDirectionalNavigation {
                    IOS27GlassControlGroup(spacing: 10) {
                        VStack(spacing: 10) {
                            companionAction("chevron.up", "Nach oben", "navigate_up", player)
                            HStack(spacing: 10) {
                                companionAction("chevron.left", "Nach links", "navigate_left", player)
                                companionAction("circle.inset.filled", "OK", "navigate_select", player, prominent: true)
                                companionAction("chevron.right", "Nach rechts", "navigate_right", player)
                            }
                            companionAction("chevron.down", "Nach unten", "navigate_down", player)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if player.companionSupportsGlobalNavigation {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { globalNavigationButtons(player) }
                        VStack(alignment: .leading, spacing: 10) { globalNavigationButtons(player) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func globalNavigationButtons(_ player: HomeAssistantEntity) -> some View {
        companionAction("chevron.backward", "Zurück", "navigate_back", player)
        companionAction("house.fill", "Home", "navigate_home", player, prominent: true)
        companionAction("line.3.horizontal", "Menü", "navigate_menu", player)
        companionAction("rectangle.stack.fill", "Zuletzt", "navigate_recents", player)
    }

    @ViewBuilder
    private func queue(_ player: HomeAssistantEntity) -> some View {
        let size = player.attributes["queue_size"]?.numberValue.map(Int.init)
        let index = player.attributes["queue_index"]?.numberValue.map(Int.init)
        if player.companionSupportsQueueControl, (size ?? 1) > 0 {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Warteschlange", subtitle: queueSubtitle(size: size, index: index))
                HStack(spacing: 10) {
                    MediaChoiceChip(title: "Vorheriger", selected: false, symbol: "backward.end.fill", accent: .orange) {
                        Task { await appModel.callFireTVCompanionService("queue_previous", for: player) }
                    }
                    MediaChoiceChip(title: "Nächster", selected: false, symbol: "forward.end.fill", accent: .orange) {
                        Task { await appModel.callFireTVCompanionService("queue_next", for: player) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appLauncher(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsLaunchApps {
            let apps = launchableApps(player)
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Apps", subtitle: foregroundApp(player))

                if !apps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(apps) { app in
                                MediaChoiceChip(
                                    title: app.name,
                                    selected: player.attributes["foreground_package"]?.stringValue == app.packageName,
                                    symbol: "app.fill",
                                    accent: .orange
                                ) {
                                    Task { await appModel.launchFireTVApp(packageName: app.packageName, for: player) }
                                }
                            }
                        }
                    }
                }

                DisclosureGroup(apps.isEmpty ? "App manuell öffnen" : "Weitere Optionen") {
                    HStack(spacing: 10) {
                        TextField("Paketname", text: $packageName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Öffnen") { launchPackage(player) }
                            .buttonStyle(.bordered)
                            .disabled(packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 10)
                }
                .font(.subheadline.weight(.semibold))
                .padding(14)
                .ios27ContentSurface(radius: 22)
            }
        }
    }

    private func launchableApps(_ player: HomeAssistantEntity) -> [FireTVLaunchApp] {
        var apps: [FireTVLaunchApp] = []

        for key in ["launchable_apps", "installed_apps", "apps", "app_packages"] {
            if let object = player.attributes[key]?.objectValue {
                for (rawKey, rawValue) in object {
                    guard let rawText = rawValue.stringValue else { continue }
                    let package = rawKey.contains(".") ? rawKey : rawText
                    let name = rawKey.contains(".") ? rawText : rawKey
                    guard package.contains(".") else { continue }
                    apps.append(FireTVLaunchApp(name: name, packageName: package))
                }
            }
            if let array = player.attributes[key]?.arrayValue {
                for item in array {
                    if let object = item.objectValue {
                        let package = object["package_name"]?.stringValue ?? object["package"]?.stringValue
                        let name = object["name"]?.stringValue ?? object["label"]?.stringValue
                        if let package, package.contains(".") {
                            apps.append(FireTVLaunchApp(name: name ?? prettyPackageName(package), packageName: package))
                        }
                    } else if let package = item.stringValue, package.contains(".") {
                        apps.append(FireTVLaunchApp(name: prettyPackageName(package), packageName: package))
                    }
                }
            }
        }

        if let package = player.attributes["foreground_package"]?.stringValue, !package.isEmpty {
            let name = player.attributes["foreground_app"]?.stringValue ?? prettyPackageName(package)
            apps.append(FireTVLaunchApp(name: name, packageName: package))
        }

        var seen = Set<String>()
        return apps.filter { seen.insert($0.packageName).inserted }
    }

    private func prettyPackageName(_ package: String) -> String {
        let tail = package.split(separator: ".").last.map(String.init) ?? package
        return tail.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    private func fireTVBackgroundStyle(for player: HomeAssistantEntity) -> IOS27AmbientBackgroundStyle {
        let identity = "\(player.entityID) \(player.displayName)".lowercased()
        if identity.contains("mika") { return .mika }
        if identity.contains("wohnzimmer") || identity.contains("living") { return .wohnzimmer }
        return .home
    }

    private func capabilityDetails(_ player: HomeAssistantEntity) -> some View {
        DisclosureGroup("Geräteinformationen") {
            VStack(alignment: .leading, spacing: 10) {
                if let version = player.companionCapabilityVersion {
                    LabeledContent("Capability-Version", value: "\(version)")
                }
                if let app = foregroundApp(player) {
                    LabeledContent("Aktive App", value: app)
                }
                if let available = player.attributes["accessibility_available"]?.boolValue {
                    LabeledContent("Accessibility", value: available ? "Verfügbar" : "Nicht verfügbar")
                }
                if let power = player.attributes["power_state"]?.stringValue, !power.isEmpty {
                    LabeledContent("Power", value: power)
                }
                capabilityChips(player)
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .padding(14)
        .ios27ContentSurface(radius: 22)
    }

    private func capabilityChips(_ player: HomeAssistantEntity) -> some View {
        let names = capabilityNames(player)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
    }

    private func capabilityNames(_ player: HomeAssistantEntity) -> [String] {
        var result: [String] = []
        if player.companionSupportsPlayerControl { result.append("Player") }
        if player.companionSupportsMediaSession { result.append("Media Session") }
        if player.companionSupportsVolumeControl { result.append("Lautstärke") }
        if player.companionSupportsMuteControl { result.append("Mute") }
        if player.companionSupportsQueueControl { result.append("Queue") }
        if player.companionSupportsForegroundApp { result.append("Foreground App") }
        if player.companionSupportsDirectionalNavigation { result.append("D-Pad") }
        if player.companionSupportsGlobalNavigation { result.append("Navigation") }
        if player.companionSupportsLaunchApps { result.append("App Launch") }
        if player.companionSupportsWakeControl { result.append("Wake") }
        if player.companionSupportsStandbyControl { result.append("Standby") }
        return result
    }

    private func foregroundApp(_ player: HomeAssistantEntity) -> String? {
        if let label = player.attributes["foreground_app"]?.stringValue, !label.isEmpty { return label }
        if let package = player.attributes["foreground_package"]?.stringValue, !package.isEmpty { return package }
        return nil
    }

    private func queueSubtitle(size: Int?, index: Int?) -> String? {
        if let size, let index { return "Eintrag \(index + 1) von \(size)" }
        if let size { return "\(size) Einträge" }
        return nil
    }

    private func launchPackage(_ player: HomeAssistantEntity) {
        let package = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !package.isEmpty else { return }
        Task { await appModel.launchFireTVApp(packageName: package, for: player) }
    }

    private func mediaAction(
        _ symbol: String,
        _ label: String,
        _ service: String,
        _ player: HomeAssistantEntity,
        prominent: Bool = false
    ) -> some View {
        MediaTransportButton(
            symbol: symbol,
            label: label,
            accent: .orange,
            prominent: prominent
        ) {
            Task { await appModel.callService(for: player, service: service) }
        }
    }

    private func companionAction(
        _ symbol: String,
        _ label: String,
        _ service: String,
        _ player: HomeAssistantEntity,
        prominent: Bool = false
    ) -> some View {
        Button {
            Task { await appModel.callFireTVCompanionService(service, for: player) }
        } label: {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(width: prominent ? 56 : 46, height: prominent ? 56 : 46)
        }
        .ios27GlassButton(prominent: prominent)
        .tint(.orange)
        .accessibilityLabel(label)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
