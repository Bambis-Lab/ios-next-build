import SwiftUI

/// The family route has no legacy API fallback. The visible screen is scoped
/// to the current account/device/key and is destroyed on a scope change.
struct SecureTicketEntryView: View {
    let appModel: AppModel
    let chatModel: ChatModel
    var startNew = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if scenePhase == .active, let scope = chatModel.secureTicketScope(appModel) {
                    SecureTicketScreen(app: appModel, chat: chatModel, scope: scope, startNew: startNew)
                        .id(scope)
                } else {
                    ContentUnavailableView("Sichere Tickets gesperrt", systemImage: "lock.shield",
                        description: Text("Aktive Familienidentität und Geräteschlüssel erforderlich. Kein Klartext-Fallback."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
        .privacySensitive()
    }
}

private struct SecureTicketScreen: View {
    let app: AppModel
    let chat: ChatModel
    let scope: TicketScreenScope
    let startNew: Bool
    @State private var tickets: [EncryptedTicketSummary] = []
    @State private var detail: EncryptedTicketDetail?
    @State private var messages: [TicketReadableMessage] = []
    @State private var devices: [ChatIdentity] = []
    @State private var selectedDevice = ""
    @State private var number = ""
    @State private var draft = ""
    @State private var pending: TicketPendingSend?
    @State private var restoredPending = false
    @State private var creating = false
    @State private var verified = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var search = ""
    @State private var projects: [String:String] = [:]
    @State private var work: Task<Void, Never>?
    @State private var generation = UUID()

    private var active: Bool { chat.secureTicketScope(app) == scope }
    private var peer: ChatIdentity? {
        if let detail { return scope.owner ? detail.requester : detail.owner }
        return devices.first { $0.deviceID == selectedDevice }
    }

    var body: some View {
        List {
            if let errorText { Text(errorText).foregroundStyle(.secondary).accessibilityIdentifier("secure-ticket-error") }
            if busy { ProgressView("Sicherer Zugriff …") }
            if restoredPending, let pending {
                Section("Ausstehender verschlüsselter Auftrag") {
                    Text("Ticket " + String(pending.message.ticketID.prefix(8)))
                    Text("Die bereits signierte Nachricht ist lokal gesichert. Sende exakt diesen Auftrag erneut.")
                    Button("Gesicherten Auftrag erneut senden") { send() }
                        .disabled(busy).accessibilityIdentifier("secure-ticket-retry-persisted")
                }
            } else if creating || detail != nil {
                editor
            } else {
                Section("Ende-zu-Ende-verschlüsselt") {
                    if tickets.isEmpty && !busy { Text("Keine zugänglichen Tickets") }
                    ForEach(tickets.filter { item in
                        search.isEmpty || item.requester.userID.localizedStandardContains(search)
                            || item.ticketID.localizedStandardContains(search)
                            || (scope.owner && (projectTitle(item.ticketID)?.localizedStandardContains(search) == true))
                    }) { item in
                        Button {
                            launch {
                                let loaded = try await chat.secureTicketDetail(item.id, scope: scope, app: app)
                                try requireActive()
                                clearEditor()
                                detail = loaded
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(scope.owner ? item.requester.userID : "Ticket " + String(item.id.prefix(8)))
                                Text(title(item.status)).font(.caption).foregroundStyle(.secondary)
                                if scope.owner, let project = projectTitle(item.ticketID) {
                                    Text(project).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(busy)
                    }
                    if !scope.owner {
                        Button("Neues verschlüsseltes Ticket", systemImage: "square.and.pencil") { newTicket() }
                            .disabled(busy).accessibilityIdentifier("secure-ticket-new")
                    }
                }
                if scope.owner { TextField("Benutzer, Ticket-ID oder Projekt suchen", text: $search) }
                Button("Aktualisieren", systemImage: "arrow.clockwise") { load() }.disabled(busy)
            }
        }
        .navigationTitle(scope.owner ? "Owner · sichere Tickets" : "Meine sicheren Tickets")
        .navigationBarTitleDisplayMode(.inline)
        .task { restoreAndLoad() }
        .onDisappear {
            generation = UUID()
            work?.cancel()
            clearEditor()
            tickets = []
            projects = [:]
        }
    }

    @ViewBuilder private var editor: some View {
        if creating {
            Section("Empfänger") {
                Picker("Owner-Gerät", selection: $selectedDevice) {
                    Text("Gerät auswählen").tag("")
                    ForEach(devices, id: \.deviceID) { device in Text(device.deviceID).tag(device.deviceID) }
                }.disabled(busy || pending != nil)
            }
        }
        if let detail {
            Section("Status") {
                Text(title(detail.status))
                if scope.owner && verified {
                    ForEach([EncryptedTicketStatus.open, .inProgress, .resolved], id: \.rawValue) { value in
                        Button(title(value)) {
                            launch {
                                let next = try await chat.secureTicketStatus(value, id: detail.ticketID, scope: scope, app: app)
                                try requireActive()
                                try showDetail(next)
                            }
                        }.disabled(busy || pending != nil)
                    }
                }
            }
        }
        if scope.owner, verified, let detail {
            Section("Lokale Projektzuordnung") {
                Picker("Projekt", selection: Binding(
                    get: { projects[detail.ticketID] ?? "" },
                    set: { selection in
                        launch {
                            try await chat.assignSecureTicketProject(selection.isEmpty ? nil : selection,
                                ticket: detail, scope: scope, app: app)
                            try requireActive()
                            projects[detail.ticketID] = selection.isEmpty ? nil : selection
                        }
                    })) {
                    Text("Nicht zugeordnet").tag("")
                    ForEach(ProjectRegistry.projects) { project in Text(project.title).tag(project.id) }
                }
                .disabled(busy || pending != nil)
                .accessibilityIdentifier("secure-ticket-local-project")
                Text("Nur verschlüsselt auf diesem Gerät gespeichert. Keine Weiterleitung und kein Arbeitsauftrag.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Schlüsselprüfung") {
            Text("Vergleiche die Sicherheitsnummer des anderen Geräts persönlich oder über einen bereits vertrauenswürdigen Kanal.")
                .font(.caption)
            TextField("Bestätigte Sicherheitsnummer", text: $number)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .disabled(busy || pending != nil || verified)
                .accessibilityIdentifier("secure-ticket-safety-number")
            if let detail, !verified {
                Button("Verlauf entschlüsseln") {
                    do { try showDetail(detail) } catch { errorText = "Schlüssel oder Nachrichten konnten nicht bestätigt werden." }
                }.disabled(busy || number.isEmpty)
            }
        }
        if verified {
            Section("Lokal entschlüsselter Verlauf") {
                ForEach(messages) { item in
                    VStack(alignment: .leading) {
                        Text(item.own ? "Du" : "Gegenüber").font(.caption)
                        Text(item.text).textSelection(.enabled)
                    }
                }
            }
        }
        if creating || verified {
            Section("Verschlüsselte Nachricht") {
                TextEditor(text: $draft).frame(minHeight: 100)
                    .disabled(busy || pending != nil).accessibilityIdentifier("secure-ticket-message")
                Button(pending == nil ? "Verschlüsselt senden" : "Identischen Auftrag erneut senden") { send() }
                    .disabled(busy || (pending == nil && (peer == nil || number.isEmpty ||
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf8.count > 16000)))
                    .accessibilityIdentifier("secure-ticket-send")
                if pending != nil {
                    Text("Empfang noch nicht bestätigt. Derselbe signierte Auftrag bleibt verschlüsselt gespeichert.")
                        .font(.caption)
                }
            }
        }
        Button("Zur Übersicht") { clearEditor(); load() }.disabled(busy || pending != nil)
    }

    private func projectTitle(_ ticketID: String) -> String? {
        guard let id = projects[ticketID] else { return nil }
        return ProjectRegistry.projects.first(where: { $0.id == id })?.title
    }

    private func refreshProjects() async throws {
        guard scope.owner else { return }
        let local = try await chat.secureTicketProjects(scope, app: app)
        try requireActive()
        projects = local
    }

    private func title(_ status: EncryptedTicketStatus) -> String {
        switch status { case .open: "Offen"; case .inProgress: "In Arbeit"; case .resolved: "Erledigt" }
    }

    private func requireActive() throws {
        try Task.checkCancellation()
        guard active else { throw ChatError.authenticationFailed }
    }

    private func launch(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy, active else { return }
        busy = true
        errorText = nil
        let attempt = generation
        work = Task { @MainActor in
            defer { if generation == attempt { busy = false; work = nil } }
            do { try requireActive(); try await operation(); try requireActive() }
            catch {
                if generation == attempt && active && !Task.isCancelled {
                    errorText = "Sicherer Ticketzugriff fehlgeschlagen. Kein Klartext-Fallback."
                }
            }
        }
    }

    private func restoreAndLoad() {
        launch {
            let saved = try await chat.restoreSecureTicketPending(scope, app: app)
            try requireActive()
            try await refreshProjects()
            if let saved {
                pending = saved
                restoredPending = true
                return
            }
            if startNew && !scope.owner {
                let options = try await chat.secureTicketOwnerDevices(scope, app: app)
                try requireActive()
                devices = options
                creating = true
            } else {
                let items = try await chat.secureTicketList(scope, app: app)
                try requireActive()
                tickets = items
            }
        }
    }

    private func load() {
        launch {
            let items = try await chat.secureTicketList(scope, app: app)
            try requireActive()
            tickets = items
            try await refreshProjects()
        }
    }

    private func newTicket() {
        launch {
            let options = try await chat.secureTicketOwnerDevices(scope, app: app)
            try requireActive()
            clearEditor()
            devices = options
            creating = true
        }
    }

    private func showDetail(_ loaded: EncryptedTicketDetail) throws {
        verified = false
        messages = []
        let decoded = try chat.openSecureTicket(loaded, number: number, scope: scope, app: app)
        detail = loaded
        messages = decoded
        verified = true
        creating = false
    }

    private func send() {
        launch {
            let request: TicketPendingSend
            if let existing = pending { request = existing }
            else {
                guard let peer else { throw ChatError.invalidEnvelope }
                request = try await chat.prepareSecureTicket(text: draft, detail: detail, peer: peer,
                    number: number, scope: scope, app: app)
                try requireActive()
                try await chat.stageSecureTicket(request, scope: scope, app: app)
                try requireActive()
                pending = request
                draft = ""
            }
            let result = try await chat.submitSecureTicket(request, scope: scope, app: app)
            try requireActive()
            // Clear the pending request after the exact server receipt even
            // when a subsequently invalid history prevents decryption.
            pending = nil
            creating = false
            verified = false
            messages = []
            detail = result
            if restoredPending {
                restoredPending = false
                number = ""
                // On reopening, require explicit peer verification before
                // displaying plaintext even after the exact retry succeeds.
            } else {
                try showDetail(result)
            }
        }
    }

    private func clearEditor() {
        detail = nil; messages = []; devices = []; selectedDevice = ""
        number = ""; draft = ""; pending = nil; creating = false; verified = false; restoredPending = false
    }
}
