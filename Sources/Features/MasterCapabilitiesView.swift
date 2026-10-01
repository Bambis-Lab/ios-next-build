import SwiftUI

struct MasterCapabilitiesView: View {
    @State private var runtime = IOSNextRuntime.shared

    private var governance: MasterGovernanceSnapshot {
        .sourceOnly(
            observedAt: runtime.liveOperationsModel.lastEventAt ?? runtime.runnerModel.masterRuntimeSnapshot.updatedAt
        )
    }

    var body: some View {
        List {
            Section("Master Zugriff") {
                LabeledContent("Authority", value: governance.authority)
                LabeledContent("Datenstand", value: freshnessText(governance.observedAt))
                capabilityRow(governance.readOnlyStatus)
            }

            Section("Capabilities") {
                ForEach(governance.capabilities.filter { $0.capability != .readOnly }) { item in
                    capabilityRow(item)
                }
            }

            Section("Aktionspipeline") {
                pipelineRow("Precheck", available: governance.precheckSupported)
                pipelineRow("Verify", available: governance.verifySupported)
                pipelineRow("Rollback", available: governance.rollbackSupported)
            }

            Section {
                Label("iOS Next 1.2 verwendet Master ausschließlich lesend.", systemImage: "lock.shield.fill")
                Label("Schreib- und Host-Aktionen werden in dieser Version weder geplant noch ausgeführt.", systemImage: "hand.raised.fill")
            } footer: {
                Text("Die Oberfläche ist bereits auf Plan → Precheck → Freigabe → Execute → Verify → Rollback vorbereitet. Die ausführbaren Schritte bleiben bis zu einer späteren, separat freigegebenen Version gesperrt.")
            }
        }
        .listStyle(.insetGrouped)
        .iosNextManagementBackground()
        .navigationTitle("Master Zugriff")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runtime.runnerModel.refresh()
            runtime.liveOperationsModel.refreshRuntimeConfiguration()
            runtime.liveOperationsModel.startIfNeeded()
        }
    }

    private func capabilityRow(_ item: MasterCapabilityStatus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.availability == .active ? "checkmark.shield.fill" : "lock.fill")
                .foregroundStyle(item.availability == .active ? .green : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.capability.rawValue)
                    .font(.subheadline.monospaced().weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.availability.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.availability == .active ? .green : .secondary)
        }
    }

    private func pipelineRow(_ title: String, available: Bool) -> some View {
        HStack {
            Label(title, systemImage: available ? "checkmark.circle.fill" : "circle.dashed")
            Spacer()
            Text(available ? "Verfügbar" : "Vorbereitet · gesperrt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func freshnessText(_ date: Date?) -> String {
        guard let date else { return "Noch keine Beobachtung" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "gerade eben" }
        if seconds < 60 { return "vor \(seconds)s" }
        if seconds < 3_600 { return "vor \(seconds / 60)m" }
        return "vor \(seconds / 3_600)h"
    }
}
