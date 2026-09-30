import Foundation

struct LightColorFavorite: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let red: Double
    let green: Double
    let blue: Double

    init(id: UUID = UUID(), red: Double, green: Double, blue: Double) {
        self.id = id
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    var homeAssistantColor: HomeAssistantLightColor {
        HomeAssistantLightColor(red: red, green: green, blue: blue)
    }
}

enum LightColorFavoritesStore {
    private static let key = "iosnext.light-color-favorites.v1"
    private static let maximumPerEntity = 6

    static func favorites(for entityID: String, defaults: UserDefaults = .standard) -> [LightColorFavorite] {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [LightColorFavorite]].self, from: data)
        else { return [] }
        return Array((payload[entityID] ?? []).prefix(maximumPerEntity))
    }

    @discardableResult
    static func add(_ color: HomeAssistantLightColor, for entityID: String, defaults: UserDefaults = .standard) -> [LightColorFavorite] {
        var payload = loadAll(defaults: defaults)
        var values = payload[entityID] ?? []
        let duplicate = values.contains { existing in
            let dr = existing.red - color.red
            let dg = existing.green - color.green
            let db = existing.blue - color.blue
            return (dr * dr + dg * dg + db * db) < 0.0025
        }
        if !duplicate {
            values.append(LightColorFavorite(red: color.red, green: color.green, blue: color.blue))
            values = Array(values.suffix(maximumPerEntity))
        }
        payload[entityID] = values
        save(payload, defaults: defaults)
        return values
    }

    @discardableResult
    static func remove(_ id: UUID, for entityID: String, defaults: UserDefaults = .standard) -> [LightColorFavorite] {
        var payload = loadAll(defaults: defaults)
        let values = (payload[entityID] ?? []).filter { $0.id != id }
        payload[entityID] = values
        save(payload, defaults: defaults)
        return values
    }

    static func clear(for entityID: String, defaults: UserDefaults = .standard) {
        var payload = loadAll(defaults: defaults)
        payload.removeValue(forKey: entityID)
        save(payload, defaults: defaults)
    }

    private static func loadAll(defaults: UserDefaults) -> [String: [LightColorFavorite]] {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [LightColorFavorite]].self, from: data)
        else { return [:] }
        return payload
    }

    private static func save(_ payload: [String: [LightColorFavorite]], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }
}

struct LightSegmentBridgeSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let sourceEntityID: String
    let supported: Bool
    let segmentCount: Int
    let segmentIndices: [Int]
    let provider: String?
    let uiEnabled: Bool
    let deviceWriteEnabled: Bool
    let reason: String?
    let state: String

    var isReady: Bool {
        state == "ready" && supported && uiEnabled && deviceWriteEnabled && segmentCount > 1 && !segmentIndices.isEmpty
    }
}

extension HomeAssistantEntity {
    var lightSegmentBridgeSnapshot: LightSegmentBridgeSnapshot? {
        guard domain == "sensor",
              let sourceEntityID = attributes["source_entity"]?.stringValue,
              !sourceEntityID.isEmpty
        else { return nil }

        let count = max(0, Int(attributes["segment_count"]?.numberValue ?? 0))
        let advertised = attributes["segments"]?.numberArrayValue?.map { Int($0) } ?? []
        let indices = advertised.isEmpty && count > 0 ? Array(0..<count) : advertised
        return LightSegmentBridgeSnapshot(
            id: entityID,
            sourceEntityID: sourceEntityID,
            supported: attributes["supported"]?.boolValue == true,
            segmentCount: count,
            segmentIndices: Array(Set(indices.filter { $0 >= 0 })).sorted(),
            provider: attributes["provider"]?.stringValue,
            uiEnabled: attributes["ui_enabled"]?.boolValue == true,
            deviceWriteEnabled: attributes["device_write_enabled"]?.boolValue == true,
            reason: attributes["reason"]?.stringValue,
            state: state.lowercased()
        )
    }
}
