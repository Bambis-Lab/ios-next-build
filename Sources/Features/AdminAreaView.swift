import SwiftUI

struct AdminAreaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let appModel: AppModel?
    @State private var model = AdminControlModel()
    @State private var runtime = IOSNextRuntime.shared
    @State private var isPresentingConfiguration = false
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
            ContentUnavailableView {
                Label("Control Center nicht eingerichtet", systemImage: "person.badge.key.fill")
            } description: {
                Text("Die Einrichtung erfordert die HTTPS-Adresse des Admin-Backends und ein serverseitiges Owner-Token.")
            } actions: {
                Button("Control Center einrichten") { isPresentingConfiguration = true }
                    .buttonStyle(.glassProminent)
            }
            .padding(24)
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

    private func lockedSurface(message: String, authenticating: Bool) -> some View {
        IOSNextControlCenterLockedSurface(
            message: message,
            isAuthenticating: authenticating,
            onUnlock: { Task { await model.unlock() } },
            onConfigure: { isPresentingConfiguration = true }
        )
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
            .navigationTitle("Control Center einrichten")
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
