import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    let appModel: AppModel
    let chatModel: ChatModel
    @State private var recorder = InMemoryVoiceRecorder()
    @State private var imageSelection: PhotosPickerItem?
    @State private var videoSelection: PhotosPickerItem?
    @State private var isPresentingCamera = false
    @State private var isPresentingConfiguration = false
    @State private var isPresentingSecurity = false
    @State private var isPresentingSupportTicket = false
    @State private var voicePressIsActive = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            connectionBanner
            messageList
            composer
        }
        .background(IOSNextBackground())
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay {
                        Label("Chat geschützt", systemImage: "lock.fill")
                            .font(.headline)
                    }
            }
        }
        .navigationTitle(chatModel.recipientUserID.isEmpty ? "Chat" : chatModel.recipientUserID)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Sicherheit", systemImage: "lock.shield.fill") {
                        isPresentingSecurity = true
                    }
                    Button("Chat einrichten", systemImage: "gearshape") {
                        isPresentingConfiguration = true
                    }
                    if chatModel.accessRole == .member {
                        Button("Ticket an Owner", systemImage: "ticket.fill") {
                            isPresentingSupportTicket = true
                        }
                    }
                    Button("Lokalen Verlauf löschen", systemImage: "trash", role: .destructive) {
                        chatModel.messages.removeAll(keepingCapacity: false)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Chatoptionen")
            }
        }
        .task { await chatModel.start(using: appModel) }
        .onDisappear { chatModel.stop() }
        .sheet(isPresented: $isPresentingConfiguration) {
            ChatConfigurationView(chatModel: chatModel)
        }
        .sheet(isPresented: $isPresentingSecurity) {
            ChatSecurityView(chatModel: chatModel)
        }
        .sheet(isPresented: $isPresentingSupportTicket) {
            SupportTicketComposerView(chatModel: chatModel)
        }
        .fullScreenCover(isPresented: $isPresentingCamera) {
            InMemoryCameraPicker { image in
                isPresentingCamera = false
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    chatModel.lastError = ChatError.unsupportedMedia.localizedDescription
                    return
                }
                Task { await chatModel.sendImage(data) }
            } onCancel: {
                isPresentingCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: imageSelection) { _, item in
            guard let item else { return }
            Task {
                defer { imageSelection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ChatError.unsupportedMedia
                    }
                    await chatModel.sendImage(data)
                } catch { chatModel.lastError = error.localizedDescription }
            }
        }
        .onChange(of: videoSelection) { _, item in
            guard let item else { return }
            Task {
                defer { videoSelection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw ChatError.unsupportedMedia
                    }
                    let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })?.preferredMIMEType ?? "video/mp4"
                    await chatModel.sendVideo(data, contentType: contentType)
                } catch { chatModel.lastError = error.localizedDescription }
            }
        }
        .alert("Chatfehler", isPresented: errorBinding) {
            Button("OK") { chatModel.lastError = nil }
        } message: {
            Text(chatModel.lastError ?? "Unbekannter Fehler")
        }
        .onChange(of: recorder.duration) { _, duration in
            guard duration >= 230, let data = recorder.stop() else { return }
            voicePressIsActive = false
            Task { await chatModel.sendVoice(data) }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch chatModel.state {
        case .notConfigured:
            Button("Verschlüsselten Chat einrichten", systemImage: "lock.shield") {
                isPresentingConfiguration = true
            }
            .buttonStyle(.borderedProminent)
            .padding(12)
        case .connecting:
            Label("Sichere Verbindung wird aufgebaut …", systemImage: "lock.rotation")
                .font(.footnote)
                .padding(10)
        case .online:
            VStack(spacing: 4) {
                Label("Ende-zu-Ende verschlüsselt · flüchtiger Relay", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if chatModel.accessRole == .owner {
                    Label("Owner serverseitig bestätigt", systemImage: "checkmark.shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else if chatModel.accessRole == .member {
                    Label("Admin-Anfragen werden separat als Ticket gespeichert", systemImage: "ticket.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if chatModel.contacts.isEmpty {
                    Label("Noch keine Chat-Kontakte registriert", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(chatModel.contacts) { contact in
                            Button {
                                chatModel.selectContact(contact)
                            } label: {
                                if chatModel.recipientUserID == contact.userID {
                                    Label(contact.displayName, systemImage: "checkmark")
                                } else {
                                    Text(contact.displayName)
                                }
                            }
                        }
                    } label: {
                        Label(
                            chatModel.contacts.first(where: { $0.userID == chatModel.recipientUserID })?.displayName
                                ?? "Chat-Kontakt auswählen",
                            systemImage: "person.2.fill"
                        )
                        .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityLabel("Ende-zu-Ende verschlüsselt. Nachrichten werden nicht gespeichert.")
        case let .offline(message):
            HStack {
                Label("Offline", systemImage: "wifi.slash")
                Spacer()
                Button("Erneut verbinden") { Task { await chatModel.start(using: appModel) } }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(10)
            .accessibilityHint(message)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chatModel.messages.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Nachrichten",
                            systemImage: "message.badge.shield.fill",
                            description: Text("Nachrichten erscheinen nur in dieser Sitzung und werden nicht als Verlauf gespeichert.")
                        )
                        .padding(.top, 60)
                    }
                    ForEach(chatModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatModel.messages.count) { _, _ in
                guard let id = chatModel.messages.last?.id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Kamera", systemImage: "camera.fill") {
                        isPresentingCamera = true
                    }
                }
                PhotosPicker(selection: $imageSelection, matching: .images) {
                    Label("Foto", systemImage: "photo")
                }
                PhotosPicker(selection: $videoSelection, matching: .videos) {
                    Label("Video", systemImage: "video")
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!chatModel.canSend)

            TextField("Nachricht", text: Bindable(chatModel).draft, axis: .vertical)
                .accessibilityIdentifier("chat-composer-field")
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .disabled(!chatModel.canSend)
                .onSubmit { Task { await chatModel.sendDraft() } }

            if chatModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceButton
            } else {
                Button {
                    Task { await chatModel.sendDraft() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.bold())
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(chatModel.isSending || !chatModel.canSend)
                .accessibilityLabel("Nachricht senden")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var voiceButton: some View {
        Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
            .font(.body.bold())
            .foregroundStyle(recorder.isRecording ? .red : .primary)
            .frame(width: 40, height: 40)
            .background(recorder.isRecording ? Color.red.opacity(0.14) : Color.clear, in: Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !voicePressIsActive else { return }
                        voicePressIsActive = true
                        Task {
                            do {
                                try await recorder.start()
                                if !voicePressIsActive { _ = recorder.stop() }
                            }
                            catch { chatModel.lastError = error.localizedDescription }
                        }
                    }
                    .onEnded { _ in
                        voicePressIsActive = false
                        guard let data = recorder.stop() else { return }
                        Task { await chatModel.sendVoice(data) }
                    }
            )
            .accessibilityLabel(recorder.isRecording ? "Aufnahme läuft" : "Für Sprachnachricht gedrückt halten")
            .allowsHitTesting(chatModel.canSend)
            .opacity(chatModel.canSend ? 1 : 0.45)
            .overlay(alignment: .topTrailing) {
                if recorder.isRecording {
                    Text(recorder.duration, format: .number.precision(.fractionLength(1)))
                        .font(.caption2.monospacedDigit())
                        .offset(y: -18)
                }
            }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { chatModel.lastError != nil },
            set: { if !$0 { chatModel.lastError = nil } }
        )
    }
}

private struct SupportTicketComposerView: View {
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 180)
                } header: {
                    Text("Anfrage an den Owner")
                } footer: {
                    Text("Tickets sind absichtlich persistent und getrennt vom flüchtigen E2EE-Chat. Keine Passwörter, Tokens oder privaten Schlüssel eintragen.")
                }

                if let ticketID = chatModel.lastCreatedTicketID {
                    Section("Letztes Ticket") {
                        Text(ticketID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Owner-Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ticket senden") {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            if await chatModel.createSupportTicket(message: message) != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        isSubmitting
                            || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || message.count > 4000
                    )
                }
            }
        }
    }
}

private struct InMemoryCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier]
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.direction == .outgoing { Spacer(minLength: 46) }
            VStack(alignment: .leading, spacing: 6) {
                content
                HStack(spacing: 4) {
                    Text(message.createdAt, format: .dateTime.hour().minute())
                    if message.direction == .outgoing {
                        Image(systemName: deliverySymbol)
                            .foregroundStyle(message.delivery == .failed ? .red : .secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(message.kind == .image || message.kind == .video ? 6 : 11)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if message.direction == .incoming { Spacer(minLength: 46) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            Text(message.text ?? "")
                .textSelection(.enabled)
        case .image:
            if let image = UIImage(data: message.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Label("Bild nicht lesbar", systemImage: "exclamationmark.triangle")
            }
        case .voice:
            HStack(spacing: 12) {
                InMemoryAudioButton(data: message.data)
                Image(systemName: "waveform")
                    .font(.title2)
                Text("Sprachnachricht")
                    .font(.subheadline.weight(.medium))
            }
            .frame(minWidth: 210, alignment: .leading)
        case .video:
            InMemoryVideoView(
                id: message.id,
                data: message.data,
                contentType: message.contentType
            )
            .frame(maxWidth: 310)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var bubbleColor: Color {
        message.direction == .outgoing ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var deliverySymbol: String {
        switch message.delivery {
        case .sending: "clock"
        case .queued: "checkmark"
        case .received: "checkmark"
        case .failed: "exclamationmark.circle.fill"
        }
    }
}

private struct ChatConfigurationView: View {
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var token = ""
    @State private var userID = ""
    @State private var recipient = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Eigene Identität") {
                    TextField("Benutzerkennung", text: $userID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Kontaktkennung", text: $recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("https://chat.home.arpa:8787", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Chat-Token", text: $token)
                } header: {
                    Text("Privater Relay")
                } footer: {
                    Text("Der Relay speichert nur öffentliche Geräteschlüssel. Nachrichten und Medien liegen höchstens 120 Sekunden verschlüsselt im RAM und werden bei Abruf gelöscht.")
                }
                if let errorMessage {
                    Section { IOSNextErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle("Chat einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        do {
                            try chatModel.configure(endpoint: endpoint, token: token, userID: userID, recipientUserID: recipient)
                            dismiss()
                            Task { await chatModel.start() }
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }
}

private struct ChatSecurityView: View {
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingNewKeys = false

    var body: some View {
        NavigationStack {
            List {
                Section("Deine Sicherheitsnummer") {
                    Text(chatModel.ownSafetyNumber.isEmpty ? "Noch nicht verfügbar" : chatModel.ownSafetyNumber)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    if chatModel.recipientSafetyNumbers.isEmpty {
                        Text("Noch kein Schlüssel gefunden")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chatModel.recipientSafetyNumbers, id: \.self) { number in
                            Text(number)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Kontaktgeräte")
                } footer: {
                    Text("Vergleicht diese Nummern über einen zweiten vertrauenswürdigen Kanal. Ändert sich ein bereits bekannter Schlüssel, blockiert die App den Versand.")
                }
                Section("Datenschutz") {
                    Label("ChaCha20-Poly1305 pro Nachrichtenblock", systemImage: "lock.fill")
                    Label("X25519-Schlüsselaustausch", systemImage: "key.fill")
                    Label("Ed25519-Signaturen", systemImage: "checkmark.seal.fill")
                    Label("Kein persistenter Chatverlauf", systemImage: "internaldrive.fill.badge.xmark")
                }
                Section {
                    Button("Geänderte Kontaktschlüssel bestätigen", systemImage: "person.badge.key.fill") {
                        isConfirmingNewKeys = true
                    }
                } footer: {
                    Text("Nur verwenden, nachdem ihr die neuen Sicherheitsnummern über einen zweiten Kanal verglichen habt. Die Änderung erfordert Face ID.")
                }
            }
            .navigationTitle("Sicherheit")
            .toolbar { Button("Fertig") { dismiss() } }
            .confirmationDialog(
                "Neue Sicherheitsidentität akzeptieren?",
                isPresented: $isConfirmingNewKeys,
                titleVisibility: .visible
            ) {
                Button("Mit Face ID bestätigen") {
                    Task { await chatModel.approveCurrentRecipientKeys() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Ein unbemerkter Schlüsselwechsel kann auf ein fremdes Gerät oder einen Angriff hinweisen.")
            }
        }
    }
}
