import Foundation

struct HomeAssistantLookupIndex: Sendable {
    let registryByEntityID: [String: HomeAssistantRegistryEntity]
    let deviceByID: [String: HomeAssistantDevice]
    let areaIDByEntityID: [String: String]
    let entityIDsByAreaID: [String: Set<String>]
    let deviceIDsByAreaID: [String: Set<String>]
    let entityIDsByDeviceID: [String: Set<String>]

    init(devices: [HomeAssistantDevice], entityRegistry: [HomeAssistantRegistryEntity]) {
        let deviceByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let registryByEntityID = Dictionary(uniqueKeysWithValues: entityRegistry.map { ($0.entityID, $0) })

        var areaIDByEntityID: [String: String] = [:]
        var entityIDsByAreaID: [String: Set<String>] = [:]
        var deviceIDsByAreaID: [String: Set<String>] = [:]
        var entityIDsByDeviceID: [String: Set<String>] = [:]

        for device in devices {
            if let areaID = device.areaID, !areaID.isEmpty {
                deviceIDsByAreaID[areaID, default: []].insert(device.id)
            }
        }

        for registry in entityRegistry {
            if let deviceID = registry.deviceID {
                entityIDsByDeviceID[deviceID, default: []].insert(registry.entityID)
            }

            let resolvedAreaID: String?
            if let directAreaID = registry.areaID, !directAreaID.isEmpty {
                resolvedAreaID = directAreaID
            } else if let deviceID = registry.deviceID {
                resolvedAreaID = deviceByID[deviceID]?.areaID
            } else {
                resolvedAreaID = nil
            }

            if let resolvedAreaID, !resolvedAreaID.isEmpty {
                areaIDByEntityID[registry.entityID] = resolvedAreaID
                entityIDsByAreaID[resolvedAreaID, default: []].insert(registry.entityID)
                if let deviceID = registry.deviceID {
                    deviceIDsByAreaID[resolvedAreaID, default: []].insert(deviceID)
                }
            }
        }

        self.registryByEntityID = registryByEntityID
        self.deviceByID = deviceByID
        self.areaIDByEntityID = areaIDByEntityID
        self.entityIDsByAreaID = entityIDsByAreaID
        self.deviceIDsByAreaID = deviceIDsByAreaID
        self.entityIDsByDeviceID = entityIDsByDeviceID
    }

    func resolvedAreaID(for entityID: String) -> String? { areaIDByEntityID[entityID] }
    func entityIDs(inArea areaID: String) -> Set<String> { entityIDsByAreaID[areaID] ?? [] }
    func deviceIDs(inArea areaID: String) -> Set<String> { deviceIDsByAreaID[areaID] ?? [] }
}

@MainActor
private final class HomeAssistantLookupIndexCache {
    static let shared = HomeAssistantLookupIndexCache()

    private struct Fingerprint: Equatable {
        let devices: [String]
        let registry: [String]
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let index: HomeAssistantLookupIndex
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func index(for model: AppModel) -> HomeAssistantLookupIndex {
        let fingerprint = Fingerprint(
            devices: model.devices.map { "\($0.id)|\($0.areaID ?? "")" },
            registry: model.entityRegistry.map { "\($0.entityID)|\($0.deviceID ?? "")|\($0.areaID ?? "")" }
        )
        let key = ObjectIdentifier(model)
        if let entry = entries[key], entry.fingerprint == fingerprint {
            return entry.index
        }
        let index = HomeAssistantLookupIndex(devices: model.devices, entityRegistry: model.entityRegistry)
        entries[key] = Entry(fingerprint: fingerprint, index: index)
        return index
    }

    func invalidate(_ model: AppModel) {
        entries.removeValue(forKey: ObjectIdentifier(model))
    }
}

@MainActor
extension AppModel {
    var homeAssistantLookupIndex: HomeAssistantLookupIndex {
        HomeAssistantLookupIndexCache.shared.index(for: self)
    }

    func invalidateHomeAssistantLookupIndex() {
        HomeAssistantLookupIndexCache.shared.invalidate(self)
    }

    func indexedResolvedAreaID(for entityID: String) -> String? {
        homeAssistantLookupIndex.resolvedAreaID(for: entityID)
    }

    func indexedEntities(inArea areaID: String) -> [HomeAssistantEntity] {
        let ids = homeAssistantLookupIndex.entityIDs(inArea: areaID)
        guard !ids.isEmpty else { return [] }
        return entities.filter { ids.contains($0.entityID) }
    }

    func indexedDevices(inArea areaID: String) -> [HomeAssistantDevice] {
        let ids = homeAssistantLookupIndex.deviceIDs(inArea: areaID)
        guard !ids.isEmpty else { return [] }
        return devices.filter { ids.contains($0.id) }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    func indexedRegistryEntity(for entityID: String) -> HomeAssistantRegistryEntity? {
        homeAssistantLookupIndex.registryByEntityID[entityID]
    }
}
