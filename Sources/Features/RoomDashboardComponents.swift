import SwiftUI

struct IOS27RoomHeaderCard: View {
    let area: HomeAssistantArea
    let appModel: AppModel
    var symbol: String = "door.left.hand.open"
    var tint: Color = .blue

    private var metrics: ResourceMetrics {
        appModel.resourceMetrics(inArea: area.id)
    }

    var body: some View {
        IOS27StatusCard(
            title: "Übersicht",
            value: "\(metrics.deviceCount) Geräte",
            symbol: symbol,
            tint: tint,
            detail: "\(metrics.activeEntityCount) aktive Entitäten"
        )
    }
}

struct IOS27RoomTechnicalDetails: View {
    let area: HomeAssistantArea
    let appModel: AppModel

    private var devices: [HomeAssistantDevice] {
        appModel.devices(inArea: area.id)
    }

    var body: some View {
        if !devices.isEmpty {
            IOS27SectionHeader(
                title: "Technische Details",
                subtitle: "Geräte und Entitäten"
            )
            DisclosureGroup("Geräte (\(devices.count))") {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                        NavigationLink {
                            DeviceDetailView(device: device, appModel: appModel)
                        } label: {
                            DeviceRow(
                                device: device,
                                entityCount: appModel.entities(forDevice: device.id).count
                            )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if index != devices.indices.last {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(14)
            .ios27ContentSurface(radius: 24)
        }
    }
}

struct IOS27RoomActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(14)
            .ios27ContentSurface(radius: 20)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
    }
}
