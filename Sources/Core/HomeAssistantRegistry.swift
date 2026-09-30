import Foundation

struct HomeAssistantFloor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let level: Int?

    init(id: String, name: String, level: Int? = nil) {
        self.id = id
        self.name = name
        self.level = level
    }
}

struct HomeAssistantArea: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let floorID: String?

    init(id: String, name: String, floorID: String? = nil) {
        self.id = id
        self.name = name
        self.floorID = floorID
    }
}

struct HomeAssistantDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let areaID: String?
}

struct HomeAssistantRegistryEntity: Identifiable, Hashable, Sendable {
    let entityID: String
    let deviceID: String?
    let areaID: String?
    let platform: String?

    var id: String { entityID }
}

struct HomeAssistantCurrentUser: Equatable, Sendable {
    let id: String
    let name: String
}

struct HomeAssistantSnapshot: Sendable {
    let currentUser: HomeAssistantCurrentUser
    let states: [HomeAssistantEntity]
    let floors: [HomeAssistantFloor]
    let areas: [HomeAssistantArea]
    let devices: [HomeAssistantDevice]
    let entityRegistry: [HomeAssistantRegistryEntity]
}
extension HomeAssistantFloor {
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["floor_id"] as? String,
              let name = dictionary["name"] as? String else { return nil }
        let level = (dictionary["level"] as? NSNumber)?.intValue
        self.init(id: id, name: name, level: level)
    }

    init?(object: [String: JSONValue]) {
        guard let id = object["floor_id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        let level = object["level"]?.numberValue.map { Int($0) }
        self.init(id: id, name: name, level: level)
    }
}

extension HomeAssistantArea {
    var isAppRoom: Bool {
        !["Tisch", "Ambiente"].contains { name.localizedCaseInsensitiveCompare($0) == .orderedSame }
    }

    var appDisplayName: String {
        name.localizedCaseInsensitiveCompare("Hütte Master") == .orderedSame ? "Hütte" : name
    }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["area_id"] as? String,
              let name = dictionary["name"] as? String else { return nil }
        self.init(id: id, name: name, floorID: dictionary["floor_id"] as? String)
    }
}

extension HomeAssistantDevice {
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String else { return nil }
        let name = dictionary["name_by_user"] as? String
            ?? dictionary["name"] as? String
            ?? id
        self.init(id: id, name: name, areaID: dictionary["area_id"] as? String)
    }
}

extension HomeAssistantRegistryEntity {
    init?(dictionary: [String: Any]) {
        guard let entityID = dictionary["entity_id"] as? String else { return nil }
        self.init(
            entityID: entityID,
            deviceID: dictionary["device_id"] as? String,
            areaID: dictionary["area_id"] as? String,
            platform: dictionary["platform"] as? String
        )
    }
}

// Production WebSocket decoding uses JSONValue so registry data stays Sendable.
extension HomeAssistantArea {
    init?(object: [String: JSONValue]) {
        guard let id = object["area_id"]?.stringValue,
              let name = object["name"]?.stringValue else { return nil }
        self.init(id: id, name: name, floorID: object["floor_id"]?.stringValue)
    }
}

extension HomeAssistantDevice {
    init?(object: [String: JSONValue]) {
        guard let id = object["id"]?.stringValue else { return nil }
        let name = object["name_by_user"]?.stringValue
            ?? object["name"]?.stringValue
            ?? id
        self.init(id: id, name: name, areaID: object["area_id"]?.stringValue)
    }
}

extension HomeAssistantRegistryEntity {
    init?(object: [String: JSONValue]) {
        guard let entityID = object["entity_id"]?.stringValue else { return nil }
        self.init(
            entityID: entityID,
            deviceID: object["device_id"]?.stringValue,
            areaID: object["area_id"]?.stringValue,
            platform: object["platform"]?.stringValue
        )
    }
}
