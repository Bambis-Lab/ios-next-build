import AVFoundation
import LocalAuthentication
import Speech
import SwiftUI
import UserNotifications

struct PermissionsCenterView: View {
    let appModel: AppModel
    @State private var notificationStatus = "Wird geprüft …"
    @State private var biometricStatus = "Wird geprüft …"

    var body: some View {
        List {
            Section("Sprache & Medien") {
                PermissionStatusRow(title: "Mikrofon", symbol: "mic.fill", value: microphoneStatus)
                PermissionStatusRow(title: "Spracherkennung", symbol: "waveform", value: speechStatus)
                PermissionStatusRow(title: "Kamera", symbol: "camera.fill", value: cameraStatus)
            }

            Section {
                PermissionStatusRow(title: "Face ID", symbol: "faceid", value: biometricStatus)
                PermissionStatusRow(title: "Mitteilungen", symbol: "bell.fill", value: notificationStatus)
                PermissionStatusRow(
                    title: "Lokales Netzwerk",
                    symbol: "network",
                    value: appModel.isConnected ? "Verbindung aktiv" : "Von iOS verwaltet"
                )
            } header: {
                Text("Sicherheit & System")
            } footer: {
                Text("Diese Ansicht liest nur den aktuellen Berechtigungszustand. Sie fordert keine Berechtigung an und verändert keine Systemeinstellung.")
            }

            Section("Jarvis") {
                PermissionStatusRow(
                    title: "On-Device-Erkennung",
                    symbol: "waveform.badge.mic",
                    value: JarvisEngine.shared.onDeviceRecognitionAvailable ? "Bereit" : "Noch nicht bestätigt"
                )
                Text("Jarvis kann Wake Listening nur starten, wenn Mikrofon und Spracherkennung erlaubt sind und iOS lokale Spracherkennung für das Gerät bereitstellt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .iosNextManagementBackground()
        .navigationTitle("Berechtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSystemPermissions() }
    }

    private var microphoneStatus: String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: "Erlaubt"
        case .denied: "Nicht erlaubt"
        case .undetermined: "Noch nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: "Erlaubt"
        case .denied: "Nicht erlaubt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Noch nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private var cameraStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "Erlaubt"
        case .denied: "Nicht erlaubt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Noch nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    @MainActor
    private func refreshSystemPermissions() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = Self.notificationTitle(notificationSettings.authorizationStatus)

        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if available {
            biometricStatus = context.biometryType == .faceID ? "Verfügbar" : "Biometrie verfügbar"
        } else if context.biometryType == .none {
            biometricStatus = "Nicht verfügbar"
        } else {
            biometricStatus = "Nicht nutzbar"
        }
    }

    private static func notificationTitle(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Erlaubt"
        case .denied: "Nicht erlaubt"
        case .notDetermined: "Noch nicht gefragt"
        case .provisional: "Vorläufig erlaubt"
        case .ephemeral: "Temporär erlaubt"
        @unknown default: "Unbekannt"
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
