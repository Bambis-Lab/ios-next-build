import Foundation
import Observation

/// Single shared source of truth for Factory OAuth, MCP telemetry and workspace
/// compatibility. This class does not perform network I/O until explicitly asked.
@MainActor
@Observable
final class FactoryWorkspaceCoordinator {
    let connection: FactoryConnectionModel

    private(set) var overview: FactoryWorkspaceEnvelope?
    private(set) var sourceStates: [FactoryWorkspaceSourceState] = []
    private(set) var overviewError: String?
    private(set) var isSynchronizing = false
    private(set) var lastSynchronized: Date?
    private(set) var eventHistory = FactoryWorkspaceEventReconciler()
    private(set) var eventHistoryError: String?

    var recentFactoryEvents: [FactoryWorkspaceEvent] { eventHistory.events }
    var eventsRequireResync: Bool { eventHistory.needsResync }

    init(connection: FactoryConnectionModel? = nil) {
        self.connection = connection ?? FactoryConnectionModel()
    }

    var discoveredTools: Set<String> {
        Set(connection.snapshot?.toolNames ?? [])
    }

    var canReadWorkspace: Bool {
        connection.phase == .connected && discoveredTools.contains("workspace_overview_get")
    }

    var isOverviewCurrent: Bool {
        guard let overview, let observed = overview.observedAt,
              !overview.stale, connection.phase == .connected else { return false }
        return observed <= Date() && Date().timeIntervalSince(observed) < 300
    }

    /// Fail closed: an unavailable future tool does not trigger guessed requests.
    func refresh() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        await connection.refresh()
        sourceStates = connection.snapshot?.rows.map {
            FactoryWorkspaceSourceState(
                id: $0.id, title: $0.title, status: $0.status,
                source: $0.source, observedAt: $0.observedAt, isStale: false
            )
        } ?? []

        guard connection.phase == .connected else {
            overview = nil
            overviewError = connection.errorMessage
            return
        }

        if discoveredTools.contains("workspace_overview_get") {
            do {
                let payload = try await connection.readWorkspaceTool("workspace_overview_get")
                overview = try FactoryWorkspaceEnvelope.decode(payload)
                overviewError = nil
            } catch {
                overview = nil
                overviewError = error.localizedDescription
            }
        } else {
            overview = nil
            overviewError = nil // Compatibility adapter remains available.
        }
        await refreshEventHistoryIfAvailable()
        lastSynchronized = Date()
    }

    private func refreshEventHistoryIfAvailable() async {
        guard discoveredTools.contains("events_history_list") else {
            eventHistoryError = nil
            return
        }
        if eventHistory.needsResync {
            eventHistory.reset()
        }
        do {
            var arguments: [String: Any] = ["limit": 100]
            if let last = eventHistory.lastSequence {
                arguments["since_sequence"] = last
            }
            let payload = try await connection.readWorkspaceTool("events_history_list", arguments: arguments)
            eventHistory.append(try FactoryWorkspaceEventBatch.decode(payload))
            eventHistoryError = eventHistory.needsResync ? "Ereignislücke erkannt – vollständige Synchronisation erforderlich." : nil
        } catch {
            eventHistoryError = error.localizedDescription
        }
    }

    func invalidateAfterDisconnect() {
        overview = nil
        overviewError = nil
        sourceStates = []
        lastSynchronized = nil
        eventHistory.reset()
        eventHistoryError = nil
    }

    /// No action execution until a separately reviewed action coordinator is implemented.
    func executeAction(_ name: String) throws {
        guard FactoryWorkspaceToolCatalog.mayExecute(name) else {
            throw FactoryConnectionError.toolNotAvailable(name)
        }
    }
}
