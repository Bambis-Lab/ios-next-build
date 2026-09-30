import SwiftUI

struct OwnerNotificationItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
}

struct OwnerNotificationsView: View {
    let model: AdminControlModel

    private var items: [OwnerNotificationItem] {
        var result: [OwnerNotificationItem] = []
        if let error = model.lastError {
            result.append(.init(id: "backend-error", title: "Owner Backend", detail: error, symbol: "exclamationmark.triangle.fill", tint: .red))
        }
        if model.backendStatus?.databaseHealthy == false {
            result.append(.init(id: "database", title: "Datenbank gestört", detail: "Das Backend meldet den Datenbankzustand als fehlerhaft.", symbol: "externaldrive.badge.exclamationmark", tint: .red))
        }
        if model.backendStatus?.maintenanceMode == true {
            result.append(.init(id: "maintenance", title: "Wartungsmodus aktiv", detail: "Der normale Backend-Betrieb ist eingeschränkt.", symbol: "wrench.and.screwdriver.fill", tint: .orange))
        }
        if let depth = model.backendStatus?.queueDepth, depth > 20 {
            result.append(.init(id: "queue", title: "Warteschlange erhöht", detail: "\(depth) Einträge warten auf Verarbeitung.", symbol: "list.bullet.rectangle", tint: .orange))
        }
        if model.ownerOpenTicketCount > 0 {
            result.append(.init(id: "tickets", title: "Offene Tickets", detail: "\(model.ownerOpenTicketCount) Anfrage(n) warten auf Bearbeitung.", symbol: "ticket.fill", tint: .blue))
        }
        if let diagnostics = model.diagnosticsV2, !diagnostics.healthy {
            let failed = diagnostics.checks.filter { !$0.ok }.count
            result.append(.init(id: "diagnostics", title: "Diagnose benötigt Aufmerksamkeit", detail: "\(failed) Check(s) sind nicht grün.", symbol: "stethoscope", tint: .orange))
        }
        result.append(contentsOf: groupedEventItems)
        return result
    }

    private var groupedEventItems: [OwnerNotificationItem] {
        let recent = Array(model.eventsV2.suffix(50))
        let groups = Dictionary(grouping: recent, by: \.type)

        return groups.compactMap { type, events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            let countText = events.count == 1 ? "1 Ereignis" : "\(events.count) Ereignisse"
            let resource = latest.resource.trimmingCharacters(in: .whitespacesAndNewlines)
            let resourceText = resource.isEmpty ? "" : " · \(resource)"
            return OwnerNotificationItem(
                id: "event-group-\(type)",
                title: eventTitle(type),
                detail: "\(countText) · Letztes \(latest.timestamp.formatted(date: .omitted, time: .shortened))\(resourceText)",
                symbol: eventSymbol(type),
                tint: type.contains("failed") ? .red : .indigo
            )
        }
        .sorted { lhs, rhs in
            let leftType = lhs.id.replacingOccurrences(of: "event-group-", with: "")
            let rightType = rhs.id.replacingOccurrences(of: "event-group-", with: "")
            let leftDate = groups[leftType]?.map(\.timestamp).max() ?? .distantPast
            let rightDate = groups[rightType]?.map(\.timestamp).max() ?? .distantPast
            return leftDate > rightDate
        }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Keine Meldungen", systemImage: "checkmark.circle", description: Text("Derzeit gibt es keine Owner-Meldungen mit Handlungsbedarf."))
            } else {
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.symbol).foregroundStyle(item.tint)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .ownerManagementBackground()
        .navigationTitle("Meldungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventTitle(_ type: String) -> String {
        type.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }

    private func eventSymbol(_ type: String) -> String {
        if type.contains("backup") { return "externaldrive.fill" }
        if type.contains("workflow") { return "point.3.connected.trianglepath.dotted" }
        if type.contains("security") { return "lock.shield.fill" }
        return "bolt.horizontal.circle.fill"
    }
}
