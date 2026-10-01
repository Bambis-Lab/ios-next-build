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
    }
}
