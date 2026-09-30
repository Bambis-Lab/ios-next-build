import Foundation
import SwiftUI

struct MotionAcceptanceView: View {
    private let sequence: IOSNextMotionSequence
    @State private var frame: Int

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let sequence = Self.sequence(from: arguments)
        self.sequence = sequence
        _frame = State(initialValue: Self.frame(from: arguments, sequence: sequence))
    }

    var body: some View {
        ZStack {
            switch sequence {
            case .startup:
                startupFrame
            case .controlCenterUnlock:
                unlockFrame
            case .controlCenterLock:
                lockFrame
            }

            acceptanceControls
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("motion-acceptance-root")
        .accessibilityValue(frameState)
        .background {
            VisualAcceptanceReadyProbe(
                markerBaseName: "iosnext-motion-ready-\(sequence.rawValue)-\(frame)",
                accessibilityIdentifier: "visual-ready-motion-\(sequence.rawValue)-\(frame)",
                payload: frameState
            )
        }
    }

    private var startupFrame: some View {
        let sample = IOSNextMasterMotion.startup(frame: frame)
        return ZStack {
            IOSNextBackground()
            MotionReferenceHome()
                .opacity(sample.contentOpacity)
                .offset(y: CGFloat(sample.contentYOffset))
                .scaleEffect(CGFloat(sample.contentScale))
            IOSNextStartupRevealLayer(sample: sample)
        }
    }

    private var unlockFrame: some View {
        let sample = IOSNextMasterMotion.controlCenterUnlock(frame: frame)
        return ZStack {
            OwnerBackground()
            MotionReferenceControlCenter()
                .environment(\.controlCenterMotionFrame, frame)
            IOSNextControlCenterUnlockLayer(sample: sample)
        }
    }

    private var lockFrame: some View {
        let sample = IOSNextMasterMotion.controlCenterLock(frame: frame)
        return ZStack {
            OwnerBackground()
            MotionReferenceControlCenter()
                .opacity(sample.contentOpacity)
                .scaleEffect(CGFloat(sample.contentScale))
                .blur(radius: CGFloat(sample.contentBlur))
            IOSNextControlCenterLockLayer(sample: sample)
        }
    }

    private var acceptanceControls: some View {
        VStack {
            HStack {
                Button {
                    frame = max(0, frame - 1)
                } label: {
                    Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous motion frame")
                .accessibilityIdentifier("motion-previous-frame")

                Spacer()

                Button {
                    frame = min(sequence.lastFrame, frame + 1)
                } label: {
                    Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next motion frame")
                .accessibilityIdentifier("motion-next-frame")
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(true)
    }

    private var frameState: String {
        String(
            format: "sequence=%@;frame=%03d;time_ms=%.3f;fps=120",
            sequence.rawValue,
            frame,
            sequence.milliseconds(at: frame)
        )
    }

    private static func sequence(from arguments: [String]) -> IOSNextMotionSequence {
        guard let argument = arguments.first(where: { $0.hasPrefix("--motion-acceptance-sequence=") }),
              let rawValue = argument.split(separator: "=").last.map(String.init),
              let sequence = IOSNextMotionSequence(rawValue: rawValue)
        else { return .startup }
        return sequence
    }

    private static func frame(from arguments: [String], sequence: IOSNextMotionSequence) -> Int {
        guard let argument = arguments.first(where: { $0.hasPrefix("--motion-frame=") }),
              let rawValue = argument.split(separator: "=").last,
              let frame = Int(rawValue)
        else { return 0 }
        return sequence.clampedFrame(frame)
    }
}

private struct MotionReferenceHome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guten Morgen").font(.largeTitle.bold())
                    Text("Zuhause").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "moon.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.opacity(0.10), in: Circle())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                referenceCard("Licht Master", value: "Bereit", symbol: "lightbulb.fill", tint: .yellow)
                referenceCard("Medien Master", value: "Alle Medien anschalten", symbol: "play.tv.fill", tint: .blue)
                referenceCard("Klima", value: "21°", symbol: "thermometer.medium", tint: .orange)
                referenceCard("Sicherheit", value: "OK", symbol: "checkmark.shield.fill", tint: .green)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Räume").font(.title2.bold())
                referenceRow("Wohnzimmer", symbol: "sofa.fill")
                referenceRow("Nico Zimmer", symbol: "bed.double.fill")
                referenceRow("Juli Zimmer", symbol: "lightbulb.max.fill")
            }
            .padding(16)
            .iosNextSurface()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 62)
        .padding(.bottom, 28)
    }

    private func referenceCard(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.headline)
            Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(15)
        .iosNextSurface()
    }

    private func referenceRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 30)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct MotionReferenceControlCenter: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                systemStatus.controlCenterModuleReveal(index: 0)
                runner.controlCenterModuleReveal(index: 1)
                activity.controlCenterModuleReveal(index: 2)
                owner.controlCenterModuleReveal(index: 3)
                footer.controlCenterModuleReveal(index: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 36)
        }
        .scrollDisabled(true)
    }

    private var systemStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("System bereit").font(.title.bold())
                    Text("Owner · Runner · Commander · Home Assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            HStack(spacing: 8) {
                miniStatus("Owner", "Online", "person.badge.key.fill", .green)
                miniStatus("Runner", "Online", "server.rack", .green)
                miniStatus("Commander", "LIVE", "terminal.fill", .green)
                miniStatus("HA", "Verbunden", "house.fill", .green)
            }
        }
        .padding(18)
        .iosNextSurface()
    }

    private var runner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runner").font(.title3.bold())
            referenceRow("Runner bereit", detail: "15 online · 15 frei · 0 beschäftigt", symbol: "server.rack", tint: .green)
            referenceRow("Code Commander", detail: "LIVE", symbol: "terminal.fill", tint: .green)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktivität").font(.title3.bold())
            referenceRow("Keine offene Aktivität", detail: "Keine aktiven Jobs, Tickets oder Warnungen", symbol: "checkmark.circle.fill", tint: .green)
        }
    }

    private var owner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Owner Control").font(.title3.bold())
            referenceRow("Projekte", detail: "Tickets, Projekte und Dispatch", symbol: "folder.fill", tint: .indigo)
            referenceRow("Betrieb", detail: "Backups, Diagnose und Wartung", symbol: "wrench.and.screwdriver.fill", tint: .indigo)
        }
    }

    private var footer: some View {
        Label("Owner-Sitzung geschützt", systemImage: "checkmark.shield.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .iosNextSurface()
    }

    private func miniStatus(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func referenceRow(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .iosNextSurface()
    }
}
