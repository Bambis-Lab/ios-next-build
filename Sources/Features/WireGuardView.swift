import SwiftUI
import UniformTypeIdentifiers

struct WireGuardView: View {
    @State private var controller = WireGuardTunnelController()
    @State private var isImporting = false
    @State private var isRemoving = false
    @State private var lastError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                HStack {
                    Label("iOS Next WireGuard", systemImage: "network.badge.shield.half.filled")
                    Spacer()
                    statusLabel
                }
                switch controller.state {
                case .connected, .connecting:
                    Button("VPN trennen", systemImage: "stop.circle") { controller.disconnect() }
                case .disconnected:
                    Button("VPN verbinden", systemImage: "play.circle") {
                        Task { await controller.connect() }
                    }
                default:
                    EmptyView()
                }
                Button("Status aktualisieren", systemImage: "arrow.clockwise") {
                    Task { await controller.refresh() }
                }
            } header: {
                Text("Fernzugriff")
            } footer: {
                Text("Home Assistant, Runner, Owner Control und Chat bleiben privat im Heimnetz. WireGuard stellt den verschlüsselten Zugang ohne Nabu Casa her.")
            }

            Section {
                Toggle("Automatisch verbinden", isOn: Bindable(controller).isOnDemandEnabled)
                Button("WireGuard-Konfiguration importieren", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
            } header: {
                Text("Einrichtung")
            } footer: {
                Text("Die .conf-Datei wird geprüft und direkt in der gemeinsamen, gerätegebundenen Keychain abgelegt. iOS zeigt beim ersten Einrichten zwingend seinen VPN-Systemdialog.")
            }

            Section("Sicherheitsregeln") {
                Label("Private Keys nie in UserDefaults oder Logs", systemImage: "key.fill")
                Label("Unbekannte wg-quick-Anweisungen werden blockiert", systemImage: "checkmark.shield.fill")
                Label("On-Demand nach einmaliger iOS-Freigabe", systemImage: "bolt.shield.fill")
                Label("Split- oder Full-Tunnel folgt AllowedIPs", systemImage: "arrow.triangle.branch")
            }

            if let failedStateMessage {
                Section { IOSNextErrorBanner(message: failedStateMessage) }
            }

            if controller.state != .notConfigured {
                Section {
                    Button("VPN-Konfiguration entfernen", role: .destructive) {
                        isRemoving = true
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .iosNextManagementBackground()
        .navigationTitle("WireGuard")
        .navigationBarTitleDisplayMode(.inline)
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
        }
        .task { await controller.refresh() }
        .onChange(of: controller.isOnDemandEnabled) { _, _ in
            Task { await controller.updateOnDemand() }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "conf") ?? .plainText, .plainText]
        ) { result in
            Task { await importConfiguration(result) }
        }
        .confirmationDialog(
            "WireGuard-Konfiguration entfernen?",
            isPresented: $isRemoving,
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) {
                Task { await controller.removeConfiguration() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Tunnel wird getrennt und die private Konfiguration aus der Keychain gelöscht.")
        }
        .alert("WireGuard-Fehler", isPresented: Binding(
            get: { lastError != nil },
            set: { if !$0 { lastError = nil } }
        )) {
            Button("OK") { lastError = nil }
        } message: {
            Text(lastError ?? "Unbekannter Fehler")
        }
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusText: String {
        switch controller.state {
        case .unavailable: "Nicht verfügbar"
        case .notConfigured: "Nicht eingerichtet"
        case .disconnected: "Getrennt"
        case .connecting: "Verbindet"
        case .connected: "Verbunden"
        case .disconnecting: "Trennt"
        case .failed: "Fehler"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        case .failed: .red
        default: .secondary
        }
    }

    private var failedStateMessage: String? {
        if case let .failed(message) = controller.state { return message }
        return nil
    }

    private func importConfiguration(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.uncached])
            guard data.count <= 64 * 1024, let text = String(data: data, encoding: .utf8) else {
                throw WireGuardConfigurationError.invalidLine
            }
            try await controller.install(configurationText: text)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
