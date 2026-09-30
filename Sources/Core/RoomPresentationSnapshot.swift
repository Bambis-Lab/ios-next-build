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
        let areaEntities = entities.filter { entityIDs.contains($0.entityID) }
        let areaDevices = devices.filter { deviceIDs.contains($0.id) }
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
