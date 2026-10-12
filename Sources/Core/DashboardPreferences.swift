import Foundation
import Observation

struct DashboardPreferenceOption: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

private struct DashboardPreferencePayload: Codable {
    var orderedIDs: [String] = []
    var hiddenIDs: Set<String> = []
}

/// Local, profile-scoped presentation preferences only. It stores no HA IDs
/// outside shortcut IDs, credentials, access tokens, or device state.
@MainActor
@Observable
final class DashboardPreferencesStore {
    private(set) var orderedIDs: [String]
    private(set) var hiddenIDs: Set<String>
    let profileID: String

    private var storageKey: String { Self.storageKey(for: profileID) }

    private static func storageKey(for profileID: String) -> String {
        "iosnext.dashboard.preferences.v1.\(profileID)"
    }

    init(profileID: String) {
        self.profileID = profileID
        if let data = UserDefaults.standard.data(forKey: Self.storageKey(for: profileID)),
           let payload = try? JSONDecoder().decode(DashboardPreferencePayload.self, from: data) {
            orderedIDs = payload.orderedIDs
            hiddenIDs = payload.hiddenIDs
        } else {
            orderedIDs = []
            hiddenIDs = []
        }
    }

    func isVisible(_ id: String) -> Bool { !hiddenIDs.contains(id) }

    func rank(of id: String) -> Int {
        orderedIDs.firstIndex(of: id) ?? Int.max
    }

    func toggleVisibility(_ id: String, visible: Bool) {
        if visible { hiddenIDs.remove(id) } else { hiddenIDs.insert(id) }
        persist()
    }

    func move(_ id: String, by offset: Int, availableIDs: [String]) {
        var effective = orderedIDs.filter { availableIDs.contains($0) }
        for value in availableIDs where !effective.contains(value) { effective.append(value) }
        guard let index = effective.firstIndex(of: id) else { return }
        let target = index + offset
        guard effective.indices.contains(target) else { return }
        effective.swapAt(index, target)
        orderedIDs = effective
        persist()
    }

    func ensureKnownIDs(_ ids: [String]) {
        var changed = false
        for id in ids where !orderedIDs.contains(id) {
            orderedIDs.append(id)
            changed = true
        }
        if changed { persist() }
    }

    func reset() {
        orderedIDs = []
        hiddenIDs = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist() {
        let payload = DashboardPreferencePayload(orderedIDs: orderedIDs, hiddenIDs: hiddenIDs)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
