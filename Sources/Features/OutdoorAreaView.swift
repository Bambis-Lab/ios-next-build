import SwiftUI

struct OutdoorAreaView: View {
    let appModel: AppModel

    private var poolArea: HomeAssistantArea? { area(named: "Pool") }
    private var lawnArea: HomeAssistantArea? { area(named: "Rasen") }
    private var mower: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == "lawn_mower.rasen_mahroboter" }
            ?? appModel.entities.first { $0.domain == "lawn_mower" }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IOS27StatusCard(
                    title: "Außenbereich",
                    value: "\(resourceCount) Ressourcen",
                    symbol: "tree.fill",
                    tint: .green,
                    detail: "Pool · Rasen · Mähroboter"
                )

                IOS27SectionHeader(title: "Ressourcen", subtitle: "Direkt auffindbar statt ineinander versteckt")

                if let poolArea {
                    NavigationLink {
                        RoomDetailView(area: poolArea, appModel: appModel)
                    } label: {
                        let metrics = appModel.resourceMetrics(inArea: poolArea.id)
                        IOS27StatusCard(title: "Pool", value: "\(metrics.deviceCount) Geräte", symbol: "drop.fill", tint: .cyan, detail: "\(metrics.activeEntityCount) aktive Entitäten")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("outdoor-resource-pool")
                }

                if let lawnArea {
                    NavigationLink {
                        RoomDetailView(area: lawnArea, appModel: appModel)
                    } label: {
                        let metrics = appModel.resourceMetrics(inArea: lawnArea.id)
                        IOS27StatusCard(title: "Rasen", value: "\(metrics.deviceCount) Geräte", symbol: "leaf.fill", tint: .green, detail: "\(metrics.activeEntityCount) aktive Entitäten")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("outdoor-resource-lawn")
                }

                if let mower {
                    NavigationLink {
                        MowerResourceView(mower: mower, appModel: appModel)
                    } label: {
                        IOS27StatusCard(title: "Mähroboter", value: mower.stateDisplayText, symbol: "gearshape.2.fill", tint: mower.isAvailable ? .green : .secondary, detail: "Eigenständige Ressource")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("outdoor-resource-mower")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground(style: .room(named: "Außenbereich", juliAccent: nil, nicoMediaActive: false)))
        .navigationTitle("Außenbereich")
        .navigationBarTitleDisplayMode(.large)
    }

    private var resourceCount: Int {
        [poolArea != nil, lawnArea != nil, mower != nil].filter { $0 }.count
    }

    private func area(named name: String) -> HomeAssistantArea? {
        appModel.areas.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}

struct MowerResourceView: View {
    let mower: HomeAssistantEntity
    let appModel: AppModel

    private var status: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == "sensor.rasen_mahroboter_status" }
    }

    private var battery: HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == "sensor.rasen_mahroboter_akku" }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IOS27StatusCard(title: "Mähroboter", value: mower.stateDisplayText, symbol: "gearshape.2.fill", tint: mower.isAvailable ? .green : .secondary, detail: mower.isAvailable ? "Ressource verfügbar" : "Nicht verfügbar")
                if let status {
                    IOS27StatusCard(title: "Status", value: status.stateDisplayText, symbol: "info.circle.fill", tint: status.isAvailable ? .green : .secondary)
                }
                if let battery {
                    IOS27StatusCard(title: "Akku", value: battery.secondaryStateText, symbol: "battery.75percent", tint: .green)
                }
                IOS27SectionHeader(title: "Technische Details", subtitle: "Entity-Ansicht ohne erfundene Steuerbefehle")
                NavigationLink {
                    EntityControlView(entityID: mower.entityID, appModel: appModel)
                } label: {
                    OwnerStatusRow(title: "Home-Assistant-Entität", detail: mower.entityID, symbol: "chevron.left.forwardslash.chevron.right", value: "Öffnen")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground(style: .room(named: "Rasen", juliAccent: nil, nicoMediaActive: false)))
        .navigationTitle("Mähroboter")
        .navigationBarTitleDisplayMode(.inline)
    }
}
