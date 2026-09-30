import SwiftUI

enum AnimationAcceptanceStage: Int, CaseIterable, Identifiable {
    case appStart, navigation, lightToggle, conditional, media, slider, chat, owner

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .appStart: "App-Start"
        case .navigation: "Navigation"
        case .lightToggle: "Light Toggle"
        case .conditional: "Conditional Card"
        case .media: "Media Play/Pause"
        case .slider: "Slider"
        case .chat: "Chat"
        case .owner: "Owner Area"
        }
    }

    var symbol: String {
        switch self {
        case .appStart: "sparkles"
        case .navigation: "rectangle.3.group.fill"
        case .lightToggle: "lightbulb.fill"
        case .conditional: "switch.2"
        case .media: "playpause.fill"
        case .slider: "slider.horizontal.3"
        case .chat: "message.fill"
        case .owner: "lock.shield.fill"
        }
    }
}

struct AnimationAcceptanceView: View {
    private let requestedStage: AnimationAcceptanceStage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: AnimationAcceptanceStage = .appStart
    @State private var navSelection = 0
    @State private var lightOn = false
    @State private var conditionalVisible = false
    @State private var mediaPlaying = false
    @State private var sliderValue = 0.15
    @State private var chatText = ""
    @State private var ownerUnlocked = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        requestedStage = Self.stage(from: arguments)
    }

    var body: some View {
        ZStack {
            IOSNextBackground()
            VStack(spacing: 16) {
                header
                stageContent
                    .id(stage)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.985))
                    ))
                Spacer(minLength: 0)
                timeline
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .animation(reduceMotion ? .linear(duration: 0.15) : IOSNextMotion.emphasis, value: stage)
        .task {
            if let requestedStage {
                configureSettledState(for: requestedStage)
            } else {
                await runSequence()
            }
        }
        .accessibilityIdentifier("animation-acceptance-root")
        .background {
            VisualAcceptanceReadyProbe(
                markerBaseName: "iosnext-animation-stage-ready-\(stage.rawValue)",
                accessibilityIdentifier: "visual-ready-animation-stage-\(stage.rawValue)",
                payload: "stage=\(stage.rawValue)"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: stage.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .iosNextFunctionalGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Live Interaction Test").font(.headline)
                Text(stage.title)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("animation-stage-\(stage.rawValue)")
            }
            Spacer()
            Text("\(stage.rawValue + 1)/\(AnimationAcceptanceStage.allCases.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .iosNextSurface()
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .appStart:
            VStack(spacing: 14) {
                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: stage)
                Text("iOS Next").font(.largeTitle.bold())
                Text("Nativ. Schnell. Privat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .iosNextSurface()
        case .navigation:
            VStack(alignment: .leading, spacing: 16) {
                Text("Navigation").font(.title2.bold())
                HStack(spacing: 6) {
                    ForEach(0..<4) { index in
                        Button { navSelection = index } label: {
                            Image(systemName: ["house.fill", "square.grid.2x2.fill", "message.fill", "ellipsis.circle.fill"][index])
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(navSelection == index ? Color.accentColor : Color.secondary)
                                .background(
                                    navSelection == index ? Color.accentColor.opacity(0.13) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .iosNextSurface()
        case .lightToggle:
            VStack(spacing: 18) {
                Image(systemName: lightOn ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 54))
                    .foregroundStyle(lightOn ? .yellow : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(lightOn ? "Licht an" : "Licht aus").font(.title3.bold())
                Button("Umschalten") { lightOn.toggle() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .iosNextSurface()
        case .conditional:
            VStack(spacing: 14) {
                Toggle("Bedingung erfüllt", isOn: $conditionalVisible)
                if conditionalVisible {
                    Label("Conditional Card sichtbar", systemImage: "checkmark.circle.fill")
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .padding(18)
            .iosNextSurface()
        case .media:
            VStack(spacing: 18) {
                Image(systemName: mediaPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 58))
                    .contentTransition(.symbolEffect(.replace))
                Text(mediaPlaying ? "Wiedergabe läuft" : "Pausiert").font(.title3.bold())
                Button(mediaPlaying ? "Pause" : "Play") { mediaPlaying.toggle() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .iosNextSurface()
        case .slider:
            VStack(alignment: .leading, spacing: 18) {
                Text("Helligkeit \(Int(sliderValue * 100))%")
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                Slider(value: $sliderValue)
                    .accessibilityIdentifier("animation-slider")
            }
            .padding(22)
            .iosNextSurface()
        case .chat:
            VStack(spacing: 14) {
                HStack {
                    Text(chatText.isEmpty ? "Nachricht wird geschrieben …" : chatText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer()
                }
                TextField("Nachricht", text: $chatText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(18)
            .iosNextSurface()
        case .owner:
            VStack(spacing: 16) {
                Image(systemName: ownerUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(ownerUnlocked ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(ownerUnlocked ? "Owner Area entsperrt" : "Owner Area gesperrt")
                    .font(.title3.bold())
                Text("Testmodus · keine echten Admin-Aktionen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .iosNextSurface()
        }
    }

    private var timeline: some View {
        HStack(spacing: 5) {
            ForEach(AnimationAcceptanceStage.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= stage.rawValue ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(height: 5)
            }
        }
        .accessibilityIdentifier("animation-timeline")
    }

    static func stage(from arguments: [String]) -> AnimationAcceptanceStage? {
        guard let argument = arguments.first(where: { $0.hasPrefix("--animation-stage=") }),
              let rawValue = Int(argument.split(separator: "=").last ?? "")
        else { return nil }
        return AnimationAcceptanceStage(rawValue: rawValue)
    }

    @MainActor
    private func configureSettledState(for requestedStage: AnimationAcceptanceStage) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stage = requestedStage
            navSelection = requestedStage == .navigation ? 3 : 0
            lightOn = requestedStage == .lightToggle
            conditionalVisible = requestedStage == .conditional
            mediaPlaying = requestedStage == .media
            sliderValue = requestedStage == .slider ? 0.88 : 0.15
            chatText = requestedStage == .chat ? "Hallo aus dem Live-Test" : ""
            ownerUnlocked = requestedStage == .owner
        }
    }

    @MainActor
    private func runSequence() async {
        await sleep(900)
        stage = .navigation
        for index in 1...3 { await sleep(420); navSelection = index }
        await sleep(650); stage = .lightToggle
        await sleep(480); lightOn = true
        await sleep(650); stage = .conditional
        await sleep(480); conditionalVisible = true
        await sleep(650); stage = .media
        await sleep(480); mediaPlaying = true
        await sleep(420); mediaPlaying = false
        await sleep(650); stage = .slider
        for value in stride(from: 0.15, through: 0.88, by: 0.073) {
            await sleep(90); sliderValue = value
        }
        await sleep(600); stage = .chat
        for character in "Hallo aus dem Live-Test" {
            await sleep(55); chatText.append(character)
        }
        await sleep(650); stage = .owner
        await sleep(550); ownerUnlocked = true
    }

    private func sleep(_ milliseconds: UInt64) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
