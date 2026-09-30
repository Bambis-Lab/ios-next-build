import Foundation
import QuartzCore
import SwiftUI
import UIKit

enum VisualAcceptanceRun {
    static let nonce: String = {
        let prefix = "--visual-ready-nonce="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return "legacy"
        }

        let raw = String(argument.dropFirst(prefix.count))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = String(raw.filter { character in
            character.unicodeScalars.allSatisfy { allowed.contains($0) }
        })
        return sanitized.isEmpty ? "legacy" : String(sanitized.prefix(96))
    }()
}

struct VisualAcceptanceReadyProbe: UIViewRepresentable {
    let markerBaseName: String
    let accessibilityIdentifier: String
    let payload: String
    var settleMilliseconds: Int = 220

    func makeUIView(context: Context) -> ReadyMarkerView {
        let view = ReadyMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ReadyMarkerView, context: Context) {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(markerBaseName)-\(VisualAcceptanceRun.nonce)")
        uiView.configure(
            markerURL: markerURL,
            payload: payload,
            accessibilityIdentifier: accessibilityIdentifier,
            settleMilliseconds: settleMilliseconds
        )
    }

    final class ReadyMarkerView: UIView {
        private var markerURL: URL?
        private var markerPayload = ""
        private var markerAccessibilityIdentifier = ""
        private var settleMilliseconds = 220
        private var generation = 0
        private var publicationScheduled = false
        private var published = false
        private var lastLayoutSize = CGSize.zero

        func configure(
            markerURL: URL,
            payload: String,
            accessibilityIdentifier: String,
            settleMilliseconds: Int
        ) {
            let key = "\(markerURL.path)|\(payload)|\(accessibilityIdentifier)|\(settleMilliseconds)"
            let currentKey = self.markerURL.map {
                "\($0.path)|\(markerPayload)|\(markerAccessibilityIdentifier)|\(self.settleMilliseconds)"
            }

            if key != currentKey {
                generation += 1
                publicationScheduled = false
                published = false
                self.markerURL = markerURL
                markerPayload = payload
                markerAccessibilityIdentifier = accessibilityIdentifier
                self.settleMilliseconds = max(0, settleMilliseconds)
                isAccessibilityElement = true
                self.accessibilityIdentifier = accessibilityIdentifier
                accessibilityLabel = "Visual acceptance ready"
                accessibilityValue = "pending"
            }

            schedulePublicationIfPossible()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            schedulePublicationIfPossible()
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let size = bounds.size
            if size.width > 0, size.height > 0, size != lastLayoutSize {
                lastLayoutSize = size
                if publicationScheduled || published {
                    generation += 1
                    publicationScheduled = false
                    published = false
                    accessibilityValue = "pending"
                }
            }

            schedulePublicationIfPossible()
        }

        private func schedulePublicationIfPossible() {
            guard window != nil, !publicationScheduled, !published, let markerURL else {
                return
            }

            publicationScheduled = true
            let ticket = generation
            let delay = settleMilliseconds

            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == ticket, self.window != nil else { return }
                self.window?.layoutIfNeeded()
                CATransaction.flush()

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == ticket, self.window != nil else { return }
                    CATransaction.flush()

                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
                        guard let self, self.generation == ticket, self.window != nil else { return }
                        CATransaction.flush()

                        do {
                            try Data(self.markerPayload.utf8).write(to: markerURL, options: .atomic)
                            self.published = true
                            self.publicationScheduled = false
                            self.accessibilityValue = "ready"
                            UIAccessibility.post(notification: .layoutChanged, argument: self)
                        } catch {
                            self.publicationScheduled = false
                            self.accessibilityValue = "write-failed"
                        }
                    }
                }
            }
        }
    }
}
