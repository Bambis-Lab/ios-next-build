import Foundation

enum EntityControlKind: String, CaseIterable, Sendable {
    case light
    case toggle
    case media
    case cover
    case climate
    case lock
    case scene
    case script
    case readOnly
}

enum HomeAssistantService {
    static let turnOn = "turn_on"
    static let turnOff = "turn_off"
    static let openCover = "open_cover"
    static let closeCover = "close_cover"
    static let stopCover = "stop_cover"
    static let lock = "lock"
    static let unlock = "unlock"
    static let setTemperature = "set_temperature"
}
