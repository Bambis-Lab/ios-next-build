import SwiftUI

/// Foreground signalling and explicitly authorized experimental audio.
struct FamilyCallPanel: View {
    let chatModel: ChatModel
    var allowInvite = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var safetyNumber = ""
    @State private var selectedAudioCall: String?

    var body: some View {
        if chatModel.canSignalCalls && scenePhase == .active {
            VStack(alignment: .leading, spacing: 8) {
                Label(chatModel.canStartAudio ? "Familienanrufe · Audio experimentell" : "Anrufsignalisierung · kein Audio", systemImage: "phone")
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
                if let error = chatModel.audioError {
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
                            Text("Anfrage angenommen")
                            if chatModel.canStartAudio {
                                audioControls(call)
                            } else {
                                Text("Audio nicht verfügbar").foregroundStyle(.secondary)
                            }
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
            .task { await chatModel.pollCallsWhileVisible() }
            .onDisappear { chatModel.stopAudio(); safetyNumber = ""; selectedAudioCall = nil }
            .privacySensitive()
            .accessibilityIdentifier("family-call-signalling")
        }
    }

    @ViewBuilder
    private func audioControls(_ call: FamilyCallState) -> some View {
        if chatModel.audioCallID == call.id {
            if let session = chatModel.audioSession {
                Text(audioStatus(session.state)).font(.caption)
                if session.state == .active {
                    Button(session.muted ? "Mikrofon einschalten" : "Mikrofon stummschalten",
                           systemImage: session.muted ? "mic.slash" : "mic") {
                        session.setMuted(!session.muted)
                    }
                }
            } else {
                ProgressView("Kontakt wird überprüft")
            }
            Button("Audio stoppen", systemImage: "phone.down") { chatModel.stopAudio() }
        } else if selectedAudioCall == call.id {
            Text("Vergleiche die Sicherheitsnummer des Gegenübers persönlich oder über einen bereits vertrauenswürdigen Kanal. Gib genau diese Nummer ein.")
                .font(.caption)
            TextField("Bestätigte Sicherheitsnummer", text: $safetyNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("family-call-confirmed-safety-number")
            HStack {
                Button("Audio sicher starten") {
                    let confirmed = safetyNumber
                    safetyNumber = ""
                    selectedAudioCall = nil
                    Task { await chatModel.startAudio(callID: call.id, confirmedSafetyNumber: confirmed) }
                }
                .disabled(safetyNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          chatModel.audioCallID != nil)
                Button("Abbrechen") { safetyNumber = ""; selectedAudioCall = nil }
            }
        } else {
            Button("Kontakt verifizieren und Audio starten", systemImage: "lock.shield") {
                safetyNumber = ""
                selectedAudioCall = call.id
            }
            .disabled(chatModel.audioCallID != nil)
        }
    }

    private func audioStatus(_ state: FamilyAudioSessionState) -> String {
        switch state {
        case .idle, .connecting: "Audioverbindung wird aufgebaut"
        case .verifying: "Schlüssel werden überprüft"
        case .active: "Verschlüsseltes Audiogespräch"
        case .reconnecting: "Sichere Wiederverbindung wird aufgebaut"
        case .ended: "Audio beendet"
        case .failed: "Audioverbindung fehlgeschlagen"
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
