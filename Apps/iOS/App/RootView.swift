import SwiftUI
import MotifCore

enum AppTab: String, Hashable {
    case summary, history, charts, search

    init?(launchName: String?) {
        guard let launchName else { return nil }
        self.init(rawValue: launchName)
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @State private var tab: AppTab = AppTab(launchName: LaunchScene.tab) ?? .summary
    @State private var summaryPath: [Route] = LaunchScene.route.map { [$0] } ?? []
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    var body: some View {
        if let store = model.activeStore, let capture = model.capture, let playback = model.playback {
            TabView(selection: $tab) {
                Tab("Summary", systemImage: "chart.bar.xaxis", value: .summary) {
                    NavigationStack(path: $summaryPath) { SummaryScreen().motifDestinations() }
                }
                Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                    NavigationStack { HistoryScreen().motifDestinations() }
                }
                Tab("Charts", systemImage: "list.number", value: .charts) {
                    NavigationStack { ChartsScreen().motifDestinations() }
                }
                Tab(value: .search, role: .search) {
                    NavigationStack { SearchScreen().motifDestinations() }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .observesLibrary(model.library)
            // Swapping between sample and real data swaps the container; start fresh.
            .id(model.isShowingSampleData)
            .modelContainer(store.container)
            .environment(model)
            .environment(capture)
            .environment(playback)
            .task { await model.startCapture() }
            .onChange(of: scenePhase) { _, phase in
                // iOS only sees music while Motif is open, so pick up what was missed each
                // time it comes back. Launch is covered by `startCapture`.
                if phase == .background {
                    wasInBackground = true
                } else if phase == .active, wasInBackground, !model.isDemoLaunch {
                    wasInBackground = false
                    Task { await capture.catchUp() }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Motif Can't Open Your History", systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.startupError ?? "The database couldn't be opened.")
            }
        }
    }
}
