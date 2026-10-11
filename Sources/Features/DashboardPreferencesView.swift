import SwiftUI

struct DashboardPreferencesView: View {
    let options: [DashboardPreferenceOption]
    let store: DashboardPreferencesStore

    private var orderedOptions: [DashboardPreferenceOption] {
        options.sorted {
            let left = store.rank(of: $0.id)
            let right = store.rank(of: $1.id)
            return left == right ? $0.id < $1.id : left < right
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Anzeigen") {
                    ForEach(orderedOptions) { option in
                        Toggle(isOn: Binding(
                            get: { store.isVisible(option.id) },
                            set: { store.toggleVisibility(option.id, visible: $0) }
                        )) {
                            Label(option.title, systemImage: option.symbol)
                        }
                    }
                } footer: {
                    Text("Einstellungen werden lokal für das ausgewählte App-Profil gespeichert.")
                }

                Section("Reihenfolge") {
                    ForEach(Array(orderedOptions.enumerated()), id: \.element.id) { index, option in
                        HStack(spacing: 12) {
                            Label(option.title, systemImage: option.symbol)
                            Spacer()
                            Button {
                                store.move(option.id, by: -1, availableIDs: orderedOptions.map(\.id))
                            } label: {
                                Image(systemName: "arrow.up")
                                    .frame(width: 40, height: 40)
                            }
                            .disabled(index == 0)
                            .accessibilityLabel("\(option.title) nach oben")

                            Button {
                                store.move(option.id, by: 1, availableIDs: orderedOptions.map(\.id))
                            } label: {
                                Image(systemName: "arrow.down")
                                    .frame(width: 40, height: 40)
                            }
                            .disabled(index == orderedOptions.count - 1)
                            .accessibilityLabel("\(option.title) nach unten")
                        }
                    }
                }

                Section {
                    Button("Zurücksetzen", role: .destructive) { store.reset() }
                }
            }
            .navigationTitle("Startseite anpassen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
