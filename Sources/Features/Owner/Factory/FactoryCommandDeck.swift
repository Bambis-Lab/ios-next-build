import SwiftUI

/// Custom Factory topology — intentionally quiet, no perpetual GPU animation.
struct FactoryCommandDeck: View {
    let factoryConnected: Bool
    let ownerConnected: Bool
    let runnerConnected: Bool
    let reportedSources: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TOPOLOGY / FACTORY")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text("Control Plane")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Text(factoryConnected ? "\(reportedSources) Quellen" : "Nicht verbunden")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let center = CGPoint(x: width / 2, y: height / 2)
                let radius = min(width * 0.32, 112.0)
                let points: [CGPoint] = [
                    CGPoint(x: center.x - radius, y: center.y - radius * 0.56),
                    CGPoint(x: center.x + radius, y: center.y - radius * 0.56),
                    CGPoint(x: center.x - radius, y: center.y + radius * 0.58),
                    CGPoint(x: center.x + radius, y: center.y + radius * 0.58)
                ]
                ZStack {
                    Canvas { context, _ in
                        for point in points {
                            var path = Path()
                            path.move(to: center)
                            path.addLine(to: point)
                            context.stroke(path, with: .color(.indigo.opacity(0.29)), lineWidth: 1.3)
                        }
                        var ring = Path()
                        ring.addEllipse(in: CGRect(x: center.x - radius * 1.21,
                                                   y: center.y - radius * 1.21,
                                                   width: radius * 2.42,
                                                   height: radius * 2.42))
                        context.stroke(ring, with: .color(.indigo.opacity(0.09)), lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                    Circle()
                        .fill(Color.indigo.opacity(reduceTransparency ? 0.09 : 0.16))
                        .frame(width: 106, height: 106)
                        .overlay(Circle().stroke(.indigo.opacity(0.25), lineWidth: 1))
                        .overlay {
                            VStack(spacing: 3) {
                                Image(systemName: "network")
                                    .font(.system(size: 27, weight: .medium))
                                Text("FACTORY")
                                    .font(.caption2.weight(.heavy))
                                    .tracking(1)
                            }
                            .foregroundStyle(.indigo)
                        }
                        .position(center)

                    node("MCP", icon: "point.3.connected.trianglepath.dotted",
                         active: factoryConnected).position(points[0])
                    node("OWNER", icon: "person.badge.key.fill",
                         active: ownerConnected).position(points[1])
                    node("RUNNER", icon: "server.rack",
                         active: runnerConnected).position(points[2])
                    node("RUNTIME", icon: "waveform.path.ecg",
                         active: factoryConnected).position(points[3])
                }
            }
            .frame(height: 214)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Factory-Topologie. MCP \(factoryConnected ? "verbunden" : "nicht verbunden"), Owner \(ownerConnected ? "online" : "nicht verfügbar"), Runner \(runnerConnected ? "online" : "nicht verfügbar").")

            HStack(spacing: 9) {
                Circle()
                    .fill(factoryConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(factoryConnected ? "Factory-Daten werden live abgefragt" :
                        "Live-Daten nur nach autorisierter Verbindung")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.indigo.opacity(0.13), lineWidth: 0.8)
        }
        .accessibilityIdentifier("factory-topology")
    }

    private func node(_ label: String, icon: String, active: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Color.green : Color.secondary)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.primary)
        }
        .frame(width: 76, height: 68)
        .background(Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((active ? Color.green : Color.secondary).opacity(0.22), lineWidth: 0.8)
        }
    }
}
