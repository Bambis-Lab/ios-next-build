import Foundation
import SwiftUI

enum IOSNextMotionSequence: String, CaseIterable {
    case startup
    case controlCenterUnlock = "control-center-unlock"
    case controlCenterLock = "control-center-lock"

    static let masterFramesPerSecond = 120.0

    var frameCount: Int {
        switch self {
        case .startup: 87
        case .controlCenterUnlock: 109
        case .controlCenterLock: 27
        }
    }

    var lastFrame: Int { frameCount - 1 }
    var duration: TimeInterval { Double(lastFrame) / Self.masterFramesPerSecond }

    func clampedFrame(_ frame: Int) -> Int {
        min(max(frame, 0), lastFrame)
    }

    func frame(at elapsed: TimeInterval) -> Int {
        clampedFrame(Int((max(0, elapsed) * Self.masterFramesPerSecond).rounded(.down)))
    }

    func milliseconds(at frame: Int) -> Double {
        Double(clampedFrame(frame)) * 1_000.0 / Self.masterFramesPerSecond
    }
}

struct IOSNextStartupMotionSample: Equatable {
    let frame: Int
    let contentOpacity: Double
    let contentYOffset: Double
    let contentScale: Double
    let backdropOpacity: Double
    let haloOpacity: Double
    let haloDiameter: Double
    let logoScale: Double
    let logoYOffset: Double
    let logoOpacity: Double
    let glassOpacity: Double
    let glassWidthFraction: Double
    let glassHeight: Double
    let glassCornerRadius: Double
}

struct IOSNextControlCenterMotionSample: Equatable {
    let frame: Int
    let lockScale: Double
    let lockOpenProgress: Double
    let lockOpacity: Double
    let lockBlur: Double
    let flashOpacity: Double
    let glassOpacity: Double
    let glassWidthFraction: Double
    let glassHeight: Double
    let glassCornerRadius: Double
    let readyOpacity: Double
    let readyScale: Double

    func moduleReveal(index: Int) -> Double {
        let starts = [7, 9, 11, 13, 15]
        let start = starts[min(max(index, 0), starts.count - 1)]
        return IOSNextMotionMath.segment(frame, start, start + 17, easing: .easeOutQuint)
    }
}

struct IOSNextControlCenterLockMotionSample: Equatable {
    let frame: Int
    let contentOpacity: Double
    let contentScale: Double
    let contentBlur: Double
    let lockedOpacity: Double
    let lockedScale: Double
}

enum IOSNextMasterMotion {
    static func startup(frame rawFrame: Int) -> IOSNextStartupMotionSample {
        let frame = IOSNextMotionSequence.startup.clampedFrame(rawFrame)
        let content = IOSNextMotionMath.segment(frame, 0, 31, easing: .easeOutQuint)
        let backdrop = IOSNextMotionMath.segment(frame, 0, 24, easing: .easeOutQuint)

        return IOSNextStartupMotionSample(
            frame: frame,
            contentOpacity: IOSNextMotionMath.lerp(0.82, 1, content),
            contentYOffset: IOSNextMotionMath.lerp(4, 0, content),
            contentScale: IOSNextMotionMath.lerp(0.998, 1, content),
            backdropOpacity: IOSNextMotionMath.lerp(0.20, 0, backdrop),
            haloOpacity: 0,
            haloDiameter: 0,
            logoScale: 1,
            logoYOffset: 0,
            logoOpacity: 0,
            glassOpacity: 0,
            glassWidthFraction: 1,
            glassHeight: 0,
            glassCornerRadius: 0
        )
    }

    static func controlCenterUnlock(frame rawFrame: Int) -> IOSNextControlCenterMotionSample {
        let frame = IOSNextMotionSequence.controlCenterUnlock.clampedFrame(rawFrame)
        let settle = IOSNextMotionMath.segment(frame, 8, 42, easing: .easeOutQuint)
        let ready = IOSNextMotionMath.segment(frame, 28, 50, easing: .easeOutQuint)
        let flashIn = IOSNextMotionMath.segment(frame, 8, 11, easing: .easeOutCubic)
        let flashOut = IOSNextMotionMath.segment(frame, 11, 24, easing: .easeInOutCubic)

        return IOSNextControlCenterMotionSample(
            frame: frame,
            lockScale: 1,
            lockOpenProgress: 1,
            lockOpacity: 0,
            lockBlur: 0,
            flashOpacity: 0.035 * flashIn * (1 - flashOut),
            glassOpacity: 0,
            glassWidthFraction: 1,
            glassHeight: 0,
            glassCornerRadius: 0,
            readyOpacity: ready,
            readyScale: IOSNextMotionMath.lerp(0.985, 1, settle)
        )
    }

    static func controlCenterLock(frame rawFrame: Int) -> IOSNextControlCenterLockMotionSample {
        let frame = IOSNextMotionSequence.controlCenterLock.clampedFrame(rawFrame)
        let content = IOSNextMotionMath.segment(frame, 0, 20, easing: .easeInOutCubic)
        let destination = IOSNextMotionMath.segment(frame, 5, 26, easing: .easeOutQuint)
        return IOSNextControlCenterLockMotionSample(
            frame: frame,
            contentOpacity: IOSNextMotionMath.lerp(1, 0.10, content),
            contentScale: IOSNextMotionMath.lerp(1, 0.985, content),
            contentBlur: IOSNextMotionMath.lerp(0, 3.5, content),
            lockedOpacity: destination,
            lockedScale: IOSNextMotionMath.lerp(0.975, 1, destination)
        )
    }
}

private enum IOSNextMotionEasing {
    case linear
    case easeOutCubic
    case easeOutQuint
    case easeInOutCubic
}

private enum IOSNextMotionMath {
    static func segment(_ frame: Int, _ start: Int, _ end: Int, easing: IOSNextMotionEasing) -> Double {
        guard end > start else { return frame >= end ? 1 : 0 }
        let x = clamp01(Double(frame - start) / Double(end - start))
        switch easing {
        case .linear: return x
        case .easeOutCubic: return 1 - pow(1 - x, 3)
        case .easeOutQuint: return 1 - pow(1 - x, 5)
        case .easeInOutCubic:
            return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        }
    }

    static func lerp(_ from: Double, _ to: Double, _ progress: Double) -> Double {
        from + (to - from) * clamp01(progress)
    }

    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct IOSNextStartupRevealHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var finished = false
    let onFinished: () -> Void
    let content: Content

    init(onFinished: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.onFinished = onFinished
        self.content = content()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / IOSNextMotionSequence.masterFramesPerSecond, paused: finished)) { timeline in
            let frame = IOSNextMotionSequence.startup.frame(at: timeline.date.timeIntervalSince(startedAt))
            let sample = IOSNextMasterMotion.startup(frame: reduceMotion ? IOSNextMotionSequence.startup.lastFrame : frame)
            ZStack {
                content
                    .opacity(sample.contentOpacity)
                    .offset(y: CGFloat(sample.contentYOffset))
                    .scaleEffect(CGFloat(sample.contentScale))
                if !finished && !reduceMotion {
                    IOSNextStartupRevealLayer(sample: sample)
                        .allowsHitTesting(false)
                }
            }
        }
        .task {
            if reduceMotion {
                finished = true
                onFinished()
                return
            }
            try? await Task.sleep(for: .milliseconds(355))
            guard !Task.isCancelled else { return }
            finished = true
            onFinished()
        }
    }
}

struct IOSNextStartupRevealLayer: View {
    let sample: IOSNextStartupMotionSample

    var body: some View {
        Color("LaunchBackground")
            .opacity(sample.backdropOpacity)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private struct ControlCenterMotionFrameKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var controlCenterMotionFrame: Int? {
        get { self[ControlCenterMotionFrameKey.self] }
        set { self[ControlCenterMotionFrameKey.self] = newValue }
    }
}

private struct ControlCenterModuleRevealModifier: ViewModifier {
    @Environment(\.controlCenterMotionFrame) private var frame
    let index: Int

    func body(content: Content) -> some View {
        guard let frame else { return AnyView(content) }
        let progress = IOSNextMasterMotion.controlCenterUnlock(frame: frame).moduleReveal(index: index)
        return AnyView(
            content
                .opacity(0.72 + (0.28 * progress))
                .offset(y: CGFloat(4 * (1 - progress)))
                .scaleEffect(CGFloat(0.995 + (0.005 * progress)))
        )
    }
}

extension View {
    func controlCenterModuleReveal(index: Int) -> some View {
        modifier(ControlCenterModuleRevealModifier(index: index))
    }
}

struct IOSNextControlCenterUnlockHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var finished = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / IOSNextMotionSequence.masterFramesPerSecond, paused: finished)) { timeline in
            let frame = IOSNextMotionSequence.controlCenterUnlock.frame(at: timeline.date.timeIntervalSince(startedAt))
            let effectiveFrame = reduceMotion ? IOSNextMotionSequence.controlCenterUnlock.lastFrame : frame
            let sample = IOSNextMasterMotion.controlCenterUnlock(frame: effectiveFrame)
            ZStack {
                content
                    .environment(\.controlCenterMotionFrame, finished ? nil : effectiveFrame)
                    .opacity(0.88 + (0.12 * sample.readyOpacity))
                    .offset(y: CGFloat(6 * (1 - sample.readyOpacity)))
                    .scaleEffect(CGFloat(0.985 + (0.015 * sample.readyOpacity)))
                    .allowsHitTesting(finished || reduceMotion)

                if !finished && !reduceMotion {
                    IOSNextControlCenterUnlockLayer(sample: sample)
                        .allowsHitTesting(false)
                }
            }
        }
        .task {
            if reduceMotion {
                IOSNextFeedbackCenter.shared.play(.controlCenterUnlock)
                finished = true
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            IOSNextFeedbackCenter.shared.play(.controlCenterUnlock)
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }
            finished = true
        }
    }
}

struct IOSNextControlCenterUnlockLayer: View {
    let sample: IOSNextControlCenterMotionSample

    var body: some View {
        Circle()
            .fill(Color.indigo)
            .frame(width: 120, height: 120)
            .blur(radius: 44)
            .opacity(sample.flashOpacity)
            .accessibilityHidden(true)
    }
}

struct IOSNextControlCenterLockHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isLocking: Bool
    let onFinished: () -> Void
    let content: Content
    @State private var startedAt = Date()

    init(isLocking: Bool, onFinished: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isLocking = isLocking
        self.onFinished = onFinished
        self.content = content()
    }

    var body: some View {
        Group {
            if isLocking && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / IOSNextMotionSequence.masterFramesPerSecond)) { timeline in
                    let frame = IOSNextMotionSequence.controlCenterLock.frame(at: timeline.date.timeIntervalSince(startedAt))
                    let sample = IOSNextMasterMotion.controlCenterLock(frame: frame)
                    ZStack {
                        content
                            .opacity(sample.contentOpacity)
                            .scaleEffect(CGFloat(sample.contentScale))
                            .blur(radius: CGFloat(sample.contentBlur))
                        IOSNextControlCenterLockedSurface(
                            message: "Der Bereich ist lokal gesperrt.",
                            isAuthenticating: false,
                            onUnlock: {},
                            onConfigure: {}
                        )
                        .opacity(sample.lockedOpacity)
                        .scaleEffect(CGFloat(sample.lockedScale))
                        .allowsHitTesting(false)
                    }
                }
            } else {
                content
            }
        }
        .onChange(of: isLocking, initial: true) { _, active in
            if active { startedAt = Date() }
        }
        .task(id: isLocking) {
            guard isLocking else { return }
            if reduceMotion {
                onFinished()
                return
            }
            try? await Task.sleep(for: .milliseconds(225))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

struct IOSNextControlCenterLockLayer: View {
    let sample: IOSNextControlCenterLockMotionSample

    var body: some View {
        IOSNextControlCenterLockedSurface(
            message: "Der Bereich ist lokal gesperrt.",
            isAuthenticating: false,
            onUnlock: {},
            onConfigure: {}
        )
        .opacity(sample.lockedOpacity)
        .scaleEffect(CGFloat(sample.lockedScale))
        .accessibilityHidden(true)
    }
}

struct IOSNextControlCenterLockedSurface: View {
    let message: String
    let isAuthenticating: Bool
    let onUnlock: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        ZStack {
            OwnerBackground()
            VStack(spacing: 20) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                Text("Control Center")
                    .font(.largeTitle.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isAuthenticating {
                    ProgressView()
                        .controlSize(.large)
                    Text("Owner-Berechtigung wird geprüft …")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Mit Face ID entsperren", systemImage: "faceid", action: onUnlock)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                    Button("Konfiguration ändern", action: onConfigure)
                        .buttonStyle(.glass)
                }
            }
            .padding(24)
        }
    }
}
