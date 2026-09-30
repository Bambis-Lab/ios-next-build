import Foundation

private struct LiveHAFixture: Decodable {
    let floors: [Floor]?
    let areas: [Area]
    let devices: [Device]
    let entities: [Entity]

    struct Floor: Decodable { let id: String; let name: String; let level: Int? }
    struct Area: Decodable { let id: String; let name: String; let floorID: String? }
    struct Device: Decodable { let id: String; let name: String; let areaID: String?; let disabled: Bool }
    struct Entity: Decodable {
        let entityID: String
        let deviceID: String?
        let areaID: String?
        let state: String
        let attributes: [String: JSONValue]
        let disabled: Bool
        let hidden: Bool
        let platform: String?
    }
}

extension AppModel {
    static var preview: AppModel {
        let model = AppModel()
        model.connectionState = .connected
        guard let url = Bundle.main.url(forResource: "live_ha_fixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixture = try? JSONDecoder().decode(LiveHAFixture.self, from: data) else {
            return fallbackPreview(model)
        }

        let fixtureFloors = (fixture.floors ?? []).map { HomeAssistantFloor(id: $0.id, name: $0.name, level: $0.level) }
        if fixtureFloors.contains(where: { $0.name.localizedCaseInsensitiveCompare("Erdgeschoss") == .orderedSame }) {
            model.floors = fixtureFloors
        } else {
            // Product-acceptance previews need a deterministic fourth Home shortcut even when
            // an older captured HA fixture predates floor-registry export.
            model.floors = fixtureFloors + [HomeAssistantFloor(id: "preview-ground-floor", name: "Erdgeschoss", level: 0)]
        }

        model.areas = fixture.areas.map { .init(id: $0.id, name: $0.name, floorID: $0.floorID) }
        model.devices = fixture.devices.map { .init(id: $0.id, name: $0.name, areaID: $0.areaID) }
        model.entityRegistry = fixture.entities.map {
            .init(entityID: $0.entityID, deviceID: $0.deviceID, areaID: $0.areaID, platform: $0.platform)
        }
        model.entities = fixture.entities.map {
            .init(entityID: $0.entityID, state: $0.state, attributes: $0.attributes)
        }
        return model
    }

    private static func fallbackPreview(_ model: AppModel) -> AppModel {
        model.entities = [.init(entityID: "sensor.fixture_error", state: "unavailable", attributes: ["friendly_name": .string("Live-HA-Fixture nicht geladen")])]
        return model
    }
}

extension ChatModel {
    static var preview: ChatModel {
        let model = ChatModel()
        model.state = .online
        model.recipientUserID = "Mika"
        model.ownSafetyNumber = "4821 7750 1904 3382"
        model.recipientSafetyNumbers = ["9550 2711 6842 1290"]
        model.messages = [
            ChatMessage(
                id: "preview-incoming",
                senderUserID: "Mika",
                kind: .text,
                contentType: "text/plain; charset=utf-8",
                data: Data("Bin gleich da 👋".utf8),
                createdAt: Date(timeIntervalSince1970: 1_789_553_100),
                direction: .incoming,
                delivery: .received
            ),
            ChatMessage(
                id: "preview-outgoing",
                senderUserID: "Timo",
                kind: .text,
                contentType: "text/plain; charset=utf-8",
                data: Data("Perfekt, bis gleich.".utf8),
                createdAt: Date(timeIntervalSince1970: 1_789_553_160),
                direction: .outgoing,
                delivery: .received
            )
        ]
        return model
    }
}
