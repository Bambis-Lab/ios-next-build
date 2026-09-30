import Foundation

enum HomeProfile: String, CaseIterable, Identifiable, Codable {
    case nico
    case timo
    case mika
    case juli
    case gabi

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var subtitle: String {
        switch self {
        case .nico: "Owner · Admin & Zuhause"
        case .timo: "Zimmer & Schlafzimmer"
        case .mika: "Zimmer & Medien"
        case .juli: "Dein Zuhause einrichten"
        case .gabi: "Zuhause im Überblick"
        }
    }

    var primaryArea: String {
        switch self {
        case .nico: "Nico Zimmer"
        case .timo: "Timo Zimmer"
        case .mika: "Mika Zimmer"
        case .juli, .gabi: "Zuhause"
        }
    }
}
