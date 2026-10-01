import Foundation

enum MasterSourceState: String, Codable, CaseIterable, Sendable {
    case healthy
    case degraded
    case stale
    case unavailable

    var title: String {
        switch self {
        case .healthy: "LIVE"
        case .degraded: "Eingeschränkt"
        case .stale: "Veraltet"
        case .unavailable: "Nicht verfügbar"
        }
    }
}

struct MasterSourceHealth: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let state: MasterSourceState
    let authority: MasterDataAuthority
    let observedAt: Date?
    let lastSuccess: Date?
    let lastFailure: Date?
    let detail: String

    enum CodingKeys: String, CodingKey {
        case id, title, state, authority, detail
        case observedAt = "observed_at"
        case lastSuccess = "last_success"
        case lastFailure = "last_failure"
    }
}

struct MasterStorageMount: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let mountPath: String
    let usedPercent: Double?
    let totalBytes: Int64?
    let freeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case id, title
        case mountPath = "mount_path"
        case usedPercent = "used_percent"
        case totalBytes = "total_bytes"
        case freeBytes = "free_bytes"
    }

    var severity: MasterStorageSeverity {
        guard let usedPercent else { return .unknown }
        if usedPercent > 95 { return .critical }
        if usedPercent >= 90 { return .warning }
        if usedPercent >= 80 { return .notice }
        return .normal
    }
}

enum MasterStorageSeverity: String, Codable, Sendable {
    case normal
    case notice
    case warning
    case critical
    case unknown
}

struct MasterReleaseProvenance: Codable, Equatable, Sendable {
    let version: String
    let build: String
    let sourceSHA: String?
    let buildSHA: String?
    let releaseTag: String?
    let ipaSHA256: String?
    let xcodeVersion: String?
    let publishedAt: Date?
    let rollbackVersion: String?

    enum CodingKeys: String, CodingKey {
        case version, build
        case sourceSHA = "source_sha"
        case buildSHA = "build_sha"
        case releaseTag = "release_tag"
        case ipaSHA256 = "ipa_sha256"
        case xcodeVersion = "xcode_version"
        case publishedAt = "published_at"
        case rollbackVersion = "rollback_version"
    }
}

struct MasterReleaseDrift: Equatable, Sendable {
    let runningVersion: String
    let runningBuild: String
    let backendInstalledVersion: String?
    let backendAvailableVersion: String?

    var hasBackendDrift: Bool {
        guard let backendInstalledVersion else { return false }
        return backendInstalledVersion != runningVersion && backendInstalledVersion != "\(runningVersion) (\(runningBuild))"
    }
}

struct MasterSanitizedLogEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let component: String
    let level: String
    let event: String
    let message: String
    let correlationID: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, component, level, event, message
        case correlationID = "correlation_id"
    }
}

enum MasterDiagnosticRedactor {
    private static let blockedFragments = [
        "authorization", "bearer ", "token", "secret", "password", "cookie", "x-owner-device-session", "x-break-glass-session"
    ]

    static func sanitized(_ value: String) -> String {
        let lower = value.lowercased()
        if blockedFragments.contains(where: { lower.contains($0) }) {
            return "[redacted]"
        }
        return value
    }

    static func export(
        appVersion: String,
        appBuild: String,
        snapshot: MasterDataPlaneSnapshot,
        storage: [MasterStorageMount] = [],
        logs: [MasterSanitizedLogEntry] = []
    ) -> String {
        var lines: [String] = []
        lines.append("iOS Next \(appVersion) (\(appBuild))")
        lines.append("Master Data Plane schema \(snapshot.schemaVersion)")
        lines.append("Generated: \(snapshot.generatedAt.formatted(.iso8601))")
        lines.append("Repositories: \(snapshot.repositories.count)")
        lines.append("CI runs: \(snapshot.ciRuns.count)")
        lines.append("Runners: \(snapshot.runners.count)")
        lines.append("Runner jobs: \(snapshot.runnerJobs.count)")
        lines.append("Governance authority: \(sanitized(snapshot.governance.authority))")
        for health in snapshot.sourceHealth {
            lines.append("Source \(health.title): \(health.state.title) · \(sanitized(health.detail))")
        }
        for mount in storage {
            let usage = mount.usedPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            lines.append("Storage \(mount.title): \(usage)")
        }
        for log in logs.suffix(20) {
            lines.append("Log \(log.component)/\(log.level): \(sanitized(log.message))")
        }
        return lines.joined(separator: "\n")
    }
}
