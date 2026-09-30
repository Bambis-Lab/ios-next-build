import SwiftUI

struct MediaView: View {
    let appModel: AppModel

    private var players: [HomeAssistantEntity] { appModel.entities(inDomain: "media_player") }
    private var activePlayerCount: Int {
        players.filter { player in
            ["playing", "paused", "buffering", "on"].contains(player.state.lowercased())
        }.count
    }
    private var nicoPlayers: [HomeAssistantEntity] {
        [
            entity("media_player.nico_zimmer_untergeschoss_apple_tv"),
            entity("media_player.denon_avr_x1300w"),
            entity("media_player.playstation_5")
        ].compactMap { $0 }
    }
    private var nicoIDs: Set<String> { Set(nicoPlayers.map(\.entityID)) }
    private var fireTVPlayers: [HomeAssistantEntity] { players.filter { appModel.isFireTVCompanion($0) } }
    private var fireTVIDs: Set<String> { Set(fireTVPlayers.map(\.entityID)) }
    private var remainingPlayers: [HomeAssistantEntity] {
        players.filter { !nicoIDs.contains($0.entityID) && !fireTVIDs.contains($0.entityID) && !appModel.isShadowedByFireTVCompanion($0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !players.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(activePlayerCount > 0 ? .green : .secondary)
                        Text("\(activePlayerCount) Player sind aktiv")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("\(players.count) gesamt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .ios27ContentSurface(radius: 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(activePlayerCount) Player sind aktiv")
                    .accessibilityIdentifier("media-active-summary")
                }

                if !nicoPlayers.isEmpty {
                    IOS27SectionHeader(title: "Nico Medien", subtitle: "Apple TV · Denon · PlayStation")
                    IOS27MediaZoneCard(
                        title: "Nico Medien",
                        subtitle: "Apple TV und Denon gekoppelt · PlayStation separat",
                        players: nicoPlayers,
                        masterState: entity("binary_sensor.nico_medien_aktiv"),
                        masterScript: entity("script.nico_medien_master_zentrale"),
                        appModel: appModel,
                        coupledPlaybackPlayerID: "media_player.nico_zimmer_untergeschoss_apple_tv",
                        coupledOutputPlayerID: "media_player.denon_avr_x1300w",
                        playerNameOverrides: [
                            "media_player.nico_zimmer_untergeschoss_apple_tv": "Apple TV",
                            "media_player.denon_avr_x1300w": "Denon AVR",
                            "media_player.playstation_5": "PlayStation 5"
                        ]
                    )
                }

                if !fireTVPlayers.isEmpty {
                    IOS27SectionHeader(title: "Fire TV Companion", subtitle: "Capability-basierte Steuerung")
                    ForEach(fireTVPlayers) { player in
                        IOS27FireTVCompanionCardV2(player: player, appModel: appModel)
                    }
                }

                if !remainingPlayers.isEmpty {
                    IOS27SectionHeader(title: "Weitere Medien", subtitle: "Receiver, Cast und TV")
                    ForEach(remainingPlayers) { player in
                        NavigationLink {
                            MediaDetailView(playerID: player.entityID, appModel: appModel)
                        } label: {
                            IOS27MediaCard(player: player, appModel: appModel)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if players.isEmpty {
                    EmptyFeatureView(
                        title: "Keine Medienplayer",
                        symbol: "play.tv",
                        message: "Verbundene Home-Assistant-Medienplayer erscheinen hier automatisch."
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle("Medien")
        .navigationBarTitleDisplayMode(.large)
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

struct MediaDetailView: View {
    let playerID: String
    let appModel: AppModel

    private var player: HomeAssistantEntity? { appModel.entities.first { $0.entityID == playerID } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let player {
                    IOS27MediaCard(player: player, appModel: appModel)
                } else {
                    EmptyFeatureView(
                        title: "Player nicht verfügbar",
                        symbol: "play.slash",
                        message: "Der Player ist nicht mehr im aktuellen Home-Assistant-Zustand vorhanden."
                    )
                }
            }
            .padding(16)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle(player?.displayName ?? "Jetzt läuft")
        .navigationBarTitleDisplayMode(.inline)
    }
}
