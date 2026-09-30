import SwiftUI

enum LiveHACardType: String, CaseIterable {
    case sections = "sections"
    case grid = "grid"
    case conditional = "conditional"
    case templateChip = "template"
    case entityChip = "entity"
    case mushroomTitle = "custom:mushroom-title-card"
    case mushroomChips = "custom:mushroom-chips-card"
    case mushroomTemplate = "custom:mushroom-template-card"
    case navbar = "custom:navbar-card"
    case battery = "custom:battery-state-card"
    case light = "custom:ios-light-card"
    case media = "custom:ios-media-player"
}

struct LiveHACardTestModeView: View {
    private let page: Int

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        page = Self.page(from: arguments)
    }

    var body: some View {
        NavigationStack {
            IOSNextPage {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    switch page {
                    case 1: batteryAndLightPage
                    case 2: mediaAndNavbarPage
                    default: structureAndMushroomPage
                    }
                }
            }
            .navigationTitle("Live-HA Kartentest")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("live-ha-card-test-mode")
        .background {
            VisualAcceptanceReadyProbe(
                markerBaseName: "iosnext-live-card-ready-\(page)",
                accessibilityIdentifier: "visual-ready-live-card-page-\(page)",
                payload: "page=\(page)"
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Testmodus · Seite \(page + 1)/3")
                .font(.title2.bold())
            Text("12/12 Kartentypen aus Zuhause, Timo, Mika, Juli und Gabi")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .iosNextSurface()
    }

    private var structureAndMushroomPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            testLabel(.sections)
            VStack(alignment: .leading, spacing: 14) {
                MushroomTitleMirror(title: "Zuhause", subtitle: "Health · System")
                    .padding(18)
                    .iosNextSurface()
                    .accessibilityIdentifier(id(.mushroomTitle))

                testLabel(.grid)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MushroomTemplateMirror(
                        title: "Nico-Zimmer",
                        subtitle: "Medien & Licht",
                        symbol: "bed.double.fill"
                    )
                    .accessibilityIdentifier(id(.mushroomTemplate))
                    MushroomTemplateMirror(
                        title: "System",
                        subtitle: "Netzwerk · Backup",
                        symbol: "server.rack"
                    )
                }

                MushroomChipsMirror()
                    .accessibilityIdentifier(id(.mushroomChips))
                Text("Template-Chip")
                    .accessibilityIdentifier(id(.templateChip))
                    .hidden()
                Text("Entity-Chip")
                    .accessibilityIdentifier(id(.entityChip))
                    .hidden()

                ConditionalMirror()
                    .accessibilityIdentifier(id(.conditional))
            }
        }
        .accessibilityIdentifier(id(.sections))
    }

    private var batteryAndLightPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            BatteryStateMirror()
                .accessibilityIdentifier(id(.battery))
            IOSLightMirror()
                .accessibilityIdentifier(id(.light))
        }
    }

    private var mediaAndNavbarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            IOSMediaMirror()
                .accessibilityIdentifier(id(.media))
            NavbarMirror()
                .accessibilityIdentifier(id(.navbar))
        }
    }

    private func testLabel(_ type: LiveHACardType) -> some View {
        Text(type.rawValue)
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(id(type))
    }

    private func id(_ type: LiveHACardType) -> String {
        "live-card-" + type.rawValue
    }

    static func page(from arguments: [String]) -> Int {
        guard let argument = arguments.first(where: { $0.hasPrefix("--live-card-page=") }),
              let value = Int(argument.split(separator: "=").last ?? ""),
              (0...2).contains(value)
        else { return 0 }
        return value
    }
}

private struct MushroomTitleMirror: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MushroomChipsMirror: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Online", symbol: "network", tint: .green)
                chip("Pool 27°", symbol: "water.waves", tint: .cyan)
                chip("Mäher 84%", symbol: "battery.75percent", tint: .green)
                chip("Nico", symbol: "person.fill", tint: .blue)
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct MushroomTemplateMirror: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ConditionalMirror: View {
    @State private var active = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conditional Card").font(.headline)
                    Text(active ? "Bedingung erfüllt" : "Bedingung nicht erfüllt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Aktiv", isOn: $active).labelsHidden()
            }
            if active {
                MushroomTemplateMirror(
                    title: "Licht Master",
                    subtitle: "Geräte an",
                    symbol: "power"
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(IOSNextMotion.state, value: active)
    }
}

private struct BatteryStateMirror: View {
    private let devices = [
        ("Nico iPhone", 0.83, false),
        ("iPad Pro", 0.61, true),
        ("Gabi Pixel", 0.34, false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Battery State").font(.title3.bold())
            ForEach(devices, id: \.0) { device in
                HStack(spacing: 12) {
                    Image(systemName: device.2 ? "battery.100percent.bolt" : batterySymbol(device.1))
                        .font(.title3)
                        .foregroundStyle(device.2 ? .cyan : tint(device.1))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(device.0).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(device.1 * 100))%").font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: device.1)
                            .tint(device.2 ? .cyan : tint(device.1))
                    }
                }
            }
        }
        .padding(18)
        .iosNextSurface()
    }

    private func tint(_ level: Double) -> Color {
        level < 0.2 ? .red : (level < 0.5 ? .orange : .green)
    }

    private func batterySymbol(_ level: Double) -> String {
        level < 0.25 ? "battery.25percent" : (level < 0.75 ? "battery.50percent" : "battery.100percent")
    }
}

private struct IOSLightMirror: View {
    @State private var isOn = true
    @State private var brightness = 0.72

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOn ? Color.yellow.opacity(0.22) : Color.secondary.opacity(0.10))
                    Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                        .font(.title2)
                        .foregroundStyle(isOn ? .yellow : .secondary)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TV Rechts").font(.headline)
                    Text(isOn ? "Ein · \(Int(brightness * 100))%" : "Aus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isOn.toggle()
                } label: {
                    Image(systemName: "power")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            }
            Slider(value: $brightness, in: 0...1)
                .disabled(!isOn)
                .accessibilityLabel("Helligkeit")
        }
        .padding(18)
        .iosNextSurface()
    }
}

private struct IOSMediaMirror: View {
    @State private var playing = true
    @State private var position = 0.38
    @State private var volume = 0.34

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.purple.opacity(0.16))
                    .overlay {
                        Image(systemName: "play.tv.fill")
                            .font(.title)
                            .foregroundStyle(.purple)
                    }
                    .frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple TV").font(.headline)
                    Text("Abendmix · Apple Music")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
            }
            Slider(value: $position)
                .accessibilityLabel("Wiedergabeposition")
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $volume)
                    .accessibilityLabel("Lautstärke")
                Image(systemName: "speaker.wave.3.fill")
            }
            .foregroundStyle(.secondary)
            Text("Receiver: Denon AVR")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(18)
        .iosNextSurface()
    }
}

private struct NavbarMirror: View {
    @State private var selection = 0
    private let items = [
        ("house.fill", "Haus"),
        ("lightbulb.fill", "Licht"),
        ("play.tv.fill", "Medien"),
        ("gearshape.fill", "System")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    withAnimation(IOSNextMotion.state) {
                        selection = index
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.0)
                            .font(.body.weight(.semibold))
                        Text(item.1)
                            .font(.caption2.weight(selection == index ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == index ? Color.accentColor : Color.secondary)
                    .padding(.vertical, 10)
                    .background(
                        selection == index ? Color.accentColor.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .iosNextFunctionalGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
