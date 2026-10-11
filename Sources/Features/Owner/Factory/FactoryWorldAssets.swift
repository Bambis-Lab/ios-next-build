import Foundation
import UIKit

// Native, offline-only viewer for the immutable Factory World Blender render pack.
// Loading this manifest NEVER talks to Factory MCP or claims real-time job progress.
struct FactoryWorldPack: Decodable {
    struct Camera: Decodable {
        let resolution_px: [Int]
        let projection: String
        let ortho_scale_m: Double
    }
    struct Sprite: Decodable {
        let file: String
        let sha256: String
        let size_px: [Int]
    }
    struct Building: Decodable {
        let id: String
        let measured_size_m: [Double]
        let uv_center: [Double]
        let sprites: [String: Sprite]
        let factory_runtime: String
    }
    struct Lane: Decodable {
        let id: String
        let from: String
        let to: String
        let kind: String
        let runtime_state: String
    }
    let schema: String
    let status: String
    let runtime_status: String
    let source_sha256: String
    let camera: Camera
    let buildings: [String: Building]
    let planned_connections: [Lane]
}

enum FactoryWorldBundle {
    private static let expectedBuildingIDs = Set((1...15).map { String(format: "HB-%02d", $0) })
    static var available: Bool { load() != nil }

    static func load(bundle: Bundle = .main) -> FactoryWorldPack? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json",
                                   subdirectory: "FactoryWorld/mobile"),
              let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(FactoryWorldPack.self, from: data),
              pack.schema == "factory.world.mobile.rendered.v1",
              pack.status == "TECHNICAL_RENDER_ONLY_NOT_ART_ACCEPTED",
              pack.runtime_status == "NO_AUTHENTICATED_EVENTS_NO_ANIMATED_PACKETS",
              pack.source_sha256.count == 64,
              pack.source_sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              Set(pack.buildings.keys) == expectedBuildingIDs,
              pack.planned_connections.count == 25,
              pack.camera.projection == "ORTHOGRAPHIC",
              pack.camera.resolution_px.count == 2,
              pack.camera.resolution_px.allSatisfy({ $0 > 0 }) else { return nil }
        for (id, item) in pack.buildings {
            guard id == item.id, item.uv_center.count == 2,
                  item.uv_center.allSatisfy({ (0...1).contains($0) }),
                  item.measured_size_m.count == 3,
                  Set(item.sprites.keys) == ["light", "dark"],
                  item.factory_runtime == "NOT_CONNECTED" else { return nil }
        }
        for lane in pack.planned_connections {
            guard expectedBuildingIDs.contains(lane.from),
                  expectedBuildingIDs.contains(lane.to),
                  lane.runtime_state == "PLANNED_NOT_LIVE" else { return nil }
        }
        return pack
    }

    // Resource package contains FactoryWorld/mobile/<theme>/world_composite.png.
    // No network access or filesystem traversal; no asset synthesis.
    static func composite(for theme: String, bundle: Bundle = .main) -> UIImage? {
        guard ["light", "dark"].contains(theme),
              let url = bundle.url(forResource: "world_composite", withExtension: "png",
                                   subdirectory: "FactoryWorld/mobile/" + theme) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
