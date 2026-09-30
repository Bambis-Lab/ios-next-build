import SwiftUI

struct OwnerConnectionIndicator: View {
    let model: AdminControlModel

    var body: some View {
        Label(model.ownerConnectionPhase.title, systemImage: model.ownerConnectionPhase.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(model.ownerConnectionPhase.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(model.ownerConnectionPhase.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("Owner Backend: \(model.ownerConnectionPhase.title)")
    }
}

struct OwnerMetricView: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .indigo

    var body: some View {
        IOSNextMetricCard(title: title, value: value, symbol: symbol, tint: tint)
    }
}

struct OwnerStatusRow: View {
    let title: String
    let detail: String
    let symbol: String
    var value: String? = nil
    var tint: Color = .indigo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(15)
        .iosNextSurface()
        .accessibilityElement(children: .combine)
    }
}

struct OwnerCapabilityUnavailableView: View {
    let title: String
    var detail: String = "Noch nicht vom Owner Backend bereitgestellt."

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .iosNextSurface()
    }
}

struct OwnerAlertBanner: View {
    let title: String
    let message: String
    let symbol: String
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct OwnerOperationProgressView: View {
    let model: AdminControlModel

    var body: some View {
        if model.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Owner-Vorgang läuft …").font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .iosNextSurface()
        } else if let receipt = model.lastReceipt {
            OwnerStatusRow(
                title: "Letzter Vorgang",
                detail: "Request \(receipt.requestID)",
                symbol: "checkmark.circle.fill",
                value: receipt.state.replacingOccurrences(of: "_", with: " ").localizedCapitalized,
                tint: .green
            )
        }
    }
}

struct OwnerActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: AdminAction
    let isExecuting: Bool
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Auswirkung") {
                    Text(action.ownerImpactText)
                }
                Section("Voraussetzungen") {
                    ForEach(action.ownerPreconditions, id: \.self) { prerequisite in
                        Label(prerequisite, systemImage: "checkmark.circle")
                    }
                }
                Section("Risiko") {
                    Label(action.ownerRiskLevel.title, systemImage: riskSymbol)
                        .foregroundStyle(action.ownerRiskLevel.tint)
                }
                Section {
                    Button(action.requiresFreshBiometrics ? "Mit Face ID bestätigen" : "Aktion ausführen") {
                        onConfirm()
                        dismiss()
                    }
                    .disabled(isExecuting)
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var riskSymbol: String {
        switch action.ownerRiskLevel {
        case .safe: "checkmark.shield.fill"
        case .operational: "gearshape.2.fill"
        case .sensitive: "exclamationmark.shield.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

struct OwnerRemoteActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: AdminRemoteAction
    let isExecuting: Bool
    let onConfirm: ([String: String]) -> Void
    @State private var parameterValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section("Auswirkung") {
                    Text(action.ownerImpactText)
                }
                if let parameters = action.parameters, !parameters.isEmpty {
                    Section("Parameter") {
                        ForEach(parameters) { parameter in
                            TextField(
                                parameter.title,
                                text: Binding(
                                    get: { parameterValues[parameter.id, default: ""] },
                                    set: { parameterValues[parameter.id] = $0 }
                                )
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                    }
                }
                Section("Sicherheitsanforderungen") {
                    if action.requiresBiometrics {
                        Label("Frische Face-ID-Bestätigung", systemImage: "faceid")
                    }
                    if action.requiresBreakGlass {
                        Label("Aktive Break-Glass-Sitzung", systemImage: "exclamationmark.octagon.fill")
                    }
                    if !action.requiresBiometrics && !action.requiresBreakGlass {
                        Label("Aktive Owner-Sitzung", systemImage: "checkmark.shield.fill")
                    }
                }
                Section("Risiko") {
                    Label(action.ownerRiskLevel.title, systemImage: riskSymbol)
                        .foregroundStyle(action.ownerRiskLevel.tint)
                }
                Section {
                    Button(action.requiresBiometrics ? "Mit Face ID bestätigen" : "Aktion ausführen") {
                        onConfirm(parameterValues)
                        dismiss()
                    }
                    .disabled(isExecuting || !action.available || !parametersComplete)
                }
            }
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var parametersComplete: Bool {
        (action.parameters ?? []).allSatisfy { parameter in
            !parameter.required || !(parameterValues[parameter.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var riskSymbol: String {
        switch action.ownerRiskLevel {
        case .safe: "checkmark.shield.fill"
        case .operational: "gearshape.2.fill"
        case .sensitive: "exclamationmark.shield.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
