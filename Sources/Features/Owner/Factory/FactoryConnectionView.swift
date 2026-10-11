import SwiftUI
import AuthenticationServices

/// Connection is opt-in; the dashboard is fully navigable before login.
struct FactoryConnectionView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    let model: FactoryConnectionModel

    @State private var authenticating = false
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                Label("Factory MCP · OAuth 2.1", systemImage: "network.badge.shield.half.filled")
                    .font(.headline)
                Text("Die App meldet sich direkt über den Browser am Factory-Gateway an. Kein Passwort wird in der App abgefragt oder gespeichert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Factory Gateway") {
                TextField("HTTPS-MCP-Endpunkt", text: Binding(
                    get: { model.endpoint },
                    set: { model.endpoint = $0 }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("factory-endpoint")

                TextField("Registrierte Client-ID (optional)", text: Binding(
                    get: { model.registeredClientID },
                    set: { model.registeredClientID = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Text("Bei leerer Client-ID versucht die App eine dynamische OAuth-Client-Registrierung. Die sichere PKCE-S256-Anmeldung erfolgt anschließend im Systembrowser.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Label("Factory verbinden", systemImage: "arrow.right.circle.fill")
                        Spacer()
                        if authenticating { ProgressView() }
                    }
                }
                .disabled(authenticating)
                .accessibilityIdentifier("factory-connect")
                if model.phase != .disconnected {
                    Button("Verbindung entfernen", role: .destructive) {
                        model.disconnect()
                        dismiss()
                    }
                }
            }
            Section("Sicherheit") {
                Label("OAuth PKCE S256 und serverseitige Berechtigungen", systemImage: "lock.shield")
                Label("Gerätegebundene Token im iOS-Schlüsselbund", systemImage: "key.fill")
                Label("Ausschließlich fest erlaubte lesende MCP-Tools", systemImage: "eye")
                Label("Keine freien Befehle und keine Factory-Schreibaktionen", systemImage: "hand.raised")
            }
            .font(.footnote)
        }
        .scrollContentBackground(.hidden)
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Factory verbinden")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Factory-Verbindung", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Unbekannter Fehler")
        }
    }

    private func connect() async {
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        do {
            let authorization = try await model.beginAuthorization()
            let callback = try await webAuthenticationSession.authenticate(
                using: authorization.authorizationURL, callbackURLScheme: "iosnext"
            )
            try await model.finishAuthorization(callback: callback, original: authorization)
            dismiss()
        } catch {
            model.cancelAuthorization()
            if !(error is CancellationError) {
                alertMessage = error.localizedDescription
            }
        }
    }
}
