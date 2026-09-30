import Foundation

struct ResourceMetrics: Equatable, Sendable {
    let deviceCount: Int
    let activeDeviceCount: Int
    let entityCount: Int
    let activeEntityCount: Int
    let unavailableEntityCount: Int
}

extension AppModel {
    func resourceMetrics(inArea areaID: String) -> ResourceMetrics {
        roomPresentationSnapshot(inArea: areaID).metrics
    }

    func resourceMetrics(inFloor floorID: String) -> ResourceMetrics {
        let index = homeAssistantLookupIndex
        let floorAreas = areas(inFloor: floorID)
        let snapshots = floorAreas.map { roomPresentationSnapshot(inArea: $0.id, using: index) }

        var deviceIDs = Set<String>()
        var uniqueEntities: [String: HomeAssistantEntity] = [:]
        var activeDeviceIDs = Set<String>()

        for snapshot in snapshots {
            deviceIDs.formUnion(snapshot.devices.map(\.id))
            activeDeviceIDs.formUnion(snapshot.activeDeviceIDs)
            for entity in snapshot.entities {
                uniqueEntities[entity.entityID] = entity
            }
        }

        let floorEntities = Array(uniqueEntities.values)
        return ResourceMetrics(
            deviceCount: deviceIDs.count,
            activeDeviceCount: activeDeviceIDs.count,
            entityCount: floorEntities.count,
            activeEntityCount: floorEntities.filter(\.isOn).count,
            unavailableEntityCount: floorEntities.filter { !$0.isAvailable }.count
        )
    }
}
