import SwiftUI

/// Deterministic, offline room fixture for Xcode 27 visual and interaction
/// acceptance. Launched only by the explicit --nico-room-layout-acceptance flag.
/// No real Home Assistant credential, token, connection or service is used.
struct NicoRoomVisualAcceptanceView: View {
    @State private var appModel = AppModel()

    private let area = HomeAssistantArea(id: "nico-acceptance", name: "Nico Zimmer")

    var body: some View {
        NavigationStack {
            RoomDetailView(area: area, appModel: appModel)
        }
        .task { seedOfflineFixture() }
        .accessibilityIdentifier("nico-room-visual-acceptance")
    }

    private func seedOfflineFixture() {
        guard appModel.entities.isEmpty else { return }
        let brightModes: JSONValue = .array([.string("brightness"), .string("hs")])
        appModel.entities = [
            HomeAssistantEntity(entityID: "light.kronach_fernseher_links", state: "on",
                attributes: ["friendly_name": .string("TV links"), "brightness": .number(220),
                             "supported_color_modes": brightModes]),
            HomeAssistantEntity(entityID: "light.kronach_fernseher_rechts", state: "on",
                attributes: ["friendly_name": .string("TV rechts"), "brightness": .number(220),
                             "supported_color_modes": brightModes]),
            HomeAssistantEntity(entityID: "light.kronach_schrank", state: "on",
                attributes: ["friendly_name": .string("Schrank"), "brightness": .number(160),
                             "rgb_color": .array([.number(55), .number(80), .number(255)]),
                             "supported_color_modes": brightModes]),
            HomeAssistantEntity(
                entityID: "switch.schreibtisch_rgb_standlampe_steckdose_1", state: "on",
                attributes: ["friendly_name": .string("Schreibtischlampe")]
            ),
            HomeAssistantEntity(entityID: "scene.kronach_kronach_prisma", state: "scening",
                attributes: ["friendly_name": .string("Prisma")]),
            HomeAssistantEntity(entityID: "group.nico_beleuchtung", state: "on", attributes: [:])
        ]
        appModel.areas = [area]
        appModel.devices = [
            HomeAssistantDevice(id: "nico-acceptance-light", name: "Fixture Lichter", areaID: area.id)
        ]
        appModel.entityRegistry = appModel.entities.map {
            HomeAssistantRegistryEntity(
                entityID: $0.entityID,
                deviceID: "nico-acceptance-light",
                areaID: area.id,
                platform: "fixture"
            )
        }
    }
}
