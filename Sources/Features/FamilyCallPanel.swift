import SwiftUI

/// Foreground signalling preview only. No audio session or microphone access.
struct FamilyCallPanel: View {
    let chatModel: ChatModel
    var allowInvite = false

    var body: some View {
        if chatModel.canSignalCalls {
            VStack(alignment: .leading, spacing: 8) {
                Label("Anrufsignalisierung · kein Audio", systemImage: "phone")
                    .font(.caption).foregroundStyle(.secondary)
                if allowInvite && !chatModel.showingFamilyGroup {
                    Button("Anrufanfrage senden", systemImage: "phone.arrow.up.right") {
                        Task { await chatModel.inviteSelectedContact() }
                    }
                    .disabled(chatModel.callBusy || chatModel.recipientUserID.isEmpty)
                }
                Button("Anrufstatus aktualisieren", systemImage: "arrow.clockwise") {
                    Task { await chatModel.refreshCalls() }
                }
                .disabled(chatModel.callBusy)
                if let error = chatModel.callError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(chatModel.callListing?.calls ?? []) { call in
                    VStack(alignment: .leading) {
                        let own = chatModel.isOwnCaller(call)
                        let peer = (own ? call.callee : call.caller).first ?? ""
                        Text(chatModel.contacts.first(where: { $0.userID == peer })?.displayName ?? "Familienkontakt")
                        switch call.state {
                        case .ringing:
                            Text(own ? "Anfrage gesendet" : "Eingehende Anrufanfrage")
                            if own {
                                action("Abbrechen", .cancel, call)
                            } else {
                                HStack {
                                    action("Annehmen", .accept, call)
                                    action("Ablehnen", .decline, call)
                                }
                            }
                        case .accepted:
                            Text("Anfrage angenommen – Audio nicht verfügbar")
                            action("Beenden", .hangup, call)
                        case .declined: Text("Abgelehnt")
                        case .cancelled: Text("Abgebrochen")
                        case .ended: Text("Beendet")
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding(8)
            .task { await chatModel.refreshCalls() }
            .privacySensitive()
            .accessibilityIdentifier("family-call-signalling")
        }
    }

    private func action(_ title: String, _ action: FamilyCallSignal.Action, _ call: FamilyCallState) -> some View {
        Button(title) {
            Task {
                if let signal = try? FamilyCallSignal.transition(action, callID: call.id) {
                    await chatModel.signalCall(signal)
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(chatModel.callBusy)
    }
}
