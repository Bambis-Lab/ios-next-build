import Foundation

struct ProjectDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let repository: String?
    let defaultBranch: String?
    let aliases: Set<String>

    fileprivate var normalizedKeys: Set<String> {
        aliases.map(ProjectRegistry.normalize).reduce(into: Set<String>()) { $0.insert($1) }
            .union([ProjectRegistry.normalize(id), ProjectRegistry.normalize(title)])
            .union(repository.map { [ProjectRegistry.normalize($0)] } ?? [])
    }
}

enum ProjectRegistry {
    static let projects: [ProjectDescriptor] = [
        ProjectDescriptor(
            id: "ios-next",
            title: "iOS App",
            repository: "Bambis-Lab/ios-next",
            defaultBranch: "main",
            aliases: [
                "ios next", "ios app", "ios-app", "ios_next", "ios-next",
                "nicofroeba16-cell/ios-app", "nicofroeba16-cell/ha-ios-next-ios", "ha-ios-next-ios"
            ]
        ),
        ProjectDescriptor(
            id: "fire-tv-companion",
            title: "Fire TV Companion",
            repository: "Bambis-Lab/firetv-companion",
            defaultBranch: "main",
            aliases: [
                "fire tv", "fire tv companion", "amazon tv", "amazontv-app",
                "nicofroeba16-cell/amazontv-app"
            ]
        ),
        ProjectDescriptor(
            id: "home-assistant-dashboard",
            title: "Home Assistant Dashboard",
            repository: "Bambis-Lab/ha-config",
            defaultBranch: "main",
            aliases: [
                "home assistant dashboard", "ha dashboard", "ha-config",
                "nicofroeba16-cell/ha-config"
            ]
        ),
        ProjectDescriptor(
            id: "intelligence-suite",
            title: "Intelligence Suite",
            repository: "Bambis-Lab/ha-intelligence",
            defaultBranch: "main",
            aliases: [
                "intelligence suite", "intelligence-suite-",
                "nicofroeba16-cell/intelligence-suite-"
            ]
        ),
        ProjectDescriptor(
            id: "file-bridge",
            title: "File Bridge",
            repository: "Bambis-Lab/mcp-file-bridge",
            defaultBranch: "main",
            aliases: [
                "file bridge", "file-bridge-mcp", "file bridge mcp",
                "nicofroeba16-cell/file-bridge-mcp"
            ]
        ),
        ProjectDescriptor(
            id: "global-project-health",
            title: "Global Project Health",
            repository: nil,
            defaultBranch: nil,
            aliases: [
                "global project health", "project health", "global health",
                "global-health", "global-project-health"
            ]
        )
    ]

    static func descriptor(projectID: String, title: String, reportedRepository: String?) -> ProjectDescriptor? {
        let projectID = normalize(projectID)
        let title = normalize(title)
        let repository = sanitizedRepository(reportedRepository).map(normalize)

        // Prefer the stable project id. This prevents an unrelated title or stale
        // reported repository from selecting the first descriptor in the registry.
        if !projectID.isEmpty,
           let exact = projects.first(where: { normalize($0.id) == projectID }) {
            return exact
        }

        if !title.isEmpty,
           let exact = projects.first(where: { normalize($0.title) == title || $0.normalizedKeys.contains(title) }) {
            return exact
        }

        if let repository,
           let exact = projects.first(where: { $0.normalizedKeys.contains(repository) }) {
            return exact
        }

        return nil
    }

    static func canonicalRepository(projectID: String, title: String, reportedRepository: String?) -> String? {
        if let descriptor = descriptor(projectID: projectID, title: title, reportedRepository: reportedRepository) {
            return descriptor.repository
        }
        return sanitizedRepository(reportedRepository)
    }

    static func canonicalDefaultBranch(projectID: String, title: String, reportedRepository: String?) -> String? {
        descriptor(projectID: projectID, title: title, reportedRepository: reportedRepository)?.defaultBranch
    }

    static func repositoryMismatch(projectID: String, title: String, reportedRepository: String?) -> Bool {
        guard
            let reported = sanitizedRepository(reportedRepository),
            let canonical = descriptor(projectID: projectID, title: title, reportedRepository: reportedRepository)?.repository
        else { return false }
        return normalize(reported) != normalize(canonical)
    }

    static func canonicalRepository(for project: AdminProjectStatusV2) -> String? {
        canonicalRepository(projectID: project.id, title: project.title, reportedRepository: project.repository)
    }

    static func repositoryMismatch(for project: AdminProjectStatusV2) -> Bool {
        repositoryMismatch(projectID: project.id, title: project.title, reportedRepository: project.repository)
    }

    static func canonicalRepository(for route: ProjectRoute) -> String? {
        canonicalRepository(projectID: route.id, title: route.title, reportedRepository: route.repository)
    }

    private static func sanitizedRepository(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    fileprivate static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
