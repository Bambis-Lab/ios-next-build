import SwiftUI

struct JarvisView: View {
    let engine: JarvisEngine

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Status", systemImage: engine.state.isListening ? "waveform" : "sparkles")
                    Spacer()
                    Text(engine.state.title)
                        .foregroundStyle(statusTint)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Wake Word", value: engine.wakeWord)
                LabeledContent("Erkennung", value: engine.onDeviceRecognitionAvailable ? "On-Device" : "Noch nicht geprüft")

                if engine.state.isListening {
                    Button("Wake Listening stoppen", systemImage: "stop.circle.fill", role: .destructive) {
                        engine.stopWakeListening()
                    }
                } else {
                    Button("Wake Listening starten", systemImage: "waveform.badge.mic") {
                        Task { await engine.startWakeListening() }
                    }
                    .disabled(isPermissionCheckRunning)
                }
            } header: {
                Text("Jarvis")
            } footer: {
                Text("Jarvis nutzt nur lokale iOS-Spracherkennung, wenn On-Device-Erkennung verfügbar ist. Es gibt keinen automatischen Server-Fallback für das Wake Word.")
            }

            Section {
                ForEach(JarvisSensitivity.allCases) { sensitivity in
                    Button {
                        engine.sensitivity = sensitivity
                    } label: {
                        HStack {
                            Text(sensitivity.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if engine.sensitivity == sensitivity {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Empfindlichkeit")
            } footer: {
                Text("Hoch reagiert früher, Normal ist der Standard, Niedrig verlangt eine deutlichere Erkennung von „Jarvis“.")
            }

            Section("Letzte Aktivität") {
                if let lastWakeAt = engine.lastWakeAt {
                    LabeledContent("Letztes Wake", value: lastWakeAt.formatted(date: .omitted, time: .standard))
                } else {
                    LabeledContent("Letztes Wake", value: "—")
                }

                if let transcript = engine.lastTranscript, !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transkript")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transcript)
                    }
                }

                if let intent = engine.latestIntent {
                    LabeledContent("Intent", value: intent.domain.rawValue)
                    LabeledContent("Aktion", value: intent.action)
                }
            }

            Section("Diagnose") {
                LabeledContent("Wake-Evidenz", value: "\(engine.wakeEvidenceCount)")
                LabeledContent("Audio Drops", value: "\(engine.audioDropCount)")
                LabeledContent("Lokale Engine", value: engine.onDeviceRecognitionAvailable ? "Bereit" : "Unbestätigt")
                if engine.latestIntent != nil || engine.lastTranscript != nil {
                    Button("Letzte Diagnose leeren", systemImage: "trash") {
                        engine.clearLastIntent()
                    }
                }
            }

            Section("Sicherheit") {
                Label("Wake Word ersetzt keine Owner-Authentifizierung.", systemImage: "faceid")
                Label("Kritische Aktionen benötigen weiterhin die bestehende Sicherheitsfreigabe.", systemImage: "lock.shield.fill")
                Label("Dieser Foundation-Stand führt erkannte Intents noch nicht automatisch aus.", systemImage: "checkmark.shield.fill")
            }
        }
        .listStyle(.insetGrouped)
        .iosNextManagementBackground()
        .navigationTitle("Jarvis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isPermissionCheckRunning: Bool {
        if case .requestingPermission = engine.state { return true }
        return false
    }

    private var statusTint: Color {
        switch engine.state {
        case .error, .unavailable: .orange
        case .wakeDetected, .listening, .transcribing, .listeningForWakeWord: .green
        case .thinking, .speaking: .blue
        case .requestingPermission: .secondary
        case .idle: .green
        }
    }
}

struct JarvisListeningPill: View {
    let engine: JarvisEngine

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            Text(engine.state.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .shadow(radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jarvis")
        .accessibilityValue(engine.state.title)
    }

    private var symbol: String {
        switch engine.state {
        case .wakeDetected: "sparkles"
        case .listening, .listeningForWakeWord: "waveform"
        case .transcribing: "text.bubble.fill"
        default: "waveform.badge.mic"
        }
    }
}
