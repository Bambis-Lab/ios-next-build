import Foundation
import os

/// OS Signposts for reproducible Instruments sessions (no private payloads).
/// Disabled by default in production. Enable via IOSNEXT_PERF_TRACE=1 in the
/// Xcode Scheme environment, never by logging user content or credentials.
enum IOSNextPerformance {
    private static let signposter = OSSignposter(
        subsystem: "de.nicofroeba16.iosnext", category: "Performance"
    )
    static let enabled = ProcessInfo.processInfo.environment["IOSNEXT_PERF_TRACE"] == "1"

    static func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard enabled else { return nil }
        return signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        signposter.endInterval(name, state)
    }
}
