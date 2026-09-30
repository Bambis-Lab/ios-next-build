import SwiftUI

struct OwnerSystemsView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry
    let appModel: AppModel?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                IOSNextSectionHeader(
                    title: "Systeme",
                    subtitle: "Ressourcen zuerst, technische Details im Drill-down",
                    symbol: "server.rack"
                )

                if capabilities.supports(.backendStatus), let status = model.backendStatus {
                    NavigationLink {
                        OwnerBackendServiceView(status: status)
                    } label: {
                        OwnerStatusRow(
                            title: "Owner Backend",
                            detail: "Version \(status.version) · \(status.environment)",
                            symbol: "server.rack",
                            value: status.healthy ? "Online" : "Gestört",
                            tint: status.healthy ? .green : .orange
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    OwnerCapabilityUnavailableView(title: "Owner Backend")
                }

                if let appModel {
                    NavigationLink {
                        OwnerHomeAssistantView(appModel: appModel, backendSystems: model.systemStatusesV2, model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Home Assistant",
                            detail: "App-Verbindung plus Owner-Backend-Telemetrie",
                            symbol: "house.fill",
                            value: appModel.connectionState.statusText,
                            tint: appModel.connectionState == .connected ? .green : .orange
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "Home Assistant",
                        detail: "In diesem Einstieg ist kein AppModel verfügbar."
                    )
                }

                if model.v2Capabilities != nil {
                    ForEach(managedSystems) { system in
                        NavigationLink {
                            OwnerManagedSystemView(system: system, model: model)
                        } label: {
                            OwnerStatusRow(
                                title: system.title,
                                detail: system.detail ?? system.kind.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                                symbol: symbol(for: system.id),
                                value: system.ownerStateTitle,
                                tint: system.ownerStateTint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "Tailscale",
                        detail: "Owner API v2 liefert nach Verbindung Service- und Routing-Telemetrie."
                    )
                    OwnerCapabilityUnavailableView(
                        title: "Runner",
                        detail: "Owner API v2 liefert nach Konfiguration Runner-Telemetrie."
                    )
                    OwnerCapabilityUnavailableView(
                        title: "Bridge",
                        detail: "Owner API v2 liefert nach Konfiguration Bridge-Telemetrie."
                    )
                }

                if let error = model.ownerV2Error, model.v2Capabilities == nil {
                    OwnerAlertBanner(
                        title: "Owner API v2 nicht aktiv",
                        message: "Die v1-Funktionen bleiben verfügbar. \(error)",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: .secondary
                    )
                }
            }
        }
        .navigationTitle("Systeme")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshStatusV2() }
    }

    private var managedSystems: [AdminSystemStatusV2] {
        let hidden = Set(["owner-admin", "owner-runtime", "home-assistant"])
        return model.systemStatusesV2.filter { !hidden.contains($0.id) }
    }

    private func symbol(for id: String) -> String {
        switch id {
        case "supervisor": "square.stack.3d.up.fill"
        case "tailscale": "network"
        case "chat-relay": "bubble.left.and.bubble.right.fill"
        case "runner": "figure.run"
        case "bridge": "arrow.left.arrow.right"
        case "host": "desktopcomputer"
        case "hypervisor": "shippingbox.fill"
        default: "server.rack"
        }
    }
}

struct OwnerBackendServiceView: View {
    let status: AdminBackendStatus

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(
                    title: "Status",
                    detail: status.environment,
                    symbol: "checkmark.circle.fill",
                    value: status.healthy ? "Online" : "Gestört",
                    tint: status.healthy ? .green : .orange
                )
                OwnerStatusRow(title: "Version", detail: "Installierter Backend-Stand", symbol: "number.circle.fill", value: status.version)
                OwnerStatusRow(title: "Uptime", detail: "Laufzeit seit letztem Start", symbol: "clock.fill", value: status.ownerUptimeText)
                OwnerStatusRow(
                    title: "Datenbank",
                    detail: "Serverseitiger Health-Status",
                    symbol: "externaldrive.fill",
                    value: status.databaseHealthy ? "OK" : "Gestört",
                    tint: status.databaseHealthy ? .green : .red
                )
                OwnerStatusRow(title: "WebSockets", detail: "Aktive Backend-Sitzungen", symbol: "network", value: "\(status.activeWebSocketSessions)")
                OwnerStatusRow(
                    title: "Warteschlange",
                    detail: "Aktuell gemeldete Queue-Tiefe",
                    symbol: "list.bullet.rectangle",
                    value: "\(status.queueDepth)",
                    tint: status.queueDepth > 20 ? .orange : .indigo
                )
            }
        }
        .navigationTitle("Owner Backend")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OwnerManagedSystemView: View {
    let system: AdminSystemStatusV2
    let model: AdminControlModel
    @State private var pendingAction: AdminRemoteAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(
                    title: "Status",
                    detail: system.detail ?? "Vom Owner Backend gemeldet",
                    symbol: system.healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    value: system.ownerStateTitle,
                    tint: system.ownerStateTint
                )
                if let version = system.version {
                    OwnerStatusRow(title: "Version", detail: "Installierter Stand", symbol: "number.circle.fill", value: version)
                }
                ForEach(system.metrics.keys.sorted(), id: \.self) { key in
                    if let value = system.metrics[key] {
                        OwnerStatusRow(
                            title: metricTitle(key),
                            detail: "Owner-Backend-Metrik",
                            symbol: "gauge.with.dots.needle.50percent",
                            value: value.displayValue
                        )
                    }
                }
                if !system.dependencies.isEmpty {
                    OwnerStatusRow(
                        title: "Abhängigkeiten",
                        detail: system.dependencies.joined(separator: ", "),
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                }
                if !contextualActions.isEmpty {
                    IOSNextSectionHeader(title: "Aktionen", subtitle: "Nur serverseitig allowlistete Funktionen", symbol: "gearshape.2.fill")
                    ForEach(contextualActions) { action in
                        Button { pendingAction = action } label: {
                            OwnerStatusRow(
                                title: action.title,
                                detail: action.ownerImpactText,
                                symbol: action.requiresBreakGlass ? "exclamationmark.octagon.fill" : "gearshape.2.fill",
                                value: action.ownerRiskLevel.title,
                                tint: action.ownerRiskLevel.tint
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLoading)
                    }
                }
                if !system.configured {
                    OwnerAlertBanner(
                        title: "Nicht konfiguriert",
                        message: system.detail ?? "Für dieses System ist noch kein sicherer Adapter eingerichtet.",
                        symbol: "gearshape"
                    )
                }
            }
        }
        .navigationTitle(system.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerRemoteActionSheet(action: action, isExecuting: model.isLoading) { parameters in
                Task { await model.performRemoteActionV2(action, parameters: parameters) }
            }
        }
    }

    private var contextualActions: [AdminRemoteAction] {
        let category: String
        switch system.id {
        case "tailscale": category = "tailscale"
        case "chat-relay": category = "communication"
        case "host": category = "host"
        case "hypervisor": category = "hypervisor"
        case "runner": category = "runner"
        case "bridge": category = "bridge"
        default: category = system.kind
        }
        return (model.v2Capabilities?.actions ?? []).filter { $0.available && $0.category == category }
    }

    private func metricTitle(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }
}

struct OwnerHomeAssistantView: View {
    let appModel: AppModel
    var backendSystems: [AdminSystemStatusV2] = []
    let model: AdminControlModel
    @State private var pendingAction: AdminRemoteAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(
                    title: "Verbindung",
                    detail: "Bestehende Home-Assistant-Verbindung der App",
                    symbol: "network",
                    value: appModel.connectionState.statusText,
                    tint: appModel.connectionState == .connected ? .green : .orange
                )
                OwnerStatusRow(title: "Räume", detail: "Geladene App-Bereiche", symbol: "square.grid.2x2.fill", value: "\(appModel.areas.filter(\.isAppRoom).count)")
                OwnerStatusRow(title: "Geräte", detail: "Geladene Device-Registry-Einträge", symbol: "cpu.fill", value: "\(appModel.devices.count)")
                OwnerStatusRow(
                    title: "Nicht erreichbar",
                    detail: "Entities mit unknown/unavailable",
                    symbol: "exclamationmark.triangle.fill",
                    value: "\(appModel.entities.filter { !$0.isAvailable }.count)",
                    tint: appModel.entities.contains { !$0.isAvailable } ? .orange : .green
                )
                ForEach(backendSystems.filter { ["home-assistant", "supervisor", "host"].contains($0.id) }) { system in
                    NavigationLink {
                        OwnerManagedSystemView(system: system, model: model)
                    } label: {
                        OwnerStatusRow(
                            title: system.title,
                            detail: system.detail ?? "Administrative Owner-Telemetrie",
                            symbol: system.id == "supervisor" ? "square.stack.3d.up.fill" : "server.rack",
                            value: system.ownerStateTitle,
                            tint: system.ownerStateTint
                        )
                    }
                    .buttonStyle(.plain)
                }
                if backendSystems.isEmpty {
                    OwnerCapabilityUnavailableView(
                        title: "Supervisor & Add-ons",
                        detail: "Owner API v2 ergänzt nach Aktivierung die administrativen Daten."
                    )
                }

                if !model.addonsV2.isEmpty {
                    IOSNextSectionHeader(title: "Add-ons", subtitle: "Supervisor-Inventar", symbol: "square.stack.3d.up.fill")
                    ForEach(model.addonsV2) { addon in
                        NavigationLink {
                            OwnerAddonDetailView(addon: addon, model: model)
                        } label: {
                            OwnerStatusRow(
                                title: addon.name,
                                detail: addon.version ?? addon.id,
                                symbol: "shippingbox.fill",
                                value: addon.state.localizedCapitalized,
                                tint: addon.healthy ? .green : .orange
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else if let inventory = model.addonInventoryStatusV2, inventory.state != "healthy" {
                    OwnerCapabilityUnavailableView(
                        title: "Add-on-Inventar",
                        detail: inventory.state == "permission_denied" ? "Supervisor-Berechtigung fehlt für die vollständige Add-on-Liste." : (inventory.state == "not_configured" ? "Supervisor-Zugriff ist nicht konfiguriert." : "Add-on-Inventar ist derzeit nicht erreichbar.")
                    )
                }

                if !homeAssistantActions.isEmpty {
                    IOSNextSectionHeader(title: "Owner-Aktionen", subtitle: "Serverseitig allowlistet", symbol: "gearshape.2.fill")
                    ForEach(homeAssistantActions) { action in
                        Button { pendingAction = action } label: {
                            OwnerStatusRow(
                                title: action.title,
                                detail: action.ownerImpactText,
                                symbol: "gearshape.2.fill",
                                value: action.ownerRiskLevel.title,
                                tint: action.ownerRiskLevel.tint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Home Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            OwnerRemoteActionSheet(action: action, isExecuting: model.isLoading) { parameters in
                Task { await model.performRemoteActionV2(action, parameters: parameters) }
            }
        }
    }

    private var homeAssistantActions: [AdminRemoteAction] {
        (model.v2Capabilities?.actions ?? []).filter { $0.available && $0.category == "home_assistant" }
    }
}

struct OwnerAddonDetailView: View {
    let addon: AdminAddonStatusV2
    let model: AdminControlModel
    @State private var pendingAction: AdminRemoteAction?

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerStatusRow(
                    title: "Status",
                    detail: addon.id,
                    symbol: addon.healthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    value: addon.state.localizedCapitalized,
                    tint: addon.healthy ? .green : .orange
                )
                if let version = addon.version {
                    OwnerStatusRow(title: "Version", detail: "Installiert", symbol: "number.circle.fill", value: version)
                }
                if let latest = addon.versionLatest {
                    OwnerStatusRow(
                        title: "Verfügbar",
                        detail: addon.updateAvailable ? "Update vorhanden" : "Aktueller Stand",
                        symbol: "arrow.down.circle.fill",
                        value: latest,
                        tint: addon.updateAvailable ? .orange : .green
                    )
                }
                ForEach(addonActions) { action in
                    Button { pendingAction = actionForDisplay(action) } label: {
                        OwnerStatusRow(
                            title: action.title,
                            detail: action.ownerImpactText,
                            symbol: "gearshape.2.fill",
                            value: action.ownerRiskLevel.title,
                            tint: action.ownerRiskLevel.tint
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoading)
                }
            }
        }
        .navigationTitle(addon.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { displayAction in
            OwnerRemoteActionSheet(action: displayAction, isExecuting: model.isLoading) { parameters in
                var resolved = parameters
                resolved["addon_slug"] = addon.id
                guard let action = addonActions.first(where: { $0.id == displayAction.id }) else { return }
                Task { await model.performRemoteActionV2(action, parameters: resolved) }
            }
        }
    }

    private var addonActions: [AdminRemoteAction] {
        (model.v2Capabilities?.actions ?? []).filter { $0.available && $0.category == "addon" }
    }

    private func actionForDisplay(_ action: AdminRemoteAction) -> AdminRemoteAction {
        AdminRemoteAction(
            id: action.id,
            title: action.title,
            category: action.category,
            risk: action.risk,
            available: action.available,
            requiresBiometrics: action.requiresBiometrics,
            requiresConfirmation: action.requiresConfirmation,
            requiresBreakGlass: action.requiresBreakGlass,
            parameters: action.parameters?.filter { $0.id != "addon_slug" }
        )
    }
}
