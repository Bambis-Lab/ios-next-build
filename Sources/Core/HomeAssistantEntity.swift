import Foundation


struct HomeAssistantLightColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

struct HomeAssistantMediaFeature: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let pause = Self(rawValue: 1)
    static let seek = Self(rawValue: 2)
    static let volumeSet = Self(rawValue: 4)
    static let volumeMute = Self(rawValue: 8)
    static let previousTrack = Self(rawValue: 16)
    static let nextTrack = Self(rawValue: 32)
    static let turnOn = Self(rawValue: 128)
    static let turnOff = Self(rawValue: 256)
    static let playMedia = Self(rawValue: 512)
    static let volumeStep = Self(rawValue: 1024)
    static let selectSource = Self(rawValue: 2048)
    static let stop = Self(rawValue: 4096)
    static let play = Self(rawValue: 16384)
    static let browseMedia = Self(rawValue: 131072)
    static let repeatSet = Self(rawValue: 262144)
}

enum EntityValueFormatter {
    private static let unavailableStates: Set<String> = ["unavailable", "unknown", "none", "null", ""]

    static func secondaryText(state: String, unit: String?, localizedState: String) -> String {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !unavailableStates.contains(normalized) else { return "Nicht verfügbar" }
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
            return localizedState
        }
        return "\(state) \(unit)"
    }
}

struct HomeAssistantEntity: Identifiable, Hashable, Sendable {
    let entityID: String
    let state: String
    let attributes: [String: JSONValue]

    var id: String { entityID }

    var displayName: String {
        if let preferredPresentationName { return preferredPresentationName }
        if let friendly = attributes["friendly_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !friendly.isEmpty,
           friendly.localizedCaseInsensitiveCompare(entityID) != .orderedSame {
            if domain == "update" && friendly.localizedCaseInsensitiveCompare("Update") == .orderedSame {
                return presentationFallbackName
            }
            return friendly
        }
        return presentationFallbackName
    }

    private var preferredPresentationName: String? {
        switch entityID {
        case "light.kronach_fernseher_links": "TV links"
        case "light.kronach_fernseher_rechts": "TV rechts"
        case "light.kronach_schrank": "Schrank"
        case "switch.schreibtisch_rgb_standlampe_steckdose_1": "Schreibtischlampe"
        case "switch.tv_steckdose_1": "TV-Strom"
        case "group.nico_beleuchtung": "Licht Master"
        case "media_player.nico_zimmer_untergeschoss_apple_tv": "Apple TV"
        case "media_player.denon_avr_x1300w": "Denon AVR"
        case "media_player.playstation_5": "PlayStation 5"
        case "light.hutte": "Ambiente"
        case "light.tisch_tisch": "Tisch"
        case "media_player.denon_avr_x1800h": "Denon AVR"
        case "media_player.gigatv_home": "GigaTV"
        default: nil
        }
    }

    private var presentationFallbackName: String {
        let objectID = entityID.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? entityID
        let words = objectID
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { token in
                let text = String(token)
                if text.allSatisfy({ $0.isNumber }) { return text }
                return text.prefix(1).uppercased() + text.dropFirst()
            }
        let candidate = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? domain.localizedCapitalized : candidate
    }

    var isOn: Bool {
        if domain == "media_player" {
            return !["off", "unavailable", "unknown"].contains(state.lowercased())
        }
        if domain == "lawn_mower" {
            return ["mowing", "returning", "returning_home", "cleaning"].contains(state.lowercased())
        }
        return ["on", "playing", "open", "opening", "heat", "cool"].contains(state.lowercased())
    }

    var stateDisplayName: String { stateDisplayText }

    var domain: String {
        entityID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    }

    var areaID: String? { attributes["area_id"]?.stringValue }
    var deviceID: String? { attributes["device_id"]?.stringValue }
    var isAvailable: Bool { state != "unavailable" && state != "unknown" }
    var brightness: Double? {
        attributes["brightness"]?.numberValue.map { min(max($0 / 255, 0), 1) }
    }
    var brightnessFraction: Double? { brightness }
    var colorTemperatureKelvin: Double? {
        if let kelvin = attributes["color_temp_kelvin"]?.numberValue { return kelvin }
        guard let mired = attributes["color_temp"]?.numberValue, mired > 0 else { return nil }
        return 1_000_000 / mired
    }
    var minColorTemperatureKelvin: Double? { attributes["min_color_temp_kelvin"]?.numberValue }
    var maxColorTemperatureKelvin: Double? { attributes["max_color_temp_kelvin"]?.numberValue }
    var currentEffect: String? { attributes["effect"]?.stringValue }
    var effectList: [String] { attributes["effect_list"]?.stringArrayValue ?? [] }
    var supportedColorModes: Set<String> { Set(attributes["supported_color_modes"]?.stringArrayValue ?? []) }
    var supportsBrightness: Bool {
        domain == "light" && (brightness != nil || !supportedColorModes.isDisjoint(with: ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww"]))
    }
    var supportsColorTemperature: Bool { domain == "light" && supportedColorModes.contains("color_temp") }
    var supportsColor: Bool {
        domain == "light" && !supportedColorModes.isDisjoint(with: ["hs", "xy", "rgb", "rgbw", "rgbww"])
    }
    var supportsEffects: Bool { domain == "light" && !effectList.isEmpty }
    var lightColor: HomeAssistantLightColor? {
        if let rgb = attributes["rgb_color"]?.numberArrayValue, rgb.count >= 3 {
            return HomeAssistantLightColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255)
        }
        if let hs = attributes["hs_color"]?.numberArrayValue, hs.count >= 2 {
            return Self.rgbFromHS(hue: hs[0], saturation: hs[1])
        }
        if let xy = attributes["xy_color"]?.numberArrayValue, xy.count >= 2 {
            return Self.rgbFromXY(x: xy[0], y: xy[1])
        }
        if let kelvin = colorTemperatureKelvin { return Self.rgbFromKelvin(kelvin) }
        return nil
    }
    var volumeLevel: Double? {
        attributes["volume_level"]?.numberValue.map { min(max($0, 0), 1) }
    }
    var isMuted: Bool? { attributes["is_volume_muted"]?.boolValue }
    var mediaTitle: String? { attributes["media_title"]?.stringValue }
    var mediaArtist: String? { attributes["media_artist"]?.stringValue }
    var supportedFeatures: Int {
        Int(attributes["supported_features"]?.numberValue ?? 0)
    }
    func supports(_ feature: Int) -> Bool {
        supportedFeatures & feature == feature
    }
    var mediaFeatures: HomeAssistantMediaFeature { HomeAssistantMediaFeature(rawValue: supportedFeatures) }
    var supportsPlay: Bool { domain == "media_player" && mediaFeatures.contains(.play) }
    var supportsPause: Bool { domain == "media_player" && mediaFeatures.contains(.pause) }
    var supportsStop: Bool { domain == "media_player" && mediaFeatures.contains(.stop) }
    var supportsSeek: Bool { domain == "media_player" && mediaFeatures.contains(.seek) }
    var supportsPreviousTrack: Bool { domain == "media_player" && mediaFeatures.contains(.previousTrack) }
    var supportsNextTrack: Bool { domain == "media_player" && mediaFeatures.contains(.nextTrack) }
    var supportsVolumeSet: Bool { domain == "media_player" && mediaFeatures.contains(.volumeSet) }
    var supportsVolumeMute: Bool { domain == "media_player" && mediaFeatures.contains(.volumeMute) }
    var supportsTurnOn: Bool { domain == "media_player" && mediaFeatures.contains(.turnOn) }
    var supportsTurnOff: Bool { domain == "media_player" && mediaFeatures.contains(.turnOff) }
    var supportsMediaPower: Bool { supportsTurnOn || supportsTurnOff }
    var supportsSourceSelection: Bool { domain == "media_player" && mediaFeatures.contains(.selectSource) }

    var companionCapabilities: [String: JSONValue] {
        attributes["capabilities"]?.objectValue ?? [:]
    }

    var companionCapabilityVersion: Int? {
        companionCapabilities["capability_version"]?.numberValue.map { Int($0) }
    }

    func companionSupports(_ capability: String) -> Bool {
        companionCapabilities[capability]?.boolValue == true
    }

    var companionSupportsLaunchApps: Bool { companionSupports("launch_apps") }
    var companionSupportsPlayerControl: Bool { companionSupports("player_control") }
    var companionSupportsMediaSession: Bool { companionSupports("media_session") }
    var companionSupportsVolumeControl: Bool { companionSupports("volume_control") }
    var companionSupportsMuteControl: Bool { companionSupports("mute_control") }
    var companionSupportsQueueControl: Bool { companionSupports("queue_control") }
    var companionSupportsForegroundApp: Bool { companionSupports("foreground_app") }
    var companionSupportsGlobalNavigation: Bool { companionSupports("global_navigation") }
    var companionSupportsDirectionalNavigation: Bool {
        companionSupports("directional_navigation") || companionSupportsGlobalNavigation
    }
    var companionSupportsStandbyControl: Bool { companionSupports("standby_control") }
    var companionSupportsWakeControl: Bool { companionSupports("wake_control") }
    var companionSupportsPowerControl: Bool { companionSupports("power_control") }
    var source: String? { attributes["source"]?.stringValue }
    var sourceList: [String] { attributes["source_list"]?.stringArrayValue ?? [] }
    var mediaPosition: Double? { attributes["media_position"]?.numberValue }
    var mediaDuration: Double? { attributes["media_duration"]?.numberValue }

    var supportsToggle: Bool {
        ["light", "switch", "fan", "input_boolean", "group"].contains(domain)
    }

    var supportsMediaControls: Bool { domain == "media_player" }
    var isFireTVCompanion: Bool { domain == "media_player" && entityID.contains("fire_tv_companion") }
    var mediaContentType: String? { attributes["media_content_type"]?.stringValue }
    var mediaImageURL: String? { attributes["entity_picture"]?.stringValue }
    var unitOfMeasurement: String? { attributes["unit_of_measurement"]?.stringValue }
    var currentTemperature: Double? { attributes["current_temperature"]?.numberValue }
    var targetTemperature: Double? { attributes["temperature"]?.numberValue }
    var temperature: Double? { targetTemperature }
    var currentPosition: Double? { attributes["current_position"]?.numberValue }
    var position: Double? {
        if domain == "cover" { return attributes["current_position"]?.numberValue }
        return nil
    }

    var iconName: String {
        switch domain {
        case "light": "lightbulb.fill"
        case "switch", "input_boolean": "switch.2"
        case "group": "lightbulb.2.fill"
        case "media_player": "play.rectangle.fill"
        case "scene": "circle.hexagongrid.fill"
        case "script": "scroll.fill"
        case "sensor": "gauge.with.dots.needle.50percent"
        case "binary_sensor": "sensor.fill"
        case "climate": "thermometer.medium"
        case "cover": "window.shade.open"
        case "lock": "lock.fill"
        case "fan": "fan.fill"
        default: "circle.grid.2x2.fill"
        }
    }

    var stateDisplayText: String {
        switch state.lowercased() {
        case "on": "Ein"
        case "off": "Aus"
        case "playing": "Wiedergabe"
        case "paused": "Pausiert"
        case "idle", "ready", "mode_ready": "Bereit"
        case "standby": "Standby"
        case "docked", "parked": "In Ladestation"
        case "charging": "Lädt"
        case "mowing": "Mäht"
        case "returning", "returning_home": "Fährt zur Ladestation"
        case "cleaning": "Aktiv"
        case "unknown", "unavailable": "Nicht verfügbar"
        case "problem", "error": "Fehler"
        case "open": "Geöffnet"
        case "closed": "Geschlossen"
        case "opening": "Öffnet"
        case "closing": "Schließt"
        default: state.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }

    var secondaryStateText: String {
        if domain == "media_player", isAvailable, let mediaTitle, !mediaTitle.isEmpty { return mediaTitle }
        return EntityValueFormatter.secondaryText(
            state: state,
            unit: unitOfMeasurement,
            localizedState: stateDisplayText
        )
    }

    var isPrimaryRoomControl: Bool {
        guard [EntityControlKind.toggle, .cover, .climate, .lock].contains(controlKind) else { return false }
        let searchable = "\(entityID) \(displayName)".lowercased()
        let technicalTerms = [
            "wi-fi", "wifi", "wlan", "pre-release", "pre_release", "kindersicherung",
            "automation:", "automatische aktualisierungen", "bluetooth", "cloud", "sprache",
            "safe browsing", "sichere suche", "abfrageprotokoll", "filterung", "jugendschutz"
        ]
        return !technicalTerms.contains { searchable.contains($0) }
    }

    var controlKind: EntityControlKind {
        switch domain {
        case "light": .light
        case "switch", "fan", "input_boolean": .toggle
        case "media_player": .media
        case "cover": .cover
        case "climate": .climate
        case "lock": .lock
        case "scene": .scene
        case "script": .script
        default: .readOnly
        }
    }

    func updating(state: String) -> HomeAssistantEntity {
        HomeAssistantEntity(entityID: entityID, state: state, attributes: attributes)
    }

    private static func rgbFromHS(hue: Double, saturation: Double) -> HomeAssistantLightColor {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = min(max(saturation / 100, 0), 1)
        let x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double)
        switch h {
        case 0..<1: (r, g, b) = (1, x, 0)
        case 1..<2: (r, g, b) = (x, 1, 0)
        case 2..<3: (r, g, b) = (0, 1, x)
        case 3..<4: (r, g, b) = (0, x, 1)
        case 4..<5: (r, g, b) = (x, 0, 1)
        default: (r, g, b) = (1, 0, x)
        }
        return HomeAssistantLightColor(red: r * s + (1 - s), green: g * s + (1 - s), blue: b * s + (1 - s))
    }

    private static func rgbFromXY(x: Double, y: Double) -> HomeAssistantLightColor? {
        guard y > 0 else { return nil }
        let z = 1 - x - y
        let Y = 1.0
        let X = (Y / y) * x
        let Z = (Y / y) * z
        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530
        func gamma(_ value: Double) -> Double { value <= 0.0031308 ? 12.92 * value : 1.055 * pow(max(value, 0), 1 / 2.4) - 0.055 }
        r = gamma(r); g = gamma(g); b = gamma(b)
        let peak = max(max(r, g), max(b, 1))
        return HomeAssistantLightColor(red: r / peak, green: g / peak, blue: b / peak)
    }

    private static func rgbFromKelvin(_ value: Double) -> HomeAssistantLightColor {
        let temperature = min(max(value, 1000), 40000) / 100
        let red = temperature <= 66 ? 255 : 329.698727446 * pow(temperature - 60, -0.1332047592)
        let green = temperature <= 66 ? 99.4708025861 * log(temperature) - 161.1195681661 : 288.1221695283 * pow(temperature - 60, -0.0755148492)
        let blue = temperature >= 66 ? 255 : (temperature <= 19 ? 0 : 138.5177312231 * log(temperature - 10) - 305.0447927307)
        return HomeAssistantLightColor(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

enum JSONValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    var foundationValue: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case let .object(value): value.mapValues(\.foundationValue)
        case let .array(value): value.map(\.foundationValue)
        case .null: NSNull()
        }
    }

    var stringArrayValue: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    var numberArrayValue: [Double]? {
        arrayValue?.compactMap(\.numberValue)
    }
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
