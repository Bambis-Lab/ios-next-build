import Foundation
import UIKit

/// An immutable static Blender camera and its 15 measured building anchors.
/// Does not perform networking, issue Factory commands or animate fabricated jobs.
struct FactoryWorldStaticPack: Decodable {
    struct Camera: Decodable {
        let projection: String
        let resolution_px: [Int]
        let ortho_scale: Double
    }
    struct Building: Decodable {
        let center_uv_top_left: [Double]
        let pixel_rect_top_left: [Int]
        let measured_dimensions_m: [Double]
        var uv_center: [Double] { center_uv_top_left }
    }
    struct Render: Decodable {
        let file: String
        let sha256: String
        let bytes: Int
    }
    let schema: String
    let scope: String
    let original_source_sha256: String
    let camera: Camera
    let buildings: [String: Building]
    let renders: [String: Render]
    let live_updates: Bool
    let animations: Bool
    let source_unchanged: Bool
    let visual_acceptance: String
}

/// Resources are placed inside the app during the pinned Xcode build.
/// The paired light/dark PNG content hashes are checked before Xcode asset compilation.
enum FactoryWorldStaticBundle {
    private static let identifiers = Set((1...15).map { String(format: "HB-%02d", $0) })
    static var available: Bool { load() != nil }

    static func load(bundle: Bundle = .main) -> FactoryWorldStaticPack? {
        guard let path = bundle.url(forResource: "FactoryWorldStaticManifest", withExtension: "json"),
              let data = try? Data(contentsOf: path),
              let model = try? JSONDecoder().decode(FactoryWorldStaticPack.self, from: data),
              model.schema == "factory.world.static.v1",
              model.scope == "OFFLINE_STATIC_ENTIRE_DISTRICT",
              model.visual_acceptance == "ENGINEERING_RENDER_NOT_FINAL_ART",
              model.source_unchanged && !model.live_updates && !model.animations,
              model.original_source_sha256 == "1c1e131692a3572a44de8c52dc1af3dd25644ef7304ad39636947d742f6123de",
              model.camera.projection == "ORTHO",
              model.camera.resolution_px.count == 2,
              model.camera.resolution_px[0] > 0,
              model.camera.resolution_px[1] > 0,
              model.camera.ortho_scale > 0,
              Set(model.buildings.keys) == identifiers,
              Set(model.renders.keys) == ["day","night"],
              model.renders.values.allSatisfy({ $0.sha256.count == 64 && $0.bytes > 1000 }),
              model.buildings.values.allSatisfy({
                  $0.center_uv_top_left.count == 2 &&
                  $0.center_uv_top_left.allSatisfy({ (0...1).contains($0) }) &&
                  $0.measured_dimensions_m.count == 3 &&
                  $0.measured_dimensions_m.allSatisfy({ $0 > 0 }) &&
                  $0.pixel_rect_top_left.count == 4
              }) else {
            return nil
        }
        return model
    }

    static func composite(for theme: String) -> UIImage? {
        switch theme {
        case "light": UIImage(named: "FactoryWorldDay")
        case "dark": UIImage(named: "FactoryWorldNight")
        default: nil
        }
    }
}
