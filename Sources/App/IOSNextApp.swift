import AppIntents
import SwiftUI

@main
struct IOSNextApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = AppModel()

    init() {
        IOSNextAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(appModel: appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active
            appModel.setApplicationActive(active)
            JarvisEngine.shared.setApplicationActive(active)
        }
    }
}
