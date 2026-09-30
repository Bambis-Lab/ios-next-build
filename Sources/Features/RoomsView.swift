import SwiftUI
import UIKit

struct RoomsView: View {
    let appModel: AppModel

    private struct FloorSection: Identifiable {
        let floor: HomeAssistantFloor
        let areas: [HomeAssistantArea]

        var id: String { floor.id }
    }

    private var floorSections: [FloorSection] {
        appModel.floors
            .sorted { lhs, rhs in
                let lhsLevel = lhs.level ?? Int.max
                let rhsLevel = rhs.level ?? Int.max
                return lhsLevel == rhsLevel
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhsLevel < rhsLevel
            }
            .compactMap { floor in
                let areas = appModel.areas(inFloor: floor.id)
                return areas.isEmpty ? nil : FloorSection(floor: floor, areas: areas)
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    HomeMetricTile(title: "Räume", value: "\(appModel.areas.filter(\.isAppRoom).count)", icon: "square.grid.2x2.fill", tint: .blue)
                    HomeMetricTile(title: "Geräte", value: "\(appModel.devices.count)", icon: "cpu.fill", tint: .indigo)
                }
                .padding(.horizontal, 6)
                .ios27ContentSurface(radius: 24)

                IOS27SectionHeader(title: "Räume", subtitle: "Bereiche und zugeordnete Geräte")

                if appModel.areas.isEmpty {
                    EmptyFeatureView(
                        title: "Keine Räume geladen",
                        symbol: "door.left.hand.open",
                        message: "Home-Assistant-Areas erscheinen hier nach der Verbindung."
                    )
                } else if floorSections.isEmpty {
                    roomLinks(appModel.areas.filter(\.isAppRoom).sorted {
                        $0.appDisplayName.localizedStandardCompare($1.appDisplayName) == .orderedAscending
                    })
                } else {
                    ForEach(floorSections) { section in
                        IOS27SectionHeader(
                            title: section.floor.name,
                            subtitle: "\(section.areas.count) Räume"
                        )
                        roomLinks(section.areas)
                    }

                    if !appModel.appAreasWithoutFloor.isEmpty {
                        IOS27SectionHeader(title: "Weitere Räume", subtitle: "Ohne Etagenzuordnung")
                        roomLinks(appModel.appAreasWithoutFloor)
                    }
                }

                if !appModel.unassignedDevices.isEmpty {
                    IOS27SectionHeader(title: "Technische Details", subtitle: "Nicht zugeordnete Geräte")
                    DisclosureGroup("Geräte ohne Raum (\(appModel.unassignedDevices.count))") {
                        NavigationLink {
                            DeviceCollectionView(
                                title: "Geräte ohne Raum",
                                devices: appModel.unassignedDevices,
                                appModel: appModel
                            )
                        } label: {
                            Label("Geräte anzeigen", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .ios27ContentSurface(radius: 24)
                }

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle("Räume")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func roomLinks(_ areas: [HomeAssistantArea]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(areas) { area in
                NavigationLink {
                    RoomDetailView(area: area, appModel: appModel)
                } label: {
                    let metrics = appModel.resourceMetrics(inArea: area.id)
                    IOS27StatusCard(
                        title: area.appDisplayName,
                        value: "\(metrics.deviceCount) Geräte",
                        symbol: "door.left.hand.open",
                        tint: .blue,
                        detail: "\(metrics.activeEntityCount) aktive Entitäten"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FloorDetailView: View {
    let floor: HomeAssistantFloor
    let appModel: AppModel

    private var areas: [HomeAssistantArea] { appModel.areas(inFloor: floor.id) }
    private var metrics: ResourceMetrics { appModel.resourceMetrics(inFloor: floor.id) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IOS27StatusCard(
                    title: "Etagenübersicht",
                    value: "\(areas.count) Räume · \(metrics.deviceCount) Geräte",
                    symbol: "building.2.fill",
                    tint: .indigo,
                    detail: "\(metrics.activeEntityCount) aktive Entitäten"
                )

                IOS27SectionHeader(title: "Unterräume", subtitle: "Home-Assistant-Raumstruktur")
                LazyVStack(spacing: 10) {
                    ForEach(areas) { area in
                        NavigationLink {
                            RoomDetailView(area: area, appModel: appModel)
                        } label: {
                            let areaMetrics = appModel.resourceMetrics(inArea: area.id)
                            IOS27StatusCard(
                                title: area.appDisplayName,
                                value: "\(areaMetrics.deviceCount) Geräte",
                                symbol: "door.left.hand.open",
                                tint: .blue,
                                detail: "\(areaMetrics.activeEntityCount) aktive Entitäten"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground())
        .navigationTitle(floor.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct RoomDetailView: View {
    let area: HomeAssistantArea
    let appModel: AppModel

    private var roomEntities: [HomeAssistantEntity] { appModel.entities(inArea: area.id) }
    private var isNicoRoom: Bool { area.name.localizedCaseInsensitiveCompare("Nico Zimmer") == .orderedSame }
    private var isHuetteRoom: Bool { area.name.localizedCaseInsensitiveCompare("Hütte Master") == .orderedSame || area.name.localizedCaseInsensitiveCompare("Hütte") == .orderedSame }
    private var isRasenRoom: Bool { area.name.localizedCaseInsensitiveCompare("Rasen") == .orderedSame }
    private var isJuliRoom: Bool { area.name.localizedCaseInsensitiveCompare("Juli Zimmer") == .orderedSame }
    private var isPoolRoom: Bool { area.name.localizedCaseInsensitiveCompare("Pool") == .orderedSame }
    private var isHandysRoom: Bool { area.name.localizedCaseInsensitiveCompare("Handys") == .orderedSame }
    private var isFlurRoom: Bool { area.name.localizedCaseInsensitiveCompare("Flur") == .orderedSame }
    private var isArbeitszimmer: Bool { area.name.localizedCaseInsensitiveCompare("Arbeitszimmer") == .orderedSame }
    private var isDienstRoom: Bool { area.name.localizedCaseInsensitiveCompare("Dienst") == .orderedSame }
    private var lights: [HomeAssistantEntity] {
        if isNicoRoom {
            let order = [
                "light.kronach_fernseher_links",
                "light.kronach_fernseher_rechts",
                "light.kronach_schrank",
                "switch.schreibtisch_rgb_standlampe_steckdose_1"
            ]
            return order.compactMap(entity)
        }
        if isHuetteRoom {
            return ["light.hutte", "light.tisch_tisch"].compactMap(entity)
        }
        return roomEntities.filter { $0.domain == "light" || ($0.domain == "switch" && $0.displayName.localizedCaseInsensitiveContains("licht")) }
    }
    private var media: [HomeAssistantEntity] {
        if isNicoRoom {
            return [
                "media_player.nico_zimmer_untergeschoss_apple_tv",
                "media_player.denon_avr_x1300w",
                "media_player.playstation_5"
            ].compactMap(entity)
        }
        if isHuetteRoom {
            return ["media_player.denon_avr_x1800h", "media_player.gigatv_home"].compactMap(entity)
        }
        return appModel.mediaPlayersForPresentation(inArea: area.id)
    }
    private var roomBackgroundStyle: IOS27AmbientBackgroundStyle {
        let juliLight = entity("light.battletron_gaming_monitor_strip_2024_fernseher_hintergrund")
        let juliAccent = juliLight?.isOn == true ? juliLight?.ios27LightTint : nil
        let nicoMediaActive = entity("binary_sensor.nico_medien_aktiv")?.isOn == true
        return .room(
            named: area.appDisplayName,
            juliAccent: juliAccent,
            nicoMediaActive: nicoMediaActive
        )
    }

    private var otherControls: [HomeAssistantEntity] {
        guard !isNicoRoom && !isHuetteRoom && !isRasenRoom && !isJuliRoom
                && !isPoolRoom && !isHandysRoom && !isFlurRoom && !isArbeitszimmer && !isDienstRoom else { return [] }
        return roomEntities.filter { entity in
            !lights.contains(entity) && !media.contains(entity) && entity.isPrimaryRoomControl
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !isPoolRoom && !isRasenRoom {
                    IOS27RoomHeaderCard(area: area, appModel: appModel)
                }

                if isNicoRoom {
                    NicoRoomDashboardContent(appModel: appModel)
                } else if isHuetteRoom {
                    HuetteRoomDashboardContent(appModel: appModel)
                } else if isRasenRoom {
                    RasenRoomDashboardContent(appModel: appModel)
                } else if isJuliRoom {
                    JuliRoomDashboardContent(appModel: appModel)
                } else if isPoolRoom {
                    PoolRoomDashboardContent(appModel: appModel)
                } else if isHandysRoom {
                    HandysRoomDashboardContent(appModel: appModel)
                } else if isFlurRoom {
                    PrinterRoomDashboardContent(kind: .flur, appModel: appModel)
                } else if isArbeitszimmer {
                    PrinterRoomDashboardContent(kind: .arbeitszimmer, appModel: appModel)
                } else if isDienstRoom {
                    DienstRoomDashboardContent(appModel: appModel)
                } else {
                    if !otherControls.isEmpty {
                        IOS27SectionHeader(title: "Steuerung", subtitle: "Primäre Raumaktionen")
                        ForEach(otherControls) { entity in
                            NavigationLink {
                                EntityControlView(entityID: entity.entityID, appModel: appModel)
                            } label: {
                                IOS27StatusCard(
                                    title: entity.displayName,
                                    value: entity.secondaryStateText,
                                    symbol: entity.iconName,
                                    tint: entity.isOn ? .green : .secondary
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !lights.isEmpty {
                        IOS27SectionHeader(title: "Licht", subtitle: "Direkte Raumsteuerung")
                        ForEach(lights) { entity in
                            IOS27LightCard(entity: entity, appModel: appModel)
                        }
                    }

                    if !media.isEmpty {
                        IOS27SectionHeader(title: "Medien", subtitle: "Player und Receiver")
                        ForEach(media) { entity in
                            if appModel.isFireTVCompanion(entity) {
                                IOS27FireTVCompanionCard(player: entity, appModel: appModel)
                            } else {
                                IOS27MediaCard(
                                    player: entity,
                                    appModel: appModel,
                                    volumePlayer: volumePlayer(for: entity)
                                )
                            }
                        }
                    }
                }

                IOS27RoomTechnicalDetails(area: area, appModel: appModel)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ios27ScrollBottomClearance()
        .background(IOS27HomeBackground(style: roomBackgroundStyle))
        .navigationTitle(area.appDisplayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }

    private func volumePlayer(for entity: HomeAssistantEntity) -> HomeAssistantEntity? {
        guard entity.entityID == "media_player.nico_zimmer_untergeschoss_apple_tv" else { return nil }
        return appModel.entities.first { $0.entityID == "media_player.denon_avr_x1300w" }
    }
}




private struct PoolRoomDashboardContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let appModel: AppModel

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        IOS27SectionHeader(title: "Pool", subtitle: "Temperatur · Wärmepumpe")

        if let temperature = entity("sensor.vertical_pool_heat_pump_temperatur") {
            IOS27StatusCard(
                title: "Wassertemperatur",
                value: temperature.secondaryStateText,
                symbol: "thermometer.medium",
                tint: .cyan
            )
        }

        LazyVGrid(columns: columns, spacing: 12) {
            if let heatPump = entity("switch.vertical_pool_heat_pump_schalter") {
                IOS27RoomActionTile(
                    title: "Wärmepumpe",
                    subtitle: heatPump.isOn ? "Ein" : "Aus",
                    symbol: "heat.waves",
                    tint: heatPump.isOn ? .orange : .secondary
                ) {
                    Task { await appModel.toggle(heatPump) }
                }
            }
            if let breaker = entity("switch.sys_wi_fi_smart_meter_schalter") {
                IOS27RoomActionTile(
                    title: "Sicherung",
                    subtitle: breaker.isOn ? "Ein" : "Aus",
                    symbol: "bolt.fill",
                    tint: breaker.isOn ? .yellow : .secondary
                ) {
                    Task { await appModel.toggle(breaker) }
                }
            }
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct HandysRoomDashboardContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let appModel: AppModel

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        IOS27SectionHeader(title: "Netzwerkschutz", subtitle: "AdGuard Home")

        if let protection = entity("switch.adguard_home_schutz") {
            IOS27RoomActionTile(
                title: "Schutz",
                subtitle: protection.isOn ? "Aktiv" : "Aus",
                symbol: "shield.lefthalf.filled",
                tint: protection.isOn ? .green : .secondary
            ) {
                Task { await appModel.toggle(protection) }
            }
        }

        LazyVGrid(columns: columns, spacing: 12) {
            if let blocked = entity("sensor.adguard_home_blockierte_dns_abfragen") {
                IOS27StatusCard(
                    title: "Blockiert",
                    value: blocked.secondaryStateText,
                    symbol: "hand.raised.fill",
                    tint: .orange
                )
            }
            if let ratio = entity("sensor.adguard_home_anteil_blockierter_dns_abfragen") {
                IOS27StatusCard(
                    title: "Blockierungsanteil",
                    value: ratio.secondaryStateText,
                    symbol: "chart.bar.fill",
                    tint: .blue
                )
            }
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct PrinterRoomDashboardContent: View {
    enum Kind { case flur, arbeitszimmer }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: Kind
    let appModel: AppModel

    private var statusID: String {
        switch kind {
        case .flur: return "sensor.hl_l3210cw_status"
        case .arbeitszimmer: return "sensor.mfc_j4410dw_status"
        }
    }

    private var consumableIDs: [String] {
        switch kind {
        case .flur:
            return [
                "sensor.hl_l3210cw_verbleibender_schwarz_toner",
                "sensor.hl_l3210cw_verbleibender_cyan_toner",
                "sensor.hl_l3210cw_verbleibender_magenta_toner",
                "sensor.hl_l3210cw_verbleibender_gelb_toner"
            ]
        case .arbeitszimmer:
            return [
                "sensor.mfc_j4410dw_verbleibende_schwarz_tinte",
                "sensor.mfc_j4410dw_verbleibende_cyan_tinte",
                "sensor.mfc_j4410dw_verbleibende_magenta_tinte",
                "sensor.mfc_j4410dw_verbleibende_gelb_tinte"
            ]
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        IOS27SectionHeader(title: "Drucker", subtitle: kind == .flur ? "Brother HL-L3210CW" : "Brother MFC-J4410DW")

        if let status = entity(statusID) {
            NavigationLink {
                EntityControlView(entityID: status.entityID, appModel: appModel)
            } label: {
                IOS27StatusCard(
                    title: "Status",
                    value: status.stateDisplayText,
                    symbol: "printer.fill",
                    tint: status.isAvailable ? .blue : .secondary,
                    detail: "Verbrauchsmaterial und Details"
                )
            }
            .buttonStyle(.plain)
        }

        let consumables = consumableIDs.compactMap(entity)
        if !consumables.isEmpty {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(consumables) { item in
                    IOS27StatusCard(
                        title: consumableName(item),
                        value: item.secondaryStateText,
                        symbol: "drop.fill",
                        tint: .secondary
                    )
                }
            }
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }

    private func consumableName(_ entity: HomeAssistantEntity) -> String {
        let id = entity.entityID.lowercased()
        if id.contains("schwarz") { return "Schwarz" }
        if id.contains("cyan") { return "Cyan" }
        if id.contains("magenta") { return "Magenta" }
        if id.contains("gelb") { return "Gelb" }
        return entity.displayName
    }
}

private struct DienstRoomDashboardContent: View {
    let appModel: AppModel

    var body: some View {
        IOS27SectionHeader(title: "Dienste", subtitle: "Home Assistant · AI")

        if let hacs = entity("update.hacs_update") {
            NavigationLink {
                EntityControlView(entityID: hacs.entityID, appModel: appModel)
            } label: {
                IOS27StatusCard(
                    title: "HACS",
                    value: hacs.state == "on" ? "Update verfügbar" : "Aktuell",
                    symbol: "shippingbox.fill",
                    tint: hacs.state == "on" ? .orange : .green
                )
            }
            .buttonStyle(.plain)
        }

        if let ai = entity("sensor.ai_automation_suggester_google_ai_provider_status_google") {
            IOS27StatusCard(
                title: "AI Provider",
                value: ai.stateDisplayText,
                symbol: "sparkles",
                tint: ai.isAvailable ? .purple : .secondary
            )
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct JuliRoomDashboardContent: View {
    let appModel: AppModel

    private var tv: HomeAssistantEntity? {
        appModel.fireTVCompanion(inArea: "juli_zimmer")
    }

    private var backlight: HomeAssistantEntity? {
        entity("light.battletron_gaming_monitor_strip_2024_fernseher_hintergrund")
    }

    var body: some View {
        IOS27SectionHeader(
            title: "Medien",
            subtitle: "Juli TV · TV-Hintergrundlicht"
        )

        if let tv {
            VStack(spacing: 8) {
                IOS27MediaCard(player: tv, appModel: appModel)
                if let backlight {
                    JuliTVBacklightCard(light: backlight, tv: tv, appModel: appModel)
                }
            }
        } else {
            IOS27StatusCard(
                title: "Juli TV Companion",
                value: "Nicht eingerichtet",
                symbol: "tv.badge.wifi",
                tint: .secondary
            )
            if let backlight {
                JuliTVBacklightCard(light: backlight, tv: nil, appModel: appModel)
            }
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct JuliTVBacklightCard: View {
    @State private var showControls = false
    let light: HomeAssistantEntity
    let tv: HomeAssistantEntity?
    let appModel: AppModel

    private var tvAllowsLight: Bool { tv?.isOn == true }
    private var canToggle: Bool { light.isOn || tvAllowsLight }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.led.wide.fill")
                .font(.headline)
                .foregroundStyle(light.ios27LightTint)
                .frame(width: 42, height: 42)
                .background(light.ios27LightTint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("TV-Hintergrundlicht")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Mit Juli TV gekoppelt", systemImage: "link")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                guard canToggle else { return }
                Task { await appModel.toggle(light) }
            } label: {
                Image(systemName: "power")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 42)
            }
            .ios27GlassButton()
            .tint(light.ios27LightTint)
            .disabled(!canToggle)
            .accessibilityLabel(light.isOn ? "TV-Hintergrundlicht ausschalten" : "TV-Hintergrundlicht einschalten")
            .accessibilityHint(tvAllowsLight || light.isOn ? "Schaltet das Hintergrundlicht um" : "Nur bei eingeschaltetem Juli TV verfügbar")
        }
        .padding(16)
        .ios27ContentSurface(radius: 24)
        .ios27HoldAction {
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            LightControlSheet(
                entityID: light.entityID,
                appModel: appModel,
                canTurnOn: tvAllowsLight,
                turnOnBlockedReason: "Nur bei eingeschaltetem Juli TV"
            )
        }
    }

    private var statusText: String {
        if light.isOn { return "Eingeschaltet" }
        if tvAllowsLight { return "Ausgeschaltet" }
        return "Nur bei eingeschaltetem TV"
    }
}


private struct RasenRoomDashboardContent: View {
    let appModel: AppModel

    private var status: HomeAssistantEntity? { entity("sensor.rasen_mahroboter_status") }
    private var battery: HomeAssistantEntity? { entity("sensor.rasen_mahroboter_akku") }
    private var mower: HomeAssistantEntity? { entity("lawn_mower.rasen_mahroboter") }

    var body: some View {
        IOS27SectionHeader(title: "Mähroboter", subtitle: "Status · Akku · Steuerung")

        if let status {
            IOS27StatusCard(
                title: "Status",
                value: status.stateDisplayText,
                symbol: "robotic.vacuum.fill",
                tint: status.isAvailable ? .green : .secondary
            )
        }

        if let battery {
            IOS27StatusCard(
                title: "Akku",
                value: battery.secondaryStateText,
                symbol: "battery.75percent",
                tint: .green
            )
        }

        if let mower {
            NavigationLink {
                EntityControlView(entityID: mower.entityID, appModel: appModel)
            } label: {
                IOS27StatusCard(
                    title: "Steuerung",
                    value: mower.stateDisplayText,
                    symbol: "gearshape.2.fill",
                    tint: .teal,
                    detail: "Mäheroptionen öffnen"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct HuetteRoomDashboardContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let appModel: AppModel

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        IOS27SectionHeader(title: "Beleuchtung", subtitle: "Ambiente · Tisch")

        ForEach(["light.hutte", "light.tisch_tisch"].compactMap(entity)) { light in
            IOS27LightCard(entity: light, appModel: appModel)
        }

        LazyVGrid(columns: columns, spacing: 12) {
            let lightMaster = entity("group.hutte_beleuchtung") ?? HomeAssistantEntity(
                entityID: "group.hutte_beleuchtung",
                state: ["light.hutte", "light.tisch_tisch"].compactMap(entity).contains(where: \.isOn) ? "on" : "off",
                attributes: [:]
            )
            IOS27RoomActionTile(
                title: "Licht Master",
                subtitle: lightMaster.isOn ? "Geräte an" : "Alles aus",
                symbol: "power",
                tint: lightMaster.isOn ? .green : .red
            ) {
                Task { await appModel.toggle(lightMaster) }
            }

            if let dimmed = entity("scene.hutte_master_tisch_gedimmt") {
                IOS27RoomActionTile(
                    title: "Tisch Gedimmt",
                    subtitle: "Szene",
                    symbol: "lamp.table.fill",
                    tint: .orange
                ) {
                    Task { await appModel.activate(dimmed) }
                }
            }
        }

        IOS27SectionHeader(title: "Medien", subtitle: "Denon · GigaTV")
        ForEach(["media_player.denon_avr_x1800h", "media_player.gigatv_home"].compactMap(entity)) { player in
            IOS27MediaCard(player: player, appModel: appModel)
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct NicoRoomDashboardContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let appModel: AppModel

    private var tvLights: [HomeAssistantEntity] {
        ["light.kronach_fernseher_links", "light.kronach_fernseher_rechts"].compactMap(entity)
    }

    private var compactLights: [HomeAssistantEntity] {
        ["light.kronach_schrank", "switch.schreibtisch_rgb_standlampe_steckdose_1"].compactMap(entity)
    }

    private var mediaPlayers: [HomeAssistantEntity] {
        [
            "media_player.nico_zimmer_untergeschoss_apple_tv",
            "media_player.denon_avr_x1300w",
            "media_player.playstation_5"
        ].compactMap(entity)
    }

    private var lightMaster: HomeAssistantEntity {
        entity("group.nico_beleuchtung") ?? HomeAssistantEntity(
            entityID: "group.nico_beleuchtung",
            state: (tvLights + compactLights).contains(where: \.isOn) ? "on" : "off",
            attributes: [:]
        )
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        IOS27SectionHeader(title: "Beleuchtung", subtitle: "TV · Schrank · Schreibtisch")

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tvLights) { light in
                NicoPrimaryLightTile(entity: light, appModel: appModel)
            }
        }

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(compactLights) { light in
                NicoCompactControlTile(entity: light, appModel: appModel)
            }
        }

        LazyVGrid(columns: columns, spacing: 12) {
            IOS27RoomActionTile(
                title: "Licht Master",
                subtitle: lightMaster.isOn ? "Geräte an" : "Alles aus",
                symbol: "power",
                tint: lightMaster.isOn ? .green : .red
            ) {
                Task { await appModel.toggle(lightMaster) }
            }

            if let prisma = entity("scene.kronach_kronach_prisma") {
                IOS27RoomActionTile(
                    title: "Prisma",
                    subtitle: "Schrank-Effekt",
                    symbol: "paintpalette.fill",
                    tint: .purple
                ) {
                    Task { await appModel.activate(prisma) }
                }
            }
        }

        IOS27SectionHeader(title: "Medien-Center", subtitle: "Apple TV · Denon · PS5")

        LazyVGrid(columns: columns, spacing: 12) {
            if let mediaMaster = entity("script.nico_medien_master_zentrale") {
                let mediaState = entity("binary_sensor.nico_medien_aktiv")
                IOS27RoomActionTile(
                    title: "Medien Master",
                    subtitle: mediaState?.isOn == true ? "Alle Medien ausschalten" : "Alle Medien anschalten",
                    symbol: "power",
                    tint: mediaState?.isOn == true ? .green : .red
                ) {
                    Task { await appModel.activateScript(mediaMaster) }
                }
            }

            if let tvPower = entity("switch.tv_steckdose_1") {
                IOS27RoomActionTile(
                    title: "TV Steckdose",
                    subtitle: tvPower.isOn ? "Ein" : "Aus",
                    symbol: "powerplug.fill",
                    tint: tvPower.isOn ? .green : .secondary
                ) {
                    Task { await appModel.toggle(tvPower) }
                }
            }
        }

        if !mediaPlayers.isEmpty {
            IOS27MediaZoneCard(
                title: "Nico Medien",
                subtitle: "Apple TV und Denon gekoppelt · PlayStation separat",
                players: mediaPlayers,
                masterState: entity("binary_sensor.nico_medien_aktiv"),
                masterScript: nil,
                appModel: appModel,
                coupledPlaybackPlayerID: "media_player.nico_zimmer_untergeschoss_apple_tv",
                coupledOutputPlayerID: "media_player.denon_avr_x1300w",
                playerNameOverrides: [
                    "media_player.nico_zimmer_untergeschoss_apple_tv": "Apple TV",
                    "media_player.denon_avr_x1300w": "Denon AVR",
                    "media_player.playstation_5": "PlayStation 5"
                ]
            )
        }
    }

    private func entity(_ id: String) -> HomeAssistantEntity? {
        appModel.entities.first { $0.entityID == id }
    }
}

private struct NicoPrimaryLightTile: View {
    @State private var showControls = false
    let entity: HomeAssistantEntity
    let appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(entity.ios27LightTint)
                    .frame(width: 38, height: 38)
                    .background(entity.ios27LightTint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    Task { await appModel.toggle(entity) }
                } label: {
                    Image(systemName: "power")
                        .frame(width: 38, height: 38)
                }
                .ios27GlassButton()
                .tint(entity.ios27LightTint)
                .accessibilityLabel(entity.isOn ? "Ausschalten" : "Einschalten")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.displayName)
                    .font(.headline)
                Text(entity.isOn ? "Eingeschaltet" : "Ausgeschaltet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let brightness = entity.brightness {
                Slider(value: Binding(
                    get: { min(max(brightness, 0), 1) },
                    set: { value in Task { await appModel.setBrightness(value, for: entity) } }
                ))
                .accessibilityLabel("Helligkeit \(entity.displayName)")
                .accessibilityValue("\(Int((brightness) * 100)) Prozent")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .ios27ContentSurface(radius: 24)
        .ios27HoldAction {
            guard entity.domain == "light" else { return }
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            LightControlSheet(entityID: entity.entityID, appModel: appModel)
        }
    }
}

private struct NicoCompactControlTile: View {
    @State private var showControls = false
    let entity: HomeAssistantEntity
    let appModel: AppModel

    var body: some View {
        Button {
            Task { await appModel.toggle(entity) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: entity.domain == "light" ? "lightbulb.fill" : "lamp.desk.fill")
                    .foregroundStyle(entity.ios27LightTint)
                    .frame(width: 34, height: 34)
                    .background(entity.ios27LightTint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.displayName).font(.subheadline.weight(.semibold))
                    Text(entity.isOn ? "Ein" : "Aus").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(14)
            .ios27ContentSurface(radius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entity.displayName)
        .accessibilityValue(entity.isOn ? "Ein" : "Aus")
        .accessibilityHint("Schaltet \(entity.displayName) um")
        .ios27HoldAction {
            guard entity.domain == "light" else { return }
            showControls = true
        }
        .sheet(isPresented: $showControls) {
            LightControlSheet(entityID: entity.entityID, appModel: appModel)
        }
    }
}


private struct DeviceCollectionView: View {
    let title: String
    let devices: [HomeAssistantDevice]
    let appModel: AppModel

    var body: some View {
        List(devices) { device in
            NavigationLink {
                DeviceDetailView(device: device, appModel: appModel)
            } label: {
                DeviceRow(device: device, entityCount: appModel.entities(forDevice: device.id).count)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DeviceDetailView: View {
    let device: HomeAssistantDevice
    let appModel: AppModel

    var body: some View {
        let entities = appModel.entities(forDevice: device.id)
        List {
            Section("Gerät") {
                LabeledContent("Name", value: device.name)
                if let areaID = device.areaID,
                   let area = appModel.areas.first(where: { $0.id == areaID }) {
                    LabeledContent("Raum", value: area.name)
                } else {
                    LabeledContent("Raum", value: "Nicht zugeordnet")
                }
                LabeledContent("Entitäten", value: "\(entities.count)")
            }

            Section("Entitäten") {
                if entities.isEmpty {
                    Text("Für dieses Gerät sind aktuell keine aktiven Entitäten geladen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entities) { entity in
                        NavigationLink {
                            EntityControlView(entityID: entity.entityID, appModel: appModel)
                        } label: {
                            EntityRow(entity: entity)
                        }
                    }
                }
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DeviceRow: View {
    let device: HomeAssistantDevice
    let entityCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .frame(width: 30)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.medium))
                Text("\(entityCount) Entitäten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }
}
