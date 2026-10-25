import SwiftUI

/// This is the actual destination of the inbox gear. It never selects a chat
/// recipient and never presents a message composer just to configure a relay.
struct ChatSettingsView: View {
    let appModel: AppModel
    let chatModel: ChatModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingTechnicalConfiguration = false

    private var connectionTitle: String {
        switch chatModel.state {
        case .notConfigured: "Noch nicht eingerichtet"
        case .connecting: "Verbindung wird aufgebaut"
        case .online: "Verbunden"
        case .offline: "Offline"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Verbindung") {
                    LabeledContent("Chat Relay", value: connectionTitle)
                    if case let .offline(reason) = chatModel.state {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chat-settings-offline-reason")
                    }
                    Button("Erneut verbinden", systemImage: "arrow.clockwise") {
                        Task { await chatModel.start(using: appModel) }
                    }
                    .accessibilityIdentifier("chat-settings-reconnect")
                }

                Section("Identität & Familie") {
                    LabeledContent("Home Assistant", value:
                        appModel.homeAssistantCurrentUser == nil ? "Nicht angemeldet" : "Angemeldet")
                    LabeledContent("Familienregistrierung", value:
                        appModel.registeredFamilyProfile == nil ? "Nicht bestätigt" : "Bestätigt")
                    if appModel.familyBrokerConfigured {
                        Text("Das Familienprofil und die Gerätefreigabe werden ausschließlich durch das Backend geprüft. Ein Name oder eine Profilwahl verleiht keine Owner-Rechte.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Persönlicher Legacy-Modus: Kein verifizierter Familien-Broker konfiguriert. Familienkontakte und Owner-Rechte werden dadurch nicht bestätigt.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Verschlüsselung") {
                    LabeledContent("Geräteschlüssel", value:
                        chatModel.ownSafetyNumber.isEmpty ? "Nicht bereit" : "Vorhanden")
                    Text("Nachrichten werden nur nach bestätigter Relay-Sitzung gesendet. Der lokale Verlauf wird nicht als dauerhaft gespeichert ausgegeben.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !appModel.familyBrokerConfigured {
                    Section {
                        Button("Manuelle Relay-Konfiguration", systemImage: "gearshape.2") {
                            showingTechnicalConfiguration = true
                        }
                        .accessibilityIdentifier("chat-settings-manual-relay")
                    } header: {
                        Text("Erweiterte Einstellungen")
                    } footer: {
                        Text("Nur für die persönliche Legacy-Installation. Manuelle Angaben ersetzen keine sichere Familienregistrierung.")
                    }
                }
            }
            .navigationTitle("Chat-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showingTechnicalConfiguration) {
                ChatConfigurationView(chatModel: chatModel)
            }
        }
    }
}
