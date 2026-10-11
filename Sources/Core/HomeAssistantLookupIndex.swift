import Foundation

struct HomeAssistantLookupIndex: Sendable {
    let registryByEntityID: [String: HomeAssistantRegistryEntity]
    let deviceByID: [String: HomeAssistantDevice]
    let areaIDByEntityID: [String: String]
    let entityIDsByAreaID: [String: Set<String>]
    let deviceIDsByAreaID: [String: Set<String>]
    let entityIDsByDeviceID: [String: Set<String>]

    init(devices: [HomeAssistantDevice], entityRegistry: [HomeAssistantRegistryEntity]) {
        // Registries may transiently contain duplicate rows while HA is
        // reconciling a reload. Resolve deterministically instead of trapping
        // in Dictionary(uniqueKeysWithValues:).
        var deviceByID: [String: HomeAssistantDevice] = [:]
        for device in devices { deviceByID[device.id] = device }
        var registryByEntityID: [String: HomeAssistantRegistryEntity] = [:]
        for registry in entityRegistry { registryByEntityID[registry.entityID] = registry }

        var areaIDByEntityID: [String: String] = [:]
        var entityIDsByAreaID: [String: Set<String>] = [:]
        var deviceIDsByAreaID: [String: Set<String>] = [:]
        var entityIDsByDeviceID: [String: Set<String>] = [:]

        for device in deviceByID.values {
            if let areaID = device.areaID, !areaID.isEmpty {
                deviceIDsByAreaID[areaID, default: []].insert(device.id)
            }
        }

        for registry in registryByEntityID.values {
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
extension AppModel {
    /// No O(N) fingerprint on each access, no global ObjectIdentifier cache.
    /// The owner invalidates this model-local index on registry/device changes.
    var homeAssistantLookupIndex: HomeAssistantLookupIndex {
        if let registryIndexCache { return registryIndexCache }
        let trace = IOSNextPerformance.begin("HA.RegistryIndexRebuild")
        defer { IOSNextPerformance.end("HA.RegistryIndexRebuild", trace) }
        let index = HomeAssistantLookupIndex(devices: devices, entityRegistry: entityRegistry)
        registryIndexCache = index
        return index
    }

    func invalidateHomeAssistantLookupIndex() {
        registryIndexCache = nil
    }

    func indexedResolvedAreaID(for entityID: String) -> String? {
        homeAssistantLookupIndex.resolvedAreaID(for: entityID)
    }

    func indexedEntities(inArea areaID: String) -> [HomeAssistantEntity] {
        let ids = homeAssistantLookupIndex.entityIDs(inArea: areaID)
        guard !ids.isEmpty else { return [] }
        return ids.compactMap(entity(withID:)).sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.entityID < $1.entityID : order == .orderedAscending
        }
    }

    func indexedDevices(inArea areaID: String) -> [HomeAssistantDevice] {
        let index = homeAssistantLookupIndex
        return index.deviceIDs(inArea: areaID).compactMap { index.deviceByID[$0] }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
    }

    func indexedRegistryEntity(for entityID: String) -> HomeAssistantRegistryEntity? {
        homeAssistantLookupIndex.registryByEntityID[entityID]
    }
}
