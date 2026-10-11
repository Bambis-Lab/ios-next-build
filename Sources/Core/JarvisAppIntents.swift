import AppIntents

struct OpenJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Jarvis starten"
    static let description = IntentDescription("Öffnet iOS Next und aktiviert den lokalen Jarvis-Sprachmodus.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await JarvisEngine.shared.startWakeListening()
        return .result()
    }
}


private enum IOSNextNavigationRequest {
    static let defaultsKey = "iosnext.requestedAppTab"

    static func open(_ tab: String) {
        guard ["home", "rooms", "chat", "media", "system"].contains(tab) else { return }
        UserDefaults.standard.set(tab, forKey: defaultsKey)
    }
}

struct OpenIOSNextHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "iOS Next Zuhause öffnen"
    static let description = IntentDescription("Öffnet die Startseite von iOS Next.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IOSNextNavigationRequest.open("home")
        return .result()
    }
}

struct OpenIOSNextRoomsIntent: AppIntent {
    static let title: LocalizedStringResource = "iOS Next Räume öffnen"
    static let description = IntentDescription("Öffnet die Raumübersicht in iOS Next.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IOSNextNavigationRequest.open("rooms")
        return .result()
    }
}

struct OpenIOSNextMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "iOS Next Medien öffnen"
    static let description = IntentDescription("Öffnet die Medienübersicht in iOS Next.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IOSNextNavigationRequest.open("media")
        return .result()
    }
}

struct IOSNextAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenJarvisIntent(),
            phrases: [
                "Starte Jarvis in \(.applicationName)",
                "Öffne Jarvis in \(.applicationName)",
                "Jarvis mit \(.applicationName)"
            ],
            shortTitle: "Jarvis starten",
            systemImageName: "waveform.badge.mic"
        )
        AppShortcut(
            intent: OpenIOSNextHomeIntent(),
            phrases: ["Öffne Zuhause in \(.applicationName)", "Startseite von \(.applicationName)"],
            shortTitle: "Zuhause öffnen",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: OpenIOSNextRoomsIntent(),
            phrases: ["Öffne Räume in \(.applicationName)", "Zeige Räume in \(.applicationName)"],
            shortTitle: "Räume öffnen",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: OpenIOSNextMediaIntent(),
            phrases: ["Öffne Medien in \(.applicationName)", "Zeige Medien in \(.applicationName)"],
            shortTitle: "Medien öffnen",
            systemImageName: "play.tv.fill"
        )
    }
}
