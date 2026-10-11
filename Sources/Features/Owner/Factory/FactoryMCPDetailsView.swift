import SwiftUI

/// Safe, human-readable projection of the explicitly allowlisted MCP tools.
/// Raw JSON, credentials and arbitrary remote content are never rendered.
struct FactoryMCPDetailsView: View {
    let snapshot: FactorySnapshot
    @State private var search = ""

    private var filtered: [FactorySnapshotRow] {
        guard !search.isEmpty else { return snapshot.rows }
        return snapshot.rows.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.status.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Factory-Protokoll")
                        .font(.largeTitle.weight(.bold))
                    Text("Read-only MCP-Telemetrie · Stand: \(snapshot.observedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("\(snapshot.rows.count) abgefragte Quellen · \(snapshot.toolNames.count) angebotene Tools")
                        .font(.caption.weight(.medium))
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ios27ContentSurface(radius: 16)

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(filtered) { report in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(report.title).font(.headline)
                            Spacer()
                            Text(report.status)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(report.source).font(.caption2).foregroundStyle(.secondary)
                        Text(report.detail)
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(safeFields(for: report.id), id: \.0) { field in
                            LabeledContent(field.0, value: field.1)
                                .font(.caption)
                        }
                    }
                    .padding(17)
                    .ios27ContentSurface(radius: 22)
                    .accessibilityElement(children: .contain)
                }

                Text("Sichtbar sind nur ausdrücklich freigegebene Statusfelder. Tokens, Dateiinhalte, Host-Aktionen und vollständige Tool-Antworten bleiben verborgen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 38)
        }
        .searchable(text: $search, prompt: "Factory-Daten durchsuchen")
        .background(FactoryAmbientBackground(kind: .factory))
        .navigationTitle("Factory MCP")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func safeFields(for name: String) -> [(String, String)] {
        guard let report = snapshot.rawReports[name],
              let root = try? JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any] else {
            return []
        }
        let safeKeys = [
            "version", "status", "state", "records", "active", "canonical",
            "configured", "service", "name", "registered", "available",
            "uptime", "healthy"
        ]
        var out: [(String, String)] = []
        for key in safeKeys {
            guard let scalar = root[key] else { continue }
            if let value = scalar as? String {
                out.append((key.localizedCapitalized, String(value.prefix(80))))
            } else if let value = scalar as? NSNumber {
                out.append((key.localizedCapitalized, value.stringValue))
            }
        }
        return out
    }
}
