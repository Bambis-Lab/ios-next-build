import SwiftUI

struct ConnectionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let appModel: AppModel
    @State private var serverAddress = ""
    @State private var validationMessage: String?
#if DEBUG
    @State private var accessToken = ""
#endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://homeassistant.local:8123", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Sicher mit Home Assistant anmelden", systemImage: "lock.shield.fill") {
                        guard let configuration = oauthConfiguration else {
                            validationMessage = "Bitte eine gültige HTTPS-, lokale oder Tailscale-Adresse eingeben (z. B. http://192.168.178.63:8123 oder http://homeassistant.tailnet.ts.net)."
                            return
                        }
                        validationMessage = nil
                        Task { await appModel.connectOAuth(using: configuration) }
                    }
                    .disabled(appModel.connectionState == .connecting)
                } header: {
                    Text("Home-Assistant-Adresse")
                } footer: {
                    Text("HTTPS wird immer unterstützt. HTTP ist zusätzlich für lokale Home-Assistant-Adressen sowie explizite Tailscale-Adressen (100.64.0.0/10 oder *.ts.net) erlaubt. Zugangsdaten werden nur im Schlüsselbund dieses Geräts gespeichert.")
                }

#if DEBUG
                Section("Lokale Entwicklungsverbindung") {
                    SecureField("Entwicklerzugriffstoken", text: $accessToken)
                        .textInputAutocapitalization(.never)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Button("Direkt verbinden") {
                        guard let url = validatedDebugURL, !accessToken.isEmpty else { return }
                        Task { await appModel.connect(serverURL: url, accessToken: accessToken) }
                    }
                    .disabled(validatedDebugURL == nil || accessToken.isEmpty || appModel.connectionState == .connecting)
                }
#endif

                if appModel.connectionState == .connecting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Verbindung wird hergestellt …")
                        }
                    }
                }

                if case let .failed(message) = appModel.connectionState {
                    Section {
                        IOSNextErrorBanner(message: message)
                    }
                }
            }
            .navigationTitle("Verbinden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var oauthConfiguration: HomeAssistantOAuthConfiguration? {
        guard let instanceURL = HomeAssistantOAuthConfiguration.normalizedInstanceURL(from: serverAddress) else { return nil }
        return HomeAssistantOAuthConfiguration(
            instanceURL: instanceURL,
            clientID: HomeAssistantOAuthConfiguration.productionClientID
        )
    }

    private var normalizedURL: URL? {
        let value = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return URL(string: value)
    }

#if DEBUG
    private var validatedDebugURL: URL? {
        guard let url = normalizedURL, ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }
#endif
}
