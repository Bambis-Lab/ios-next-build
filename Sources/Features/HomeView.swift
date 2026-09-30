import SwiftUI

private enum HomeShortcutDestination {
    case area(String)
    case floor(String)
    case outdoors
}

private struct HomeShortcutPresentation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let destination: HomeShortcutDestination
}

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let appModel: AppModel

    private var nicoArea: HomeAssistantArea? { area(named: "Nico Zimmer") }
    private var groundFloor: HomeAssistantFloor? {
        appModel.floors.first { floor in
            floor.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == "erdgeschoss"
        }
    }

    private var featuredItems: [HomeShortcutPresentation] {
        var items: [HomeShortcutPresentation] = []
        if area(named: "Timo Zimmer") != nil {
            items.append(.init(id: "timo", title: "Timo-Zimmer", subtitle: "Persönlicher Bereich", symbol: "house.lodge.fill", tint: .blue, destination: .area("Timo Zimmer")))
        }
        if area(named: "Hütte Master") != nil || area(named: "Hütte") != nil {
            let name = area(named: "Hütte Master") != nil ? "Hütte Master" : "Hütte"
            items.append(.init(id: "huette", title: "Hütte", subtitle: "Gartenhaus & Medien", symbol: "house.and.flag.fill", tint: .orange, destination: .area(name)))
        }
        if hasOutdoorResources {
            items.append(.init(id: "outdoors", title: "Außenbereich", subtitle: "Pool · Rasen · Mähroboter", symbol: "tree.fill", tint: .green, destination: .outdoors))
        }
        if let groundFloor {
            items.append(.init(id: "ground-floor", title: "Erdgeschoss", subtitle: "Räume & Geräte", symbol: "square.grid.2x2.fill", tint: .indigo, destination: .floor(groundFloor.id)))
        } else if area(named: "Wohnzimmer") != nil {
            items.append(.init(id: "living-room", title: "Wohnzimmer", subtitle: "TV & Medien", symbol: "sofa.fill", tint: .teal, destination: .area("Wohnzimmer")))
        }
        return items
    }

    var body: some View {
        ZStack {
            IOS27HomeBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    OwnerHomeHeader(connectionState: appModel.connectionState)
                    if let nicoArea { heroCard(for: nicoArea) }

                    if !featuredItems.isEmpty {
                        sectionTitle("Häufig genutzt")
                        LazyVGrid(columns: featuredColumns, spacing: 12) {
                            ForEach(featuredItems) { item in
                                NavigationLink {
                                    destination(for: item.destination)
                                } label: {
                                    shortcutCard(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(item.title)
                                .accessibilityValue(metricText(for: item.destination))
                                .accessibilityHint("Öffnet den Bereich")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("home-shortcut-\(item.id)")
                            }
                        }
                    }

                    sectionTitle("System & Geräte")
                    systemStrip
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .ios27ScrollBottomClearance()
        }
        .navigationTitle("Zuhause")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func destination(for destination: HomeShortcutDestination) -> some View {
        switch destination {
        case let .area(name):
            if let area = area(named: name) {
                RoomDetailView(area: area, appModel: appModel)
            } else {
                ContentUnavailableView("Bereich nicht verfügbar", systemImage: "house.slash")
            }
        case let .floor(id):
            if let floor = appModel.floors.first(where: { $0.id == id }) {
                FloorDetailView(floor: floor, appModel: appModel)
            } else {
                ContentUnavailableView("Etage nicht verfügbar", systemImage: "building.2")
            }
        case .outdoors:
            OutdoorAreaView(appModel: appModel)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func heroCard(for area: HomeAssistantArea) -> some View {
        let metrics = appModel.resourceMetrics(inArea: area.id)
        return NavigationLink {
            RoomDetailView(area: area, appModel: appModel)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                RadialGradient(colors: [Color.purple.opacity(0.42), .clear], center: .bottomLeading, startRadius: 10, endRadius: 260)
                LinearGradient(colors: [Color.indigo.opacity(0.16), .clear], startPoint: .topTrailing, endPoint: .center)

                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Image(systemName: "house.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.10), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.7))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nico-Zimmer").font(.title2.weight(.bold))
                        Text("Dein Bereich · Medien & Licht")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { heroStatusChips(for: area) }
                        VStack(alignment: .leading, spacing: 8) { heroStatusChips(for: area) }
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(maxWidth: .infinity, minHeight: 224, alignment: .leading)
            .ios27ContentSurface(radius: 30, elevated: true)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nico-Zimmer")
        .accessibilityValue("\(metrics.deviceCount) Geräte, \(metrics.activeEntityCount) aktive Entitäten")
        .accessibilityHint("Öffnet den Raum")
        .accessibilityAddTraits(.isButton)
    }

    private func shortcutCard(_ item: HomeShortcutPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 38, height: 38)
                    .background(item.tint.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(item.tint.opacity(0.16), lineWidth: 0.7))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(metricText(for: item.destination))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .ios27ContentSurface(radius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricText(for destination: HomeShortcutDestination) -> String {
        switch destination {
        case let .area(name):
            guard let area = area(named: name) else { return "Nicht verfügbar" }
            let metrics = appModel.resourceMetrics(inArea: area.id)
            return "\(metrics.deviceCount) Geräte · \(metrics.activeEntityCount) aktive Entitäten"
        case let .floor(id):
            let metrics = appModel.resourceMetrics(inFloor: id)
            let roomCount = appModel.areas(inFloor: id).count
            return "\(roomCount) Räume · \(metrics.deviceCount) Geräte"
        case .outdoors:
            return "\(outdoorResourceCount) Ressourcen"
        }
    }

    private var systemStrip: some View {
        HStack(spacing: 0) {
            HomeMetricTile(title: "Räume", value: "\(appModel.areas.filter(\.isAppRoom).count)", icon: "square.grid.2x2.fill", tint: .blue)
            divider
            HomeMetricTile(title: "Geräte", value: "\(appModel.devices.count)", icon: "cpu.fill", tint: .indigo)
            divider
            HomeMetricTile(title: "Nicht erreichbar", value: "\(unavailableCount)", icon: "exclamationmark.triangle.fill", tint: unavailableCount > 0 ? .orange : .green)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .ios27ContentSurface(radius: 24)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 44)
    }

    @ViewBuilder
    private func heroStatusChips(for area: HomeAssistantArea) -> some View {
        HomeStatusChip(text: "\(activeCount(in: area, domain: "light")) Licht", symbol: "lightbulb.fill")
        HomeStatusChip(text: "\(activeCount(in: area, domain: "media_player")) Medien", symbol: "play.tv.fill")
        HomeStatusChip(text: "\(appModel.resourceMetrics(inArea: area.id).deviceCount) Geräte", symbol: "cpu")
    }

    private var featuredColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func area(named name: String) -> HomeAssistantArea? {
        appModel.areas.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func activeCount(in area: HomeAssistantArea, domain: String? = nil) -> Int {
        appModel.entities(inArea: area.id).filter { entity in
            (domain == nil || entity.domain == domain) && entity.isOn
        }.count
    }

    private var hasOutdoorResources: Bool {
        area(named: "Pool") != nil || area(named: "Rasen") != nil || appModel.entities.contains { $0.domain == "lawn_mower" }
    }

    private var outdoorResourceCount: Int {
        var count = 0
        if area(named: "Pool") != nil { count += 1 }
        if area(named: "Rasen") != nil { count += 1 }
        if appModel.entities.contains(where: { $0.domain == "lawn_mower" }) { count += 1 }
        return count
    }

    private var unavailableCount: Int { appModel.entities.filter { !$0.isAvailable }.count }
}

#Preview("Dark Owner Home") {
    NavigationStack { HomeView(appModel: .preview) }
        .preferredColorScheme(.dark)
}
