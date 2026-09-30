import SwiftUI

@main
struct IOSNextApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(appModel: appModel)
        }
    }
}
