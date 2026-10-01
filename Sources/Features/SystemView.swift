import Foundation
import SwiftUI
import UIKit

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
                .accessibilityIdentifier("system-live-operations")
                NavigationLink {
                    MasterCapabilitiesView()
                } label: {
                    Label("Master Zugriff", systemImage: "checkmark.shield.fill")
                }
                .accessibilityIdentifier("system-master-capabilities")
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
    @State private var runtime = IOSNextRuntime.shared
    @State private var didCopy = false

    private static let cachedSourceCommit: String? = {
        guard
            let url = Bundle.main.url(forResource: "build_info", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["source_commit"] as? String
    }()

    private var governance: MasterGovernanceSnapshot {
        .sourceOnly(
            observedAt: runtime.liveOperationsModel.lastEventAt ?? runtime.runnerModel.masterRuntimeSnapshot.updatedAt
        )
    }

    var body: some View {
        List {
            Section("Verbindungen") {
                diagnosticRow("Home Assistant", value: appModel.connectionState.statusText, symbol: "house.fill")
                diagnosticRow("Runner Control", value: runnerStatusText, symbol: "server.rack")
                diagnosticRow("Runtime Live", value: runnerLiveStatusText, symbol: "waveform.path.ecg")
                diagnosticRow("Vorgänge", value: liveOperationsStatusText, symbol: "bolt.horizontal.fill")
                diagnosticRow("Chat Relay", value: chatStatusText, symbol: "message.fill")
            }

            Section("Master Governance") {
                LabeledContent("Authority", value: governance.authority)
                LabeledContent("READ_ONLY", value: governance.readOnlyStatus.availability.title)
                LabeledContent("Writes", value: "Gesperrt")
                LabeledContent("Precheck", value: governance.precheckSupported ? "Verfügbar" : "Vorbereitet")
                LabeledContent("Verify / Rollback", value: governance.verifySupported && governance.rollbackSupported ? "Verfügbar" : "Vorbereitet")
                if let observedAt = governance.observedAt {
                    LabeledContent("Datenstand", value: relativeAge(observedAt))
                }
            }

            Section("Home Assistant") {
                LabeledContent("Geladene Entitäten", value: "\(appModel.entities.count)")
                LabeledContent(
                    "Nicht erreichbar",
                    value: "\(appModel.entities.filter { !$0.isAvailable }.count)"
                )
            }

            Section("Master Runtime") {
                let snapshot = runtime.runnerModel.masterRuntimeSnapshot
                LabeledContent("Status", value: masterRuntimeStatus(snapshot.availability))
                LabeledContent("Vorgänge", value: "\(runtime.liveOperationsModel.activeOperations.count)")
                LabeledContent("Runner", value: "\(snapshot.registeredRunners)")
                if let disk = snapshot.diskPercent {
                    LabeledContent("Disk", value: String(format: "%.1f%%", disk))
                }
                if let updatedAt = snapshot.updatedAt {
                    LabeledContent("Letztes Runtime-Event", value: relativeAge(updatedAt))
                }
                if let liveAt = runtime.liveOperationsModel.lastEventAt {
                    LabeledContent("Letztes Vorgangs-Event", value: relativeAge(liveAt))
                }
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

            Section {
                Button(didCopy ? "Diagnose kopiert" : "Sanitisierte Diagnose kopieren", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = sanitizedDiagnosticText
                    didCopy = true
                }
            } footer: {
                Text("Der Export enthält Status-, Authority-, Freshness- und Build-Metadaten, aber keine Tokens, Schlüssel, Nachrichten, Befehle oder Dateiinhalte.")
            }

            Section("Datenschutz") {
                Label("Tokens werden nie in der Diagnose angezeigt.", systemImage: "lock.shield.fill")
                Label("Keine Home-Assistant-Konfiguration wird durch Diagnose verändert.", systemImage: "checkmark.shield.fill")
                Label("Master Schreib- und Host-Capabilities bleiben in iOS Next 1.2 gesperrt.", systemImage: "hand.raised.fill")
                Label("Jarvis verwendet keinen automatischen Server-Fallback für das Wake Word.", systemImage: "waveform.badge.mic")
            }
        }
        .iosNextManagementBackground()
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runtime.runnerModel.refresh()
            runtime.liveOperationsModel.refreshRuntimeConfiguration()
            runtime.liveOperationsModel.startIfNeeded()
        }
    }

    private func diagnosticRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var runnerStatusText: String {
        switch runtime.runnerModel.state {
        case .notConfigured: "Nicht konfiguriert"
        case .loading: "Verbinden"
        case .ready: "Online"
        case .failed: "Offline"
        }
    }

    private var runnerLiveStatusText: String {
        switch runtime.runnerModel.commanderLiveState.connection {
        case .live: "Live"
        case .syncing, .connecting: "Verbinden"
        case .reconnecting: "Neu verbinden"
        case .degraded: "Eingeschränkt"
        case .disconnected: "Offline"
        case .unconfigured: "Nicht konfiguriert"
        }
    }

    private var liveOperationsStatusText: String {
        switch runtime.liveOperationsModel.connectionState {
        case .live: "Live"
        case .syncing, .connecting: "Verbinden"
        case .reconnecting: "Neu verbinden"
        case .degraded: "Eingeschränkt"
        case .offline: "Offline"
        case .unconfigured: "Nicht konfiguriert"
        }
    }

    private var chatStatusText: String {
        switch runtime.chatModel.state {
        case .notConfigured: "Nicht konfiguriert"
        case .connecting: "Verbinden"
        case .online: "Online"
        case .offline: "Offline"
        }
    }

    private func masterRuntimeStatus(_ availability: MasterRuntimeAvailability) -> String {
        switch availability {
        case .ready: "Live"
        case .degraded: "Eingeschränkt"
        case .unavailable: "Offline"
        }
    }

    private func relativeAge(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "gerade eben" }
        if seconds < 60 { return "vor \(seconds)s" }
        if seconds < 3_600 { return "vor \(seconds / 60)m" }
        return "vor \(seconds / 3_600)h"
    }

    private var sanitizedDiagnosticText: String {
        let snapshot = runtime.runnerModel.masterRuntimeSnapshot
        return [
            "iOS Next \(appVersion) (\(appBuild))",
            "Home Assistant: \(appModel.connectionState.statusText)",
            "Runner Control: \(runnerStatusText)",
            "Runtime Live: \(runnerLiveStatusText)",
            "Operations Live: \(liveOperationsStatusText)",
            "Active Operations: \(runtime.liveOperationsModel.activeOperations.count)",
            "Chat Relay: \(chatStatusText)",
            "Master Authority: \(governance.authority)",
            "Master READ_ONLY: \(governance.readOnlyStatus.availability.title)",
            "Master Writes: locked",
            "Registered Runners: \(snapshot.registeredRunners)",
            "Busy Runners: \(snapshot.busyRunners)",
            "Entities: \(appModel.entities.count)",
            "Unavailable Entities: \(appModel.entities.filter { !$0.isAvailable }.count)",
            "Source Commit: \(Self.cachedSourceCommit.map { String($0.prefix(12)) } ?? "—")"
        ].joined(separator: "\n")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
