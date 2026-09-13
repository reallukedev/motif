import SwiftUI
import MotifCore

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                LastFMSection()
                HistorySourcesSection()
                ListeningRulesSection()
                Section {
                    NavigationLink {
                        Form {
                            RadioPlaylistSection()
                            StationExclusionsSection()
                        }
                        .navigationTitle("Radio")
                    } label: {
                        Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                WidgetSection()
                if let store = model.store, !model.isDemoLaunch {
                    CloudSyncSection(store: store)
                }
                AboutSection()
                #if DEBUG
                Section("Developer") {
                    NavigationLink("Probe") { ProbeScreen(model: ProbeModel()) }
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
