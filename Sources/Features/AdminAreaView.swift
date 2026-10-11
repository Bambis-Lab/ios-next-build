import SwiftUI

struct AdminAreaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let appModel: AppModel?
    @State private var model = AdminControlModel()
    @State private var runtime = IOSNextRuntime.shared
    @State private var isPresentingConfiguration = false
    @State private var isPresentingFactoryPreview = false
    @State private var isLockingControlCenter = false
    @State private var dismissAfterLock = false

    init(appModel: AppModel? = nil) {
        self.appModel = appModel
    }

    var body: some View {
        ZStack {
            OwnerBackground()
            NavigationStack {
                content
                    .navigationTitle("Control Center")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Schließen") { requestClose() }
                                .disabled(isLockingControlCenter)
                        }
                        if case .unlocked = model.state {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                NavigationLink {
                                    OwnerNotificationsView(model: model)
                                } label: {
                                    Image(systemName: model.ownerAttentionCount > 0 || model.ownerOpenTicketCount > 0 ? "bell.badge.fill" : "bell")
                                }
                                .accessibilityLabel("Owner-Meldungen")

                                Button("Sperren", systemImage: "lock.fill") {
                                    dismissAfterLock = false
                                    isLockingControlCenter = true
                                }
                                .labelStyle(.iconOnly)
                                .disabled(isLockingControlCenter)
                            }
                        }
                    }
            }
            .background(Color.clear)
        }
        .interactiveDismissDisabled(model.state == .unlocking || isLockingControlCenter)
        .alert("Owner-Aktion fehlgeschlagen", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "Unbekannter Fehler")
        }
        .sheet(isPresented: $isPresentingConfiguration) {
            AdminConfigurationView(model: model)
        }
        .sheet(isPresented: $isPresentingFactoryPreview) {
            NavigationStack { FactoryPreviewView() }
        }
        .onAppear {
            let active = scenePhase == .active
            model.setPollingActive(active)
            runtime.setRunnerPollingActive("control-center", active: active)
        }
        .onDisappear {
            model.setPollingActive(false)
            runtime.setRunnerPollingActive("control-center", active: false)
        }
        .onChange(of: scenePhase) { _, phase in
            let active = phase == .active
            model.setPollingActive(active)
            runtime.setRunnerPollingActive("control-center", active: active)
            if active, case .unlocked = model.state {
                Task { await model.refreshStatusV2() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notConfigured:
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--visual-owner-locked") {
                lockedSurface(message: "Demonstration: Owner Control ist lokal gesperrt.", authenticating: false)
                    .accessibilityIdentifier("visual-owner-locked")
            } else {
                preconnectionSurface
            }
#else
            preconnectionSurface
#endif
        case .locked:
            lockedSurface(message: "Der Bereich ist lokal gesperrt.", authenticating: false)
        case .unlocking:
            lockedSurface(message: "Der Bereich ist lokal gesperrt.", authenticating: true)
        case .unlocked:
            IOSNextControlCenterLockHost(isLocking: isLockingControlCenter, onFinished: finishLock) {
                IOSNextControlCenterUnlockHost {
                    OwnerControlView(
                        model: model,
                        capabilities: model.ownerCapabilityRegistry,
                        appModel: appModel,
                        runnerModel: runtime.runnerModel
                    )
                }
            }
        case let .failed(message):
            lockedSurface(message: message, authenticating: false)
        }
    }

    /// Read-only setup overview. Never claims a successful Owner login.
    private var preconnectionSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("OWNER · CONTROL CENTER", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Deine Verwaltung.\nDeine Freigaben.")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Schon vor der Anmeldung erreichbar. Live-Daten und Aktionen erst nach bestätigter Owner-Berechtigung.")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.82))
                }
                .padding(.bottom, 4)

                OwnerStatusRow(
                    title: "Owner Backend",
                    detail: "Verbindung noch nicht eingerichtet",
                    symbol: "person.badge.key.fill",
                    value: "Setup",
                    tint: .indigo
                )
                OwnerStatusRow(
                    title: "Geräteauthentifizierung",
                    detail: "Face ID und serverseitige Gerätebindung nach dem Verbinden",
                    symbol: "lock.shield.fill",
                    value: "Geschützt",
                    tint: .blue
                )
                VStack(alignment: .leading, spacing: 12) {
                    Button("Control Center einrichten") {
                        isPresentingConfiguration = true
                    }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("control-center-setup-action")
                    Button("Factory Vorschau") {
                        isPresentingFactoryPreview = true
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("factory-preview-entry")
                    Text("Factory und Runner können separat verbunden werden. Keine Freigabe ohne Anmeldung.")
                        .font(.footnote)
                        .foregroundStyle(Color.primary.opacity(0.78))
                }
                .padding(17)
                .ios27ContentSurface(radius: 22)
            }
            .frame(maxWidth: 670)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("control-center-unconfigured")
    }

    private func lockedSurface(message: String, authenticating: Bool) -> some View {
        VStack(spacing: 12) {
            IOSNextControlCenterLockedSurface(
                message: message,
                isAuthenticating: authenticating,
                onUnlock: { Task { await model.unlock() } },
                onConfigure: { isPresentingConfiguration = true }
            )
                .frame(maxHeight: .infinity)
            Label(
                "Owner-Aktionen bleiben bis zur bestätigten Geräteauthentifizierung und Serverfreigabe gesperrt.",
                systemImage: "lock.shield.fill"
            )
                .font(.footnote)
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(maxWidth: 670, alignment: .leading)
                .padding(16)
                .ios27ContentSurface(radius: 18)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .accessibilityIdentifier("owner-locked-security-note")
        }
    }

    private func requestClose() {
        guard !isLockingControlCenter else { return }
        if case .unlocked = model.state {
            dismissAfterLock = true
            isLockingControlCenter = true
        } else {
            model.lock()
            dismiss()
        }
    }

    private func finishLock() {
        model.lock()
        isLockingControlCenter = false
        if dismissAfterLock {
            dismissAfterLock = false
            dismiss()
        }
    }
}

private struct AdminConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    let model: AdminControlModel
    @State private var endpoint = AdminControlConfiguration.suggestedEndpoint
    @State private var ownerToken = ""
    @State private var enrollmentSecret = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Owner-Backend") {
                    TextField("https://admin.example.com/", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Owner-Token", text: $ownerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Geräte-Kopplungscode (nur erste Kopplung)", text: $enrollmentSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Owner-Token und optionaler Geräte-Kopplungscode werden im iOS-Schlüsselbund gespeichert. Der Kopplungscode wird nach erfolgreicher Gerätebindung gelöscht. Der Server muss für `/v1/admin/session` die Rolle `owner` bestätigen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Control-Center-Zugang entfernen", role: .destructive) {
                        model.removeConfiguration()
                        dismiss()
                    }
                }
            }
            .ownerManagementBackground()
            .background(OwnerBackground())
            .navigationTitle("Owner-Zugang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        do {
                            try model.configure(endpoint: endpoint, ownerToken: ownerToken, enrollmentSecret: enrollmentSecret)
                            dismiss()
                            Task { await model.unlock() }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(endpoint.isEmpty || ownerToken.isEmpty)
                }
            }
        }
    }
}
