import Foundation

struct ProjectPresentationSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let repository: String?
    let repositoryMismatch: Bool
    let dispatchCount: Int
    let activeJobs: Int
    let latestDispatchState: String?
    let ciStatus: String?
    let ciConclusion: String?
    let ciWorkflow: String?
    let ciHeadSHA: String?
    let ciUpdatedAt: Date?
    let ciError: String?
    let jobs: [AdminJobStatusV2]

    init(project: AdminProjectStatusV2, jobs: [AdminJobStatusV2]) {
        self.id = project.id
        self.title = project.title
        self.repository = ProjectRegistry.canonicalRepository(for: project)
        self.repositoryMismatch = ProjectRegistry.repositoryMismatch(for: project)
        self.dispatchCount = project.dispatchCount
        self.activeJobs = project.activeJobs
        self.latestDispatchState = project.latestDispatchState
        self.ciStatus = project.ci?.status
        self.ciConclusion = project.ci?.conclusion
        self.ciWorkflow = project.ci?.workflow
        self.ciHeadSHA = project.ci?.headSHA
        self.ciUpdatedAt = project.ci?.updatedAt
        self.ciError = project.ci?.error
        self.jobs = jobs
            .filter { $0.projectID == project.id }
            .sorted { $0.approvedAt > $1.approvedAt }
    }

    var hasCISnapshot: Bool {
        ciStatus != nil || ciConclusion != nil || ciWorkflow != nil || ciHeadSHA != nil || ciUpdatedAt != nil || ciError != nil
    }
}

extension Array where Element == AdminProjectStatusV2 {
    func presentationSnapshots(jobs: [AdminJobStatusV2]) -> [ProjectPresentationSnapshot] {
        let jobsByProject = Dictionary(grouping: jobs, by: \.projectID)
        return map { project in
            ProjectPresentationSnapshot(project: project, jobs: jobsByProject[project.id] ?? [])
        }
    }
}
