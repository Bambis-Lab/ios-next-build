import SwiftUI

// Member ticket history is persisted by the trusted backend; unlike private
// E2EE chats, these records are explicitly accessible to the authorized Owner.
struct MemberTicketInboxView: View {
    let chatModel: ChatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if chatModel.memberTickets.isEmpty {
                    ContentUnavailableView(
                        "Keine Admin-Anfragen",
                        systemImage: "ticket",
                        description: Text("Erstellte Tickets und Antworten erscheinen hier.")
                    )
                }
                ForEach(chatModel.memberTickets) { ticket in
                    NavigationLink {
                        MemberTicketConversationView(chatModel: chatModel, ticketID: ticket.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ticket.lastMessage ?? "Anfrage")
                                .lineLimit(2)
                            HStack {
                                Text(ticket.status == "open" ? "Neu" :
                                     ticket.status == "in_progress" ? "In Arbeit" :
                                     ticket.status == "resolved" ? "Erledigt" : ticket.status)
                                Spacer()
                                Text(ticket.updatedAt)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Meine Admin-Tickets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task { await chatModel.loadMemberTickets() }
            .refreshable { await chatModel.loadMemberTickets() }
        }
    }
}

private struct MemberTicketConversationView: View {
    let chatModel: ChatModel
    let ticketID: String
    @State private var draft = ""
    @State private var isSending = false

    private var ticket: SupportTicket? { chatModel.memberTicketDetails[ticketID] }

    var body: some View {
        VStack(spacing: 0) {
            if let ticket {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(ticket.messages ?? []) { item in
                            HStack {
                                if item.authorRole == .member { Spacer(minLength: 36) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.authorRole == .owner ? "Nico · Owner" : "Du")
                                        .font(.caption.weight(.semibold))
                                    Text(item.body)
                                        .textSelection(.enabled)
                                    Text(item.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    item.authorRole == .member ? Color.accentColor.opacity(0.15) :
                                        Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                                if item.authorRole == .owner { Spacer(minLength: 36) }
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                ProgressView("Ticket laden …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                TextField("Antwort an Nico", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                Button {
                    let text = draft
                    Task {
                        isSending = true
                        let sent = await chatModel.replyMemberTicket(ticketID, message: text)
                        if sent && draft == text { draft = "" }
                        isSending = false
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 4000)
                .accessibilityLabel("Ticketantwort senden")
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle("Admin-Anfrage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await chatModel.loadMemberTicket(ticketID) }
        .refreshable { await chatModel.loadMemberTicket(ticketID) }
    }
}
