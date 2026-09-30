import Foundation

struct ProfileDefinition: Equatable, Sendable {
    let profile: HomeProfile
    let roomNames: [String]
    let favoriteEntityIDs: [String]
}

enum ProfileCatalog {
    static func definition(for profile: HomeProfile) -> ProfileDefinition {
        switch profile {
        case .nico:
            ProfileDefinition(
                profile: .nico,
                roomNames: ["Nico Zimmer"],
                favoriteEntityIDs: [
                    "light.kronach_fernseher_links",
                    "light.kronach_fernseher_rechts",
                    "light.kronach_schrank",
                    "media_player.nico_zimmer_untergeschoss_apple_tv",
                    "media_player.denon_avr_x1300w",
                    "media_player.playstation_5"
                ]
            )
        case .timo:
            ProfileDefinition(
                profile: .timo,
                roomNames: ["Timo Zimmer"],
                favoriteEntityIDs: [
                    "light.hintergrund_fernseher",
                    "light.nachttisch",
                    "light.schlafzimmer",
                    "media_player.schlafzimmer"
                ]
            )
        case .mika:
            ProfileDefinition(
                profile: .mika,
                roomNames: ["Mika Zimmer"],
                favoriteEntityIDs: ["media_player.fire_tv_companion"]
            )
        case .juli:
            ProfileDefinition(profile: .juli, roomNames: ["Juli Zimmer"], favoriteEntityIDs: [])
        case .gabi:
            ProfileDefinition(profile: .gabi, roomNames: ["Zuhause"], favoriteEntityIDs: [])
        }
    }
}
