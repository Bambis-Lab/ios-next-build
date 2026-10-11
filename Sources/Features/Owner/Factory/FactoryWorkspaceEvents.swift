import Foundation

/// Contract for a future Factory event history endpoint. Until the server
/// advertises it, existing Runner/Live adapters remain the authoritative feed.
struct FactoryWorkspaceEvent: Identifiable, Equatable {
    let id: String
    let sequence: Int64
    let kind: String
    let source: String
    let occurredAt: Date?
}

struct FactoryWorkspaceEventBatch {
    let events: [FactoryWorkspaceEvent]
    let lastSequence: Int64?

    static func decode(_ json: String) throws -> Self {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema_version"] as? String == "factory.events.v1",
              let entries = object["events"] as? [[String: Any]] else {
            throw FactoryWorkspaceContractError.invalidEnvelope
        }
        let decoded: [FactoryWorkspaceEvent] = try entries.map { item in
            guard let id = item["event_id"] as? String, !id.isEmpty,
                  let number = item["sequence"] as? NSNumber, number.int64Value > 0,
                  let type = item["type"] as? String, !type.isEmpty,
                  let source = item["source"] as? String, !source.isEmpty else {
                throw FactoryWorkspaceContractError.invalidEnvelope
            }
            let date = (item["occurred_at"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
            return FactoryWorkspaceEvent(
                id: id, sequence: number.int64Value, kind: type,
                source: source, occurredAt: date
            )
        }
        let last = (object["last_sequence"] as? NSNumber)?.int64Value
        return Self(events: decoded, lastSequence: last)
    }
}

/// Deterministic cursor and deduplication. A gap blocks further claiming
/// "live" until a full refetch reconciles the missing sequence.
struct FactoryWorkspaceEventReconciler {
    private(set) var events: [FactoryWorkspaceEvent] = []
    private(set) var lastSequence: Int64?
    private(set) var needsResync = false

    mutating func append(_ batch: FactoryWorkspaceEventBatch) {
        guard !needsResync else { return }
        for entry in batch.events.sorted(by: { $0.sequence < $1.sequence }) {
            if let lastSequence {
                if entry.sequence <= lastSequence { continue }
                if entry.sequence != lastSequence + 1 {
                    needsResync = true
                    return
                }
            }
            self.lastSequence = entry.sequence
            if !events.contains(where: { $0.id == entry.id }) {
                events.append(entry)
            }
        }
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
        if let terminal = batch.lastSequence,
           let lastSequence, terminal > lastSequence {
            needsResync = true
        }
    }

    mutating func reset() {
        events = []
        lastSequence = nil
        needsResync = false
    }
}
