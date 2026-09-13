import SwiftUI
import SwiftData
import MotifCore
import MotifMusic

/// Which stations Motif captures from. Edits the exclusion set ``CapturePolicy`` reads.
///
/// Stations are picked from a list rather than typed, because an exclusion only works if
/// it matches the name the platform reports exactly.
struct StationExclusionsSection: View {
    @Environment(AppModel.self) private var model
    /// Most recently heard first.
    @Query(sort: \Station.lastSeenAt, order: .reverse) private var stations: [Station]

    /// A local copy of the stored set, saved on change. `CaptureSettings` isn't observable,
    /// so a `Toggle` bound straight to it would snap back after each tap.
    @State private var excluded = CaptureSettings().excludedStations

    /// Stations Apple Music says the user has played. Motif only learns a station's name on
    /// macOS if it saw the tune-in, so its own list is usually shorter.
    @State private var fromAppleMusic: [String] = []

    private let settings = CaptureSettings()

    var body: some View {
        Section {
            if names.isEmpty {
                Text("Stations show up here once you've listened to one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.self) { name in
                    Toggle(name, isOn: capturing(name))
                }
            }
        } header: {
            Text("Stations")
        } footer: {
            Text("""
                Turn a station off to stop keeping what it plays. Songs already kept from it \
                stay in your history.
                """)
        }
        .onChange(of: excluded) { _, names in
            settings.excludedStations = names
        }
        .task {
            guard !model.isShowingSampleData else { return }
            fromAppleMusic = (try? await CatalogLookup().recentStationNames()) ?? []
        }
    }

    /// Motif's stations in the order it heard them, then Apple Music's, then any excluded
    /// name neither list mentions, so every excluded station keeps a switch to turn back on.
    private var names: [String] {
        let known = stations.map(\.name)
        var seen = Set(known)
        let fromApple = fromAppleMusic.filter { seen.insert($0).inserted }
        return known + fromApple + excluded.subtracting(seen).sorted()
    }

    /// On means capturing, so the switch doesn't read as a double negative.
    private func capturing(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(name) },
            // Local state only; `onChange(of: excluded)` saves it.
            set: { isCapturing in
                if isCapturing {
                    excluded.remove(name)
                } else {
                    excluded.insert(name)
                }
            }
        )
    }
}
