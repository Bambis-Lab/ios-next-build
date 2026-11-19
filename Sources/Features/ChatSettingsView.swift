import SwiftUI

/// This is the actual destination of the inbox gear. It never selects a chat
/// recipient and never presents a message composer just to configure a relay.
struct ChatSettingsView: View {
    let appModel: AppModel
    let chatModel: ChatModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingTechnicalConfiguration = false
    @State private var confirmV2=false

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
                    Text("Nachrichten werden nur nach bestätigter Relay-Sitzung gesendet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if appModel.familyBrokerConfigured {
                    Section("Lokaler Chatverlauf") {
                        LabeledContent("Speicher",value:chatModel.historyUsesV2 ? "V2 · verschlüsselte Datenbank" : "V1 / noch nicht geöffnet")
                        if chatModel.historyMigrationInProgress {
                            ProgressView("Verschlüsselten Verlauf überprüfen …")
                        } else if !chatModel.historyUsesV2 {
                            Button("Auf V2 umstellen",systemImage:"lock.shield") {confirmV2=true}
                                .disabled(!chatModel.canActivateHistoryV2(appModel))
                                .accessibilityIdentifier("chat-settings-history-v2")
                        }
                        if let notice=chatModel.historyMigrationNotice {Text(notice).font(.caption)}
                        Text("Einmalige lokale Umstellung nach Gerätebestätigung. Das Originalarchiv bleibt erhalten; nach Aktivierung ist kein automatischer Rückfall möglich.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
            .confirmationDialog("Verschlüsselten Chatverlauf umstellen?",isPresented:$confirmV2,titleVisibility:.visible) {
                Button("V2 einmalig aktivieren") {
                    Task {await chatModel.activateHistoryV2(using:appModel)}
                }
                Button("Abbrechen",role:.cancel) {}
            } message: {
                Text("Empfang und Versand werden während der Prüfung pausiert. Das Originalarchiv wird nicht gelöscht. Die Aktivierung ist nicht automatisch rückgängig zu machen.")
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
