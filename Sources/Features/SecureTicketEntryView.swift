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
    @State private var creating = false
    @State private var verified = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var search = ""
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
            if creating || detail != nil {
                editor
            } else {
                Section("Ende-zu-Ende-verschlüsselt") {
                    if tickets.isEmpty && !busy { Text("Keine zugänglichen Tickets") }
                    ForEach(tickets.filter { item in
                        search.isEmpty || item.requester.userID.localizedStandardContains(search)
                            || item.ticketID.localizedStandardContains(search)
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
                            }
                        }
                        .disabled(busy)
                    }
                    if !scope.owner {
                        Button("Neues verschlüsseltes Ticket", systemImage: "square.and.pencil") { newTicket() }
                            .disabled(busy).accessibilityIdentifier("secure-ticket-new")
                    }
                }
                if scope.owner { TextField("Nach Benutzer oder Ticket-ID suchen", text: $search) }
                Button("Aktualisieren", systemImage: "arrow.clockwise") { load() }.disabled(busy)
            }
        }
        .navigationTitle(scope.owner ? "Owner · sichere Tickets" : "Meine sicheren Tickets")
        .navigationBarTitleDisplayMode(.inline)
        .task { if startNew && !scope.owner { newTicket() } else { load() } }
        .onDisappear {
            generation = UUID()
            work?.cancel()
            clearEditor()
            tickets = []
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
                    Text("Empfang noch nicht bestätigt. Wiederholung verwendet dieselbe signierte Nachricht. Beim Schließen geht dieser ausstehende Auftrag verloren.")
                        .font(.caption)
                }
            }
        }
        Button("Zur Übersicht") { clearEditor(); load() }.disabled(busy || pending != nil)
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

    private func load() {
        launch {
            let items = try await chat.secureTicketList(scope, app: app)
            try requireActive()
            tickets = items
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
            try showDetail(result)
        }
    }

    private func clearEditor() {
        detail = nil; messages = []; devices = []; selectedDevice = ""
        number = ""; draft = ""; pending = nil; creating = false; verified = false
    }
}
