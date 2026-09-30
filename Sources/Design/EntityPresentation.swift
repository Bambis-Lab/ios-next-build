import SwiftUI

enum EntityPresentation {
    static let controllableDomains: Set<String> = [
        "light", "switch", "media_player", "climate", "cover", "lock", "scene"
    ]

    static func symbol(for domain: String) -> String {
        switch domain {
        case "light": "lightbulb.fill"
        case "switch": "switch.2"
        case "media_player": "play.tv.fill"
        case "climate": "thermometer.medium"
        case "cover": "window.shade.open"
        case "camera": "video.fill"
        case "lock": "lock.fill"
        case "scene": "sparkles"
        case "sensor": "gauge.with.dots.needle.67percent"
        case "binary_sensor": "sensor.fill"
        default: "circle.grid.2x2.fill"
        }
    }

    static func title(for domain: String) -> String {
        switch domain {
        case "light": "Lichter"
        case "switch": "Schalter"
        case "media_player": "Medien"
        case "climate": "Klima"
        case "cover": "Abdeckungen"
        case "camera": "Kameras"
        case "lock": "Schlösser"
        case "scene": "Szenen"
        case "sensor": "Sensoren"
        case "binary_sensor": "Statussensoren"
        default: domain.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }
}
