import SwiftUI

struct OwnerSecurityView: View {
    let model: AdminControlModel
    let capabilities: OwnerCapabilityRegistry

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                IOSNextSectionHeader(
                    title: "Sicherheit",
                    subtitle: "Keine Secret-Werte in der Oberfläche",
                    symbol: "lock.shield.fill"
                )

                if let security = model.securityV2 {
                    OwnerStatusRow(
                        title: "Owner Security",
                        detail: security.deviceBindingAvailable ? "Gerätebindung verfügbar" : "Nur Basis-Authentifizierung",
                        symbol: security.deviceBindingAvailable ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                        value: security.controlEnabled ? "Control" : "Observe",
                        tint: security.freeShellAvailable ? .red : .green
                    )
                    OwnerStatusRow(
                        title: "Gerätebindung",
                        detail: deviceBindingDetail,
                        symbol: deviceBindingSymbol,
                        value: deviceBindingTitle,
                        tint: deviceBindingTint
                    )
                    OwnerStatusRow(
                        title: "Geräte-Sitzungen",
                        detail: "Kurzlebige gerätegebundene Owner-Sitzungen",
                        symbol: "iphone.gen3",
                        value: "\(security.activeSessions) aktiv",
                        tint: .indigo
                    )
                    OwnerStatusRow(
                        title: "Break-Glass",
                        detail: "Critical-Zugriff mit zusätzlicher Challenge und Zeitlimit",
                        symbol: "exclamationmark.octagon.fill",
                        value: model.hasActiveBreakGlassSession ? "Aktiv" : "Gesperrt",
                        tint: model.hasActiveBreakGlassSession ? .red : .green
                    )
                }

                if capabilities.supports(.audit) {
                    NavigationLink {
                        OwnerAuditView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Audit",
                            detail: "Serverseitig protokollierte Owner-Aktionen",
                            symbol: "list.bullet.clipboard.fill",
                            value: "\(model.auditEvents.count) Ereignisse",
                            tint: .green
                        )
                    }
                    .buttonStyle(.plain)
                }

                if capabilities.supports(.credentials) {
                    NavigationLink {
                        OwnerCredentialsView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Credentials",
                            detail: "Nur Name, Zweck, Scope und Risiko — niemals Secret-Werte",
                            symbol: "key.fill",
                            value: "\(model.credentialsV2.count)"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    OwnerCapabilityUnavailableView(
                        title: "Credentials",
                        detail: "Metadaten werden erst mit Owner API v2 bereitgestellt."
                    )
                }

                if capabilities.supports(.users) {
                    NavigationLink {
                        OwnerUsersView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Benutzer",
                            detail: "Owner- und Member-Rollen aus dem Backend",
                            symbol: "person.2.fill",
                            value: "\(model.usersV2.count)"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    OwnerCapabilityUnavailableView(title: "Benutzer")
                }

                if capabilities.supports(.devices) {
                    NavigationLink {
                        OwnerDevicesSessionsView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Geräte & Sessions",
                            detail: "Gerätebindung, Fingerprints und kurze Sitzungen",
                            symbol: "iphone.gen3",
                            value: "\(model.devicesV2.count) Geräte"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    OwnerCapabilityUnavailableView(title: "Geräte & Sessions")
                }

                if model.v2Capabilities?.capabilities.contains("break_glass") == true {
                    NavigationLink {
                        OwnerAdvancedAccessView(model: model)
                    } label: {
                        OwnerStatusRow(
                            title: "Erweiterter Zugriff",
                            detail: "Break-Glass nur für kritische Recovery-Aktionen",
                            symbol: "exclamationmark.octagon.fill",
                            value: model.hasActiveBreakGlassSession ? "Aktiv" : "Gesperrt",
                            tint: model.hasActiveBreakGlassSession ? .red : .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Sicherheit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshStatusV2() }
    }
    private var deviceBindingTitle: String {
        switch model.deviceBindingPhase {
        case .unavailable: return "Nicht verfügbar"
        case .enrolling: return "Kopplung läuft"
        case .verifying: return "Wird bestätigt"
        case .trusted: return "Vertrauenswürdig"
        case .failed: return "Kopplung fehlgeschlagen"
        }
    }

    private var deviceBindingDetail: String {
        switch model.deviceBindingPhase {
        case .unavailable: return "Gerätebindung ist auf diesem Backend nicht verfügbar."
        case .enrolling: return "Dieses Gerät wird beim Owner Backend registriert."
        case .verifying: return "Die signierte Geräte-Challenge wird geprüft."
        case let .trusted(expiresAt): return "Geräte-Session aktiv bis \(expiresAt.formatted(date: .omitted, time: .shortened))."
        case let .failed(message): return message
        }
    }

    private var deviceBindingSymbol: String {
        switch model.deviceBindingPhase {
        case .trusted: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.shield.fill"
        case .enrolling, .verifying: return "arrow.triangle.2.circlepath"
        case .unavailable: return "shield.slash.fill"
        }
    }

    private var deviceBindingTint: Color {
        switch model.deviceBindingPhase {
        case .trusted: return .green
        case .failed: return .orange
        case .enrolling, .verifying: return .indigo
        case .unavailable: return .secondary
        }
    }

}

struct OwnerAuditView: View {
    let model: AdminControlModel

    var body: some View {
        List {
            if model.auditEvents.isEmpty {
                ContentUnavailableView(
                    "Keine Audit-Ereignisse",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Geladene Owner-Aktionen erscheinen hier.")
                )
            } else {
                ForEach(model.auditEvents) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.action.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(resultTitle(event.result))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(resultTint(event.result))
                        }
                        Text(event.actor).font(.caption).foregroundStyle(.secondary)
                        Text(event.timestamp, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .ownerManagementBackground()
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultTitle(_ result: String) -> String {
        switch result.lowercased() {
        case "success", "ok": "Erfolgreich"
        case "failed", "failure", "error": "Fehlgeschlagen"
        default: result.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }

    private func resultTint(_ result: String) -> Color {
        ["success", "ok"].contains(result.lowercased()) ? .green : .orange
    }
}

private struct OwnerCredentialsView: View {
    let model: AdminControlModel

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerAlertBanner(
                    title: "Metadaten nur",
                    message: "Credential-Werte werden vom Backend nicht an die App übertragen.",
                    symbol: "lock.shield.fill",
                    tint: .green
                )
                ForEach(model.credentialsV2) { credential in
                    OwnerStatusRow(
                        title: credential.name,
                        detail: "\(credential.purpose) · \(credential.scope)",
                        symbol: "key.fill",
                        value: credential.configured ? credential.risk.localizedCapitalized : "Nicht gesetzt",
                        tint: credential.configured ? riskTint(credential.risk) : .secondary
                    )
                }
            }
        }
        .navigationTitle("Credentials")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func riskTint(_ risk: String) -> Color {
        switch risk {
        case "high": .orange
        case "critical": .red
        default: .indigo
        }
    }
}

private struct OwnerUsersView: View {
    let model: AdminControlModel

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                ForEach(model.usersV2) { user in
                    OwnerStatusRow(
                        title: user.displayName,
                        detail: user.id,
                        symbol: user.role == "owner" ? "person.badge.key.fill" : "person.fill",
                        value: user.role.localizedCapitalized,
                        tint: user.role == "owner" ? .indigo : .secondary
                    )
                }
            }
        }
        .navigationTitle("Benutzer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OwnerDevicesSessionsView: View {
    let model: AdminControlModel

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.pageSpacing) {
                IOSNextSectionHeader(title: "Vertrauensgeräte", subtitle: "Nur Public-Key-Fingerprints", symbol: "iphone.gen3")
                if model.devicesV2.isEmpty {
                    OwnerCapabilityUnavailableView(title: "Noch kein Gerät registriert")
                } else {
                    ForEach(model.devicesV2) { device in
                        OwnerStatusRow(
                            title: device.id,
                            detail: String(device.publicKeyFingerprint.prefix(16)) + "…",
                            symbol: "iphone.gen3",
                            value: device.trusted ? "Trusted" : "Gesperrt",
                            tint: device.trusted ? .green : .red
                        )
                    }
                }

                IOSNextSectionHeader(title: "Aktive Sessions", subtitle: "Serverseitig zeitlich begrenzt", symbol: "clock.badge.checkmark")
                if model.sessionsV2.isEmpty {
                    OwnerStatusRow(title: "Keine aktive Session", detail: "Beim nächsten sensiblen Vorgang wird eine neue Geräte-Session aufgebaut.", symbol: "lock.fill", value: "0")
                } else {
                    ForEach(model.sessionsV2) { session in
                        OwnerStatusRow(
                            title: session.deviceID,
                            detail: "Ablauf: \(session.expiresAt.formatted(date: .omitted, time: .shortened))",
                            symbol: "checkmark.shield.fill",
                            value: "Aktiv",
                            tint: .green
                        )
                    }
                }
            }
        }
        .navigationTitle("Geräte & Sessions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OwnerAdvancedAccessView: View {
    let model: AdminControlModel
    @State private var reason = ""

    var body: some View {
        OwnerPage {
            VStack(alignment: .leading, spacing: IOSNextLayout.sectionSpacing) {
                OwnerAlertBanner(
                    title: "Break-Glass",
                    message: "Nur für kritische Recovery. Face ID, Geräte-Challenge und ein serverseitiges 5-Minuten-Zeitfenster sind erforderlich.",
                    symbol: "exclamationmark.octagon.fill",
                    tint: .red
                )
                OwnerStatusRow(
                    title: "Status",
                    detail: model.breakGlassExpiresAt.map { "Ablauf \($0.formatted(date: .omitted, time: .shortened))" } ?? "Kein aktiver kritischer Zugriff",
                    symbol: model.hasActiveBreakGlassSession ? "lock.open.fill" : "lock.fill",
                    value: model.hasActiveBreakGlassSession ? "Aktiv" : "Gesperrt",
                    tint: model.hasActiveBreakGlassSession ? .red : .green
                )
                TextField("Grund für Recovery", text: $reason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Break-Glass für 5 Minuten anfordern", systemImage: "faceid") {
                    Task { await model.openBreakGlass(reason: reason) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || model.isLoading)
                OwnerStatusRow(
                    title: "Freie Shell",
                    detail: "Absichtlich nicht Bestandteil von Owner Control",
                    symbol: "terminal.fill",
                    value: "Nicht verfügbar",
                    tint: .green
                )
            }
        }
        .navigationTitle("Erweiterter Zugriff")
        .navigationBarTitleDisplayMode(.inline)
    }
}
