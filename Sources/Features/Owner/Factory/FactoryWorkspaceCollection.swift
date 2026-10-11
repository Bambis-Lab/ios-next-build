import Foundation

/// Safe presentation contract for future Factory list endpoints.
/// No arbitrary server key or raw payload is displayed in the UI.
struct FactoryWorkspaceRecord: Identifiable, Equatable {
    let id: String
    let title: String
    let state: String
}

struct FactoryWorkspaceCollection: Equatable {
    let source: String
    let observedAt: Date?
    let stale: Bool
    let records: [FactoryWorkspaceRecord]
    let nextCursor: String?

    static func decode(_ json: String) throws -> Self {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["schema_version"] as? String == "factory.workspace.v1",
              root["status"] as? String == "ok",
              let source = root["source"] as? String, !source.isEmpty,
              let payload = root["data"] as? [String: Any],
              let items = payload["items"] as? [[String: Any]],
              items.count <= 100 else {
            throw FactoryWorkspaceContractError.invalidEnvelope
        }
        let records: [FactoryWorkspaceRecord] = try items.map {
            guard let id = $0["id"] as? String, !id.isEmpty,
                  let title = ($0["title"] ?? $0["name"]) as? String, !title.isEmpty else {
                throw FactoryWorkspaceContractError.invalidEnvelope
            }
            return FactoryWorkspaceRecord(
                id: String(id.prefix(160)),
                title: String(title.prefix(160)),
                state: String(($0["status"] as? String ?? "Geliefert").prefix(80))
            )
        }
        let when = (root["observed_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        let freshness = root["freshness"] as? [String: Any]
        let observedStale = when.map { date in
            date > Date() || Date().timeIntervalSince(date) > 300
        } ?? true
        return Self(
            source: source,
            observedAt: when,
            stale: (freshness?["stale"] as? Bool ?? true) || observedStale,
            records: records,
            nextCursor: (root["next_cursor"] as? String).map { String($0.prefix(512)) }
        )
    }
}
