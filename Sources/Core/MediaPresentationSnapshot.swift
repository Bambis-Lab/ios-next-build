import Foundation

/// Immutable media grouping built once per debounced Home Assistant state revision.
/// The specialized adapters remain authoritative for their own controls/capabilities.
struct MediaPresentationSnapshot {
    let players: [HomeAssistantEntity]
    let activePlayerCount: Int
    let nicoPlayers: [HomeAssistantEntity]
    let fireTVPlayers: [HomeAssistantEntity]
    let remainingPlayers: [HomeAssistantEntity]

    static let empty = MediaPresentationSnapshot(
        players: [], activePlayerCount: 0, nicoPlayers: [],
        fireTVPlayers: [], remainingPlayers: []
    )

    @MainActor
    static func build(from appModel: AppModel) -> Self {
        let trace = IOSNextPerformance.begin("Media.PresentationSnapshot")
        defer { IOSNextPerformance.end("Media.PresentationSnapshot", trace) }
        let players = appModel.entities(inDomain: "media_player")
        let nicoIDs: Set<String> = [
            "media_player.nico_zimmer_untergeschoss_apple_tv",
            "media_player.denon_avr_x1300w",
            "media_player.playstation_5"
        ]
        let nico = players.filter { nicoIDs.contains($0.entityID) }
        let fire = players.filter { appModel.isFireTVCompanion($0) }
        let fireIDs = Set(fire.map(\.entityID))
        let remaining = players.filter {
            !nicoIDs.contains($0.entityID)
                && !fireIDs.contains($0.entityID)
                && !appModel.isShadowedByFireTVCompanion($0)
        }
        let active = players.reduce(into: 0) { count, player in
            if ["playing", "paused", "buffering", "on"].contains(player.state.lowercased()) {
                count += 1
            }
        }
        return Self(
            players: players,
            activePlayerCount: active,
            nicoPlayers: nico,
            fireTVPlayers: fire,
            remainingPlayers: remaining
        )
    }
}
