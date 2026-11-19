import Foundation

/// Local metadata only. No ticket content, repository credentials, dispatch,
/// or work-order creation. The account/device/key scope is part of the AAD.
@MainActor
final class SecureTicketProjectStore {
    private struct Snapshot: Codable {
        let version: Int
        let projects: [String:String]
    }
    private let scope: TicketScreenScope
    private let archive: ChatHistoryArchive

    convenience init(scope: TicketScreenScope) throws {
        guard scope.owner else { throw ChatError.authenticationFailed }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let archive = try ChatHistoryArchive(scopedData: encoder.encode(scope),
            namespace: "ticketProject.v1", folder: "EncryptedTicketProjects")
        try self.init(scope: scope, archive: archive)
    }

    init(scope: TicketScreenScope, archive: ChatHistoryArchive) throws {
        guard scope.owner else { throw ChatError.authenticationFailed }
        self.scope = scope
        self.archive = archive
    }

    func read() throws -> [String:String] {
        guard let snapshot = try archive.load(Snapshot.self) else { return [:] }
        guard snapshot.version == 1, snapshot.projects.count <= 1000,
              snapshot.projects.allSatisfy({ entry in EncryptedTicketMessage.validID(entry.key) &&
                  ProjectRegistry.projects.contains(where: { $0.id == entry.value }) }) else {
            throw ChatHistoryError.invalidArchive
        }
        return snapshot.projects
    }

    func assign(ticketID: String, projectID: String?) throws {
        guard scope.owner, EncryptedTicketMessage.validID(ticketID),
              projectID == nil || ProjectRegistry.projects.contains(where: { $0.id == projectID })
        else { throw ChatError.invalidConfiguration }
        var projects = try read()
        projects[ticketID] = projectID
        guard projects.count <= 1000 else { throw ChatHistoryError.capacity }
        try archive.save(Snapshot(version:1, projects:projects))
    }
}
