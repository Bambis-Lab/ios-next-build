import Foundation

struct RoomPresentationSnapshot: Equatable, Sendable {
    let areaID: String
    let devices: [HomeAssistantDevice]
    let entities: [HomeAssistantEntity]
    let activeDeviceIDs: Set<String>
    let activeEntityCount: Int
    let unavailableEntityCount: Int

    var metrics: ResourceMetrics {
        ResourceMetrics(
            deviceCount: devices.count,
            activeDeviceCount: activeDeviceIDs.count,
            entityCount: entities.count,
            activeEntityCount: activeEntityCount,
            unavailableEntityCount: unavailableEntityCount
        )
    }
}

@MainActor
extension AppModel {
    func roomPresentationSnapshot(inArea areaID: String) -> RoomPresentationSnapshot {
        roomPresentationSnapshot(inArea: areaID, using: homeAssistantLookupIndex)
    }

    func roomPresentationSnapshot(
        inArea areaID: String,
        using index: HomeAssistantLookupIndex
    ) -> RoomPresentationSnapshot {
        let entityIDs = index.entityIDs(inArea: areaID)
        let deviceIDs = index.deviceIDs(inArea: areaID)
        let areaEntities = entityIDs.compactMap(entity(withID:)).sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.entityID < $1.entityID : order == .orderedAscending
        }
        let areaDevices = deviceIDs.compactMap { index.deviceByID[$0] }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        let activeEntities = areaEntities.filter(\.isOn)
        let activeDeviceIDs = Set(activeEntities.compactMap { entity -> String? in
            guard let deviceID = index.registryByEntityID[entity.entityID]?.deviceID,
                  deviceIDs.contains(deviceID) else { return nil }
            return deviceID
        })

        return RoomPresentationSnapshot(
            areaID: areaID,
            devices: areaDevices,
            entities: areaEntities,
            activeDeviceIDs: activeDeviceIDs,
            activeEntityCount: activeEntities.count,
            unavailableEntityCount: areaEntities.filter { !$0.isAvailable }.count
        )
    }
}
