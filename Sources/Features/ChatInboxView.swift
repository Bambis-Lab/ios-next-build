import SwiftUI

/// Inbox owns navigation only. Encryption, verified HA identities, draft
/// isolation and delivery remain solely in ChatModel / the authenticated relay.
struct ChatInboxView: View {
    let appModel: AppModel
    let chatModel: ChatModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var destination: ChatInboxDestination?
    @State private var showingMemberTickets = false
    @State private var showingNewTicket = false
    @State private var showingOwnerTickets = false

    private enum ChatInboxDestination: Hashable, Identifiable {
        case family
        case person(String)
        case setup
        var id: String {
            switch self {
            case .family: "family"
            case .person(let userID): "person:\(userID)"
            case .setup: "setup"
            }
        }
    }

    private var filteredContacts: [ChatContact] {
        guard !searchText.isEmpty else { return chatModel.contacts }
        return chatModel.contacts.filter {
            $0.displayName.localizedStandardContains(searchText)
        }
    }

    private var showOwnerTickets: Bool {
        chatModel.accessRole == .owner &&
        appModel.registeredFamilyProfile == .nico
    }

    private var showMemberTickets: Bool {
        chatModel.accessRole == .member &&
        appModel.registeredFamilyProfile != .nico
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                if let group = chatModel.familyGroup {
                    Section("Familie") {
                        Button {
                            chatModel.selectFamilyGroup()
                            destination = .family
                        } label: {
                            inboxRow(
                                symbol: "person.3.fill",
                                title: group.title,
                                subtitle: familyPreview,
                                accessory: group.isReady ? nil : "Einrichtung ausstehend"
                            )
                        }
                        .accessibilityIdentifier("chat-inbox-family")
                        .buttonStyle(.plain)
                    }
                } else if appModel.familyBrokerConfigured &&
                            appModel.registeredFamilyProfile != nil {
                    Section("Familie") {
                        Label("Familiengruppe noch nicht verfügbar", systemImage: "person.3.sequence")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chat-inbox-family-pending")
                    }
                }

                if showOwnerTickets || showMemberTickets {
                    Section("Admin") {
                        if showOwnerTickets {
                            Button {
                                showingOwnerTickets = true
                            } label: {
                                inboxRow(
                                    symbol: "shield.checkered",
                                    title: "Admin-Anfragen",
                                    subtitle: "Familientickets · Owner-Freigabe erforderlich",
                                    accessory: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat-inbox-owner-tickets")
                        } else {
                            Button {
                                showingMemberTickets = true
                            } label: {
                                inboxRow(
                                    symbol: "ticket.fill",
                                    title: "Meine Admin-Tickets",
                                    subtitle: "Deine Anfragen und Nicos Antworten",
                                    accessory: nil
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat-inbox-member-tickets")
                            Button {
                                showingNewTicket = true
                            } label: {
                                Label("Admin kontaktieren", systemImage: "square.and.pencil")
                            }
                            .accessibilityIdentifier("chat-inbox-create-ticket")
                        }
                    }
                }
            }

            Section("Private Unterhaltungen") {
                if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        chatModel.contacts.isEmpty ? "Noch keine Kontakte" : "Keine Treffer",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(chatModel.contacts.isEmpty
                            ? "Erst nach der sicheren Geräteregistrierung erscheinen Kontakte."
                            : "Versuche einen anderen Namen.")
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(filteredContacts) { contact in
                    Button {
                        chatModel.selectContact(contact)
                        destination = .person(contact.userID)
                    } label: {
                        inboxRow(
                            symbol: "person.crop.circle.fill",
                            title: contact.displayName,
                            subtitle: ChatInboxPolicy.previewText(
                                chatModel.messages,
                                peerUserID: contact.userID
                            ),
                            accessory: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-inbox-person-\(contact.userID)")
                }
            }

            Section {
                Label("Private Chats sind Ende-zu-Ende verschlüsselt. Der Verlauf bleibt derzeit nur während dieser Sitzung erhalten.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "Chats durchsuchen")
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Chat einrichten", systemImage: "gearshape") {
                    destination = .setup
                }
                .accessibilityIdentifier("chat-inbox-settings")
            }
        }
        .navigationDestination(item: $destination) { _ in
            ChatView(appModel: appModel, chatModel: chatModel)
        }
        .sheet(isPresented: $showingMemberTickets) {
            MemberTicketInboxView(chatModel: chatModel)
        }
        .sheet(isPresented: $showingNewTicket) {
            NavigationStack {
                MemberTicketCreationView(chatModel: chatModel)
            }
        }
        .sheet(isPresented: $showingOwnerTickets) {
            AdminAreaView(appModel: appModel, ticketsOnly: true)
        }
        .privacySensitive()
        .overlay {
            if scenePhase != .active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay {
                        Label("Chats geschützt", systemImage: "lock.fill")
                            .font(.headline)
                    }
            }
        }
        .task {
            await IOSNextRuntime.shared.lifecycleCoordinator.chatViewAppeared(appModel: appModel)
        }
        .onAppear {
            if showMemberTickets { Task { await chatModel.loadMemberTickets() } }
        }
        .onDisappear {
            // Conversation detail owns its own lifecycle while pushed.
            if destination == nil {
                IOSNextRuntime.shared.lifecycleCoordinator.chatViewDisappeared()
            }
        }
    }

    private var familyPreview: String {
        let count = chatModel.familyGroup?.members.count ?? 0
        return ChatInboxPolicy.previewText(chatModel.messages, peerUserID: nil)
            == "Noch keine Nachrichten"
            ? "\(count) Mitglieder · verschlüsselter Gruppenchat"
            : ChatInboxPolicy.previewText(chatModel.messages, peerUserID: nil)
    }

    private func inboxRow(symbol: String, title: String, subtitle: String, accessory: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(.tint)
                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let accessory {
                    Text(accessory)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Does not infer message delivery or persistence from a local snapshot.
enum ChatInboxPolicy {
    static func previewText(_ messages: [ChatMessage], peerUserID: String?) -> String {
        guard let last = messages.last(where: { message in
            if let peerUserID {
                return message.conversationID == nil && message.peerUserID == peerUserID
            }
            return message.conversationID == "family"
        }) else {
            return "Noch keine Nachrichten"
        }
        switch last.kind {
        case .text: return last.text ?? "Nachricht"
        case .image: return "Foto"
        case .video: return "Video"
        case .voice: return "Sprachnachricht"
        }
    }
}

/// The new inbox shows a dedicated member ticket entry without creating
/// an owner-authority shortcut.
private struct MemberTicketCreationView: View {
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sending = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("chat-inbox-ticket-message")
            } header: {
                Text("Nachricht an Nico")
            } footer: {
                Text("Admin-Tickets werden serverseitig gespeichert und sind keine E2EE-Privatnachrichten.")
            }
        }
        .navigationTitle("Admin kontaktieren")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Senden") {
                    let body = message
                    Task {
                        sending = true
                        let ticketID = await chatModel.createSupportTicket(message: body)
                        sending = false
                        if ticketID != nil { dismiss() }
                    }
                }
                .disabled(
                    sending ||
                    message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    message.count > 4000
                )
                .accessibilityIdentifier("chat-inbox-ticket-send")
            }
        }
    }
}
