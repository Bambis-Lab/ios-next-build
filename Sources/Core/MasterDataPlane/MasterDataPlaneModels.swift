import Foundation

enum MasterDataVerification: String, Codable, CaseIterable, Sendable {
    case verified
    case observed
    case stale
    case unavailable
}

enum MasterDataAuthority: String, Codable, CaseIterable, Sendable {
    case bambisMaster = "Bambis Master"
    case platformGovernance = "Platform Governance"
    case github = "GitHub"
    case runnerControl = "Runner Control"
    case ownerBackend = "Owner Backend"
    case compatibilityAdapter = "Compatibility Adapter"
}

enum MasterRepositoryCategory: String, Codable, CaseIterable, Sendable {
    case product
    case master
    case platform
    case build
    case other

    var title: String {
        switch self {
        case .product: "Produkte"
        case .master: "Master / Infrastruktur"
        case .platform: "Platform"
        case .build: "Build / Distribution"
        case .other: "Weitere"
        }
    }
}

struct MasterFreshness: Codable, Equatable, Sendable {
    let observedAt: Date?
    let ttlSeconds: Double?

    func state(now: Date = Date()) -> MasterDataVerification {
        guard let observedAt else { return .unavailable }
        guard let ttlSeconds else { return .observed }
        return now.timeIntervalSince(observedAt) <= ttlSeconds ? .verified : .stale
    }

    func ageText(now: Date = Date()) -> String {
        guard let observedAt else { return "Keine Beobachtung" }
        let seconds = max(0, Int(now.timeIntervalSince(observedAt)))
        if seconds < 5 { return "gerade eben" }
        if seconds < 60 { return "vor \(seconds)s" }
        if seconds < 3_600 { return "vor \(seconds / 60)m" }
        return "vor \(seconds / 3_600)h"
    }
}

struct MasterEvidence: Codable, Equatable, Identifiable, Sendable {
    let source: String
    let subject: String
    let claim: String
    let observedAt: Date?

    var id: String { "\(source)|\(subject)|\(claim)" }
}

struct MasterRepositoryRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let fullName: String
    let role: String
    let category: MasterRepositoryCategory
    let visibility: String
    let lifecycle: String
    let defaultBranch: String?
    let currentSHA: String?
    let canonical: Bool
    let authority: MasterDataAuthority
    let verification: MasterDataVerification
    let freshness: MasterFreshness
    let evidence: [MasterEvidence]

    enum CodingKeys: String, CodingKey {
        case id, name, role, category, visibility, lifecycle, canonical, authority, verification, freshness, evidence
        case fullName = "full_name"
        case defaultBranch = "default_branch"
        case currentSHA = "current_sha"
    }
}

enum MasterCIState: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case success
    case failure
    case cancelled
    case skipped
    case unknown

    init(status: String?, conclusion: String?) {
        let conclusion = conclusion?.lowercased()
        if conclusion == "success" { self = .success; return }
        if conclusion == "failure" { self = .failure; return }
        if conclusion == "cancelled" { self = .cancelled; return }
        if conclusion == "skipped" { self = .skipped; return }
        switch status?.lowercased() {
        case "queued", "waiting", "pending": self = .queued
        case "in_progress", "running": self = .running
        default: self = .unknown
        }
    }
}

struct MasterCIArtifactRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let sizeBytes: Int64?
    let digest: String?
}

struct MasterCIStepRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let state: MasterCIState
}

struct MasterCIJobRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let runnerName: String?
    let state: MasterCIState
    let startedAt: Date?
    let completedAt: Date?
    let steps: [MasterCIStepRecord]

    enum CodingKeys: String, CodingKey {
        case id, name, state, steps
        case runnerName = "runner_name"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct MasterCIRunRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let repository: String
    let workflow: String
    let runNumber: Int?
    let branch: String?
    let headSHA: String?
    let event: String?
    let state: MasterCIState
    let startedAt: Date?
    let completedAt: Date?
    let jobs: [MasterCIJobRecord]
    let artifacts: [MasterCIArtifactRecord]
    let freshness: MasterFreshness

    enum CodingKeys: String, CodingKey {
        case id, repository, workflow, branch, event, state, jobs, artifacts, freshness
        case runNumber = "run_number"
        case headSHA = "head_sha"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct MasterRunnerRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let online: Bool
    let busy: Bool
    let labels: [String]
    let operatingSystem: String?
    let architecture: String?
    let currentJobID: String?
    let lastSeen: Date?
    let authority: MasterDataAuthority

    enum CodingKeys: String, CodingKey {
        case id, name, online, busy, labels, architecture, authority
        case operatingSystem = "operating_system"
        case currentJobID = "current_job_id"
        case lastSeen = "last_seen"
    }
}

struct MasterRunnerJobRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let repository: String?
    let branch: String?
    let workflow: String?
    let runnerID: String?
    let runnerName: String?
    let state: String
    let startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, repository, branch, workflow, state
        case runnerID = "runner_id"
        case runnerName = "runner_name"
        case startedAt = "started_at"
    }
}

struct MasterDataPlaneGovernance: Codable, Equatable, Sendable {
    let authority: String
    let verification: MasterDataVerification
    let observedAt: Date?
    let capabilities: [String]
    let actionsServerControlled: Bool

    enum CodingKeys: String, CodingKey {
        case authority, verification, capabilities
        case observedAt = "observed_at"
        case actionsServerControlled = "actions_server_controlled"
    }
}

struct MasterDataPlaneSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let repositories: [MasterRepositoryRecord]
    let ciRuns: [MasterCIRunRecord]
    let runners: [MasterRunnerRecord]
    let runnerJobs: [MasterRunnerJobRecord]
    let governance: MasterDataPlaneGovernance
    let sourceHealth: [MasterSourceHealth]

    enum CodingKeys: String, CodingKey {
        case repositories, runners, governance
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case ciRuns = "ci_runs"
        case runnerJobs = "runner_jobs"
        case sourceHealth = "source_health"
    }

    static func compatibility(
        projects: [AdminProjectStatusV2],
        runnerStatus: RunnerStatus?,
        observedAt: Date? = nil
    ) -> MasterDataPlaneSnapshot {
        let now = observedAt ?? Date()
        let repositories = projects.compactMap { project -> MasterRepositoryRecord? in
            guard let fullName = ProjectRegistry.canonicalRepository(for: project) ?? project.repository else { return nil }
            let components = fullName.split(separator: "/")
            let name = components.last.map(String.init) ?? fullName
            let descriptor = ProjectRegistry.descriptor(
                projectID: project.id,
                title: project.title,
                reportedRepository: project.repository
            )
            return MasterRepositoryRecord(
                id: project.id,
                name: name,
                fullName: fullName,
                role: role(for: name),
                category: category(for: name),
                visibility: "unknown",
                lifecycle: "active",
                defaultBranch: descriptor?.defaultBranch,
                currentSHA: project.ci?.headSHA,
                canonical: true,
                authority: .compatibilityAdapter,
                verification: project.ci?.updatedAt == nil ? .observed : .verified,
                freshness: MasterFreshness(observedAt: project.ci?.updatedAt ?? now, ttlSeconds: 300),
                evidence: []
            )
        }

        let ciRuns = projects.compactMap { project -> MasterCIRunRecord? in
            guard let ci = project.ci, let repository = ProjectRegistry.canonicalRepository(for: project) ?? project.repository else { return nil }
            return MasterCIRunRecord(
                id: "\(project.id)-latest",
                repository: repository,
                workflow: ci.workflow ?? "CI",
                runNumber: nil,
                branch: nil,
                headSHA: ci.headSHA,
                event: nil,
                state: MasterCIState(status: ci.status, conclusion: ci.conclusion),
                startedAt: nil,
                completedAt: ci.updatedAt,
                jobs: [],
                artifacts: [],
                freshness: MasterFreshness(observedAt: ci.updatedAt, ttlSeconds: 300)
            )
        }

        let runners = (runnerStatus?.runnerInstances ?? []).map {
            MasterRunnerRecord(
                id: $0.id,
                name: $0.name,
                online: $0.online,
                busy: $0.busy,
                labels: $0.labels ?? [],
                operatingSystem: $0.operatingSystem,
                architecture: $0.architecture,
                currentJobID: $0.currentJobID,
                lastSeen: $0.lastSeen,
                authority: .runnerControl
            )
        }

        let jobs = (runnerStatus?.activeJobs ?? []).map {
            MasterRunnerJobRecord(
                id: $0.id,
                name: $0.name,
                repository: $0.repository,
                branch: $0.branch,
                workflow: $0.workflow,
                runnerID: $0.runnerID,
                runnerName: $0.runnerName,
                state: $0.state,
                startedAt: $0.startedAt
            )
        }

        let runnerObservedAt = runnerStatus?.lastHealthCheck ?? now
        return MasterDataPlaneSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            repositories: repositories,
            ciRuns: ciRuns,
            runners: runners,
            runnerJobs: jobs,
            governance: MasterDataPlaneGovernance(
                authority: "Bambis Master",
                verification: .observed,
                observedAt: now,
                capabilities: [MasterCapability.readOnly.rawValue],
                actionsServerControlled: true
            ),
            sourceHealth: [
                MasterSourceHealth(
                    id: "owner-projects",
                    title: "Repositories / CI",
                    state: projects.isEmpty ? .unavailable : .healthy,
                    authority: .ownerBackend,
                    observedAt: now,
                    lastSuccess: projects.isEmpty ? nil : now,
                    lastFailure: nil,
                    detail: projects.isEmpty ? "Keine Projektdaten geliefert" : "\(projects.count) Projekte beobachtet"
                ),
                MasterSourceHealth(
                    id: "runner",
                    title: "Runner",
                    state: runnerStatus == nil ? .unavailable : .healthy,
                    authority: .runnerControl,
                    observedAt: runnerObservedAt,
                    lastSuccess: runnerStatus == nil ? nil : runnerObservedAt,
                    lastFailure: nil,
                    detail: runnerStatus.map { "\($0.registeredRunners) registriert · \($0.idleRunners) frei · \($0.busyRunners) beschäftigt" } ?? "Runner nicht verfügbar"
                )
            ]
        )
    }

    private static func role(for name: String) -> String {
        switch name {
        case "ios-next": "native-ios"
        case "android-next": "native-android"
        case "next-tv", "firetv-companion": "tv-client"
        case "platform-governance": "governance"
        case "platform-workflows": "ci-platform"
        case "platform-contracts": "contracts"
        case "ios-next-build": "build-mirror"
        case "ios-next-releases": "distribution"
        case "master-orchestration": "control-plane"
        case "master-appliance": "infrastructure"
        case "organization-plugin", "master-runner-mcp": "organization-mcp"
        case "ha-bridge", "mcp-file-bridge": "ha-agent"
        default: "project"
        }
    }

    private static func category(for name: String) -> MasterRepositoryCategory {
        switch name {
        case "ios-next", "android-next", "next-tv", "firetv-companion", "brother-companion", "ha-frontend-next", "ha-config", "ha-intelligence", "blackglass", "ps5-stream-core": .product
        case "master-orchestration", "master-appliance", "organization-plugin", "master-runner-mcp", "ha-bridge", "mcp-file-bridge": .master
        case "platform-governance", "platform-contracts", "platform-workflows", ".github": .platform
        case "ios-next-build", "ios-next-releases": .build
        default: .other
        }
    }
}
