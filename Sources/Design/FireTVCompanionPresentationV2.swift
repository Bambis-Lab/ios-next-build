import SwiftUI

private struct FireTVUserApp: Identifiable, Hashable {
    let name: String
    let package: String
    var id: String { package }
}

struct IOS27FireTVCompanionCardV2: View {
    let player: HomeAssistantEntity
    let appModel: AppModel
    @State private var showControls = false

    private var presentationState: FireTVPresentationState {
        FireTVPresentationState.resolve(entity: player)
    }

    private var subtitle: String {
        FireTVPresentationPolicy.visibleForegroundApp(for: player)
            ?? player.mediaTitle.flatMap { FireTVPresentationPolicy.isSystemIdentity($0) ? nil : $0 }
            ?? player.stateDisplayText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                Image(systemName: "tv.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.displayName).font(.title3.weight(.bold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(player.isAvailable ? (player.isOn ? Color.green : Color.secondary) : Color.red)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 10) {
                if presentationState == .off || presentationState == .standby {
                    if player.companionSupportsWakeControl && player.supportsTurnOn {
                        Button("Aufwecken", systemImage: "power") {
                            Task { await appModel.callService(for: player, service: "turn_on") }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if player.companionSupportsStandbyControl && player.supportsTurnOff {
                    Button("Standby", systemImage: "moon.zzz.fill") {
                        Task { await appModel.callService(for: player, service: "turn_off") }
                    }
                    .buttonStyle(.bordered)
                }

                if FireTVPresentationPolicy.shouldShowTransport(for: player), player.supportsPlay || player.supportsPause {
                    Button(player.state == "playing" ? "Pause" : "Play", systemImage: player.state == "playing" ? "pause.fill" : "play.fill") {
                        Task { await appModel.callService(for: player, service: player.state == "playing" ? "media_pause" : "media_play") }
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                capability("Player", enabled: player.companionSupportsPlayerControl)
                capability("Media Session", enabled: player.companionSupportsMediaSession)
                capability("App Launch", enabled: player.companionSupportsLaunchApps)
            }
        }
        .padding(18)
        .ios27ContentSurface(radius: 28, elevated: true)
        .contentShape(Rectangle())
        .ios27HoldAction { showControls = true }
        .sheet(isPresented: $showControls) {
            FireTVCompanionControlSheetV2(entityID: player.entityID, appModel: appModel)
        }
    }

    @ViewBuilder
    private func capability(_ name: String, enabled: Bool) -> some View {
        if enabled {
            Text(name)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }
}

struct FireTVCompanionControlSheetV2: View {
    let entityID: String
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
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
                                apps(player)
                                remote(player)
                            } else {
                                IOS27StatusCard(title: "Nicht verfügbar", value: "Fire TV derzeit nicht erreichbar", symbol: "tv.slash", tint: .orange, detail: "Steueraktionen sind deaktiviert.")
                            }
                            deviceInfo(player)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .ios27ScrollBottomClearance()
                    .background(IOS27HomeBackground())
                } else {
                    ContentUnavailableView("Fire TV nicht verfügbar", systemImage: "tv.slash")
                }
            }
            .navigationTitle("Fire TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func header(_ player: HomeAssistantEntity) -> some View {
        let state = FireTVPresentationState.resolve(entity: player)
        return HStack(spacing: 14) {
            Image(systemName: "tv.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 72, height: 72)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(player.displayName).font(.title3.weight(.bold))
                Text(stateText(state)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let app = FireTVPresentationPolicy.visibleForegroundApp(for: player) {
                    Text(app).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func nowPlaying(_ player: HomeAssistantEntity) -> some View {
        if FireTVPresentationPolicy.shouldShowNowPlaying(for: player) {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Jetzt läuft", subtitle: FireTVPresentationPolicy.visibleForegroundApp(for: player))
                VStack(alignment: .leading, spacing: 6) {
                    Text(cleanMediaTitle(player)).font(.headline.weight(.semibold))
                    if let artist = player.mediaArtist, !artist.isEmpty, !FireTVPresentationPolicy.isSystemIdentity(artist) {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let source = player.source, !source.isEmpty, !FireTVPresentationPolicy.isSystemIdentity(source) {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .ios27ContentSurface(radius: 22)
            }
        }
    }

    @ViewBuilder
    private func transport(_ player: HomeAssistantEntity) -> some View {
        if FireTVPresentationPolicy.shouldShowTransport(for: player) {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Wiedergabe")
                HStack(spacing: 12) {
                    if player.supportsPreviousTrack { action("gobackward.10", "Zurück") { Task { await appModel.callService(for: player, service: "media_previous_track") } } }
                    if player.supportsPlay || player.supportsPause { action(player.state == "playing" ? "pause.fill" : "play.fill", player.state == "playing" ? "Pause" : "Play") { Task { await appModel.callService(for: player, service: player.state == "playing" ? "media_pause" : "media_play") } } }
                    if player.supportsNextTrack { action("goforward.10", "Weiter") { Task { await appModel.callService(for: player, service: "media_next_track") } } }
                }
            }
        }
    }

    @ViewBuilder
    private func volume(_ player: HomeAssistantEntity) -> some View {
        let state = FireTVPresentationState.resolve(entity: player)
        if state != .off, state != .standby, state != .unavailable, player.companionSupportsVolumeControl, player.supportsVolumeSet, let level = player.volumeLevel {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Lautstärke")
                Slider(value: Binding(get: { level }, set: { value in Task { await appModel.setVolume(value, for: player) } }))
            }
            .padding(16)
            .ios27ContentSurface(radius: 22)
        }
    }

    @ViewBuilder
    private func power(_ player: HomeAssistantEntity) -> some View {
        let state = FireTVPresentationState.resolve(entity: player)
        VStack(alignment: .leading, spacing: 10) {
            IOS27SectionHeader(title: "Power")
            HStack(spacing: 10) {
                if (state == .off || state == .standby), player.companionSupportsWakeControl, player.supportsTurnOn {
                    Button("Aufwecken", systemImage: "power") { Task { await appModel.callService(for: player, service: "turn_on") } }.buttonStyle(.borderedProminent)
                }
                if state != .off, state != .standby, state != .unavailable, player.companionSupportsStandbyControl, player.supportsTurnOff {
                    Button("Standby", systemImage: "moon.zzz.fill") { Task { await appModel.callService(for: player, service: "turn_off") } }.buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func apps(_ player: HomeAssistantEntity) -> some View {
        if player.companionSupportsLaunchApps {
            let visibleApps = launchableApps(player)
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Apps", subtitle: FireTVPresentationPolicy.visibleForegroundApp(for: player))
                if !visibleApps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(visibleApps) { app in
                                Button(app.name, systemImage: "app.fill") { Task { await appModel.launchFireTVApp(packageName: app.package, for: player) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                DisclosureGroup(visibleApps.isEmpty ? "App manuell öffnen" : "Weitere Optionen") {
                    HStack {
                        TextField("Paketname", text: $packageName).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        Button("Öffnen") {
                            let value = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty, !FireTVPresentationPolicy.isSystemIdentity(value) else { return }
                            Task { await appModel.launchFireTVApp(packageName: value, for: player) }
                        }
                    }.padding(.top, 8)
                }
                .padding(14)
                .ios27ContentSurface(radius: 22)
            }
        }
    }

    @ViewBuilder
    private func remote(_ player: HomeAssistantEntity) -> some View {
        let state = FireTVPresentationState.resolve(entity: player)
        if state != .off, state != .standby, state != .unavailable, player.companionSupportsDirectionalNavigation || player.companionSupportsGlobalNavigation {
            VStack(alignment: .leading, spacing: 10) {
                IOS27SectionHeader(title: "Fernbedienung")
                HStack(spacing: 10) {
                    action("chevron.backward", "Zurück") { Task { await appModel.callFireTVCompanionService("navigate_back", for: player) } }
                    action("house.fill", "Home") { Task { await appModel.callFireTVCompanionService("navigate_home", for: player) } }
                    action("line.3.horizontal", "Menü") { Task { await appModel.callFireTVCompanionService("navigate_menu", for: player) } }
                }
            }
        }
    }

    private func deviceInfo(_ player: HomeAssistantEntity) -> some View {
        DisclosureGroup("Geräteinformationen") {
            VStack(alignment: .leading, spacing: 8) {
                if let version = player.companionCapabilityVersion { LabeledContent("Capability-Version", value: "\(version)") }
                if let app = FireTVPresentationPolicy.visibleForegroundApp(for: player) { LabeledContent("Aktive App", value: app) }
                LabeledContent("Status", value: stateText(FireTVPresentationState.resolve(entity: player)))
            }.padding(.top, 8)
        }
        .padding(14)
        .ios27ContentSurface(radius: 22)
    }

    private func launchableApps(_ player: HomeAssistantEntity) -> [FireTVUserApp] {
        var result: [FireTVUserApp] = []
        for key in ["launchable_apps", "installed_apps", "apps", "app_packages"] {
            if let object = player.attributes[key]?.objectValue {
                for (rawKey, rawValue) in object {
                    guard let rawText = rawValue.stringValue else { continue }
                    let package = rawKey.contains(".") ? rawKey : rawText
                    let name = rawKey.contains(".") ? rawText : rawKey
                    if package.contains("."), FireTVPresentationPolicy.isLaunchableUserApp(name: name, package: package) {
                        result.append(.init(name: name, package: package))
                    }
                }
            }
            if let array = player.attributes[key]?.arrayValue {
                for item in array {
                    if let object = item.objectValue {
                        guard let package = object["package_name"]?.stringValue ?? object["package"]?.stringValue else { continue }
                        let name = object["name"]?.stringValue ?? object["label"]?.stringValue ?? FireTVPresentationPolicy.prettyPackageName(package)
                        if package.contains("."), FireTVPresentationPolicy.isLaunchableUserApp(name: name, package: package) { result.append(.init(name: name, package: package)) }
                    } else if let package = item.stringValue, package.contains("."), FireTVPresentationPolicy.isLaunchableUserApp(name: package, package: package) {
                        result.append(.init(name: FireTVPresentationPolicy.prettyPackageName(package), package: package))
                    }
                }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.package).inserted }
    }

    private func cleanMediaTitle(_ player: HomeAssistantEntity) -> String {
        if let title = player.mediaTitle, !title.isEmpty, !FireTVPresentationPolicy.isSystemIdentity(title) { return title }
        return player.state == "playing" ? "Wiedergabe" : "Pausiert"
    }

    private func stateText(_ state: FireTVPresentationState) -> String {
        switch state {
        case .unavailable: "Nicht verfügbar"
        case .off: "Aus"
        case .standby: "Standby"
        case .idle: "Bereit"
        case .playing: "Wiedergabe"
        case .paused: "Pausiert"
        }
    }

    private func action(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 42, height: 42) }
            .buttonStyle(.bordered)
            .accessibilityLabel(label)
    }
}
