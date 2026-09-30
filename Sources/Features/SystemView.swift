import Foundation
import SwiftUI

struct SystemView: View {
    let appModel: AppModel
    @State private var isPresentingControlCenter = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Home Assistant", systemImage: "house.fill")
                    Spacer()
                    ConnectionStatusLabel(state: appModel.connectionState)
                }
                Button("Entitäten aktualisieren", systemImage: "arrow.clockwise") {
                    Task { await appModel.refresh() }
                }
                .disabled(appModel.connectionState == .connecting)
                Button("Verbindung verwalten", systemImage: "link") {
                    appModel.isPresentingConnection = true
                }
            } header: {
                Text("Verbindung")
            } footer: {
                Text("Statusänderungen werden nach der Anmeldung live über die Home-Assistant-WebSocket-Verbindung empfangen.")
            }

            Section("Verwaltung") {
#if !IOSNEXT_FREE_SIDELOAD
                NavigationLink {
                    WireGuardView()
                } label: {
                    Label("Fernzugriff · WireGuard", systemImage: "network.badge.shield.half.filled")
                }
#endif
                NavigationLink {
                    ScenesView(appModel: appModel)
                } label: {
                    Label("Szenen", systemImage: "sparkles")
                }
                NavigationLink {
                    GlobalSearchView(appModel: appModel)
                } label: {
                    Label("Suche", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    JarvisView(engine: JarvisEngine.shared)
                } label: {
                    HStack {
                        Label("Jarvis", systemImage: "waveform.badge.mic")
                        Spacer()
                        Text(JarvisEngine.shared.state.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                NavigationLink {
                    LiveOperationsView()
                } label: {
                    Label("Master Runtime Live", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("system-master-runtime-live")
                Button {
                    isPresentingControlCenter = true
                } label: {
                    HStack {
                        Label("Control Center", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                NavigationLink {
                    PermissionsCenterView(appModel: appModel)
                } label: {
                    Label("Berechtigungen", systemImage: "checkmark.shield.fill")
                }
                NavigationLink {
                    DiagnosticsView(appModel: appModel)
                } label: {
                    Label("Diagnose", systemImage: "stethoscope")
                }
            }

            Section("App") {
                LabeledContent("Entitäten", value: "\(appModel.entities.count)")
                LabeledContent("Oberfläche", value: "iOS 27")
                LabeledContent("Technik", value: "SwiftUI")
            }

            Section {
                Button("Verbindung und Zugangsdaten entfernen", role: .destructive) {
                    appModel.forgetConnection()
                }
            } footer: {
                Text("Entfernt lokale Schlüsselbunddaten. Home Assistant selbst wird nicht verändert.")
            }
        }
        .listStyle(.insetGrouped)
        .iosNextManagementBackground()
        .navigationTitle("Mehr")
        .fullScreenCover(isPresented: $isPresentingControlCenter) {
            AdminAreaView(appModel: appModel)
        }
    }
}

private struct DiagnosticsView: View {
    let appModel: AppModel

    private static let cachedSourceCommit: String? = {
        guard
            let url = Bundle.main.url(forResource: "build_info", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["source_commit"] as? String
    }()

    var body: some View {
        List {
            Section("Verbindung") {
                LabeledContent("Status", value: appModel.connectionState.statusText)
                LabeledContent("Geladene Entitäten", value: "\(appModel.entities.count)")
                LabeledContent(
                    "Nicht erreichbar",
                    value: "\(appModel.entities.filter { !$0.isAvailable }.count)"
                )
            }
            Section("Jarvis") {
                LabeledContent("Status", value: JarvisEngine.shared.state.title)
                LabeledContent("Wake Word", value: JarvisEngine.shared.wakeWord)
                LabeledContent("On-Device", value: JarvisEngine.shared.onDeviceRecognitionAvailable ? "Bereit" : "Unbestätigt")
                LabeledContent("Audio Drops", value: "\(JarvisEngine.shared.audioDropCount)")
            }
            Section("Build") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                if let sourceCommit = Self.cachedSourceCommit {
                    LabeledContent("Commit", value: String(sourceCommit.prefix(12)))
                }
            }
            Section("Datenschutz") {
                Label("Tokens werden nie in der Diagnose angezeigt.", systemImage: "lock.shield.fill")
                Label("Keine Home-Assistant-Konfiguration wird durch Diagnose verändert.", systemImage: "checkmark.shield.fill")
                Label("Jarvis verwendet keinen automatischen Server-Fallback für das Wake Word.", systemImage: "waveform.badge.mic")
            }
        }
        .iosNextManagementBackground()
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
