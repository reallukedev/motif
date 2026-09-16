import SwiftUI
import MotifCore

struct RootView: View {
    @Bindable var model: AppModel
    @State private var summaryPath: [Route] = LaunchScene.route.map { [$0] } ?? []
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    var body: some View {
        if let store = model.store, let capture = model.capture, let playback = model.playback {
            TabView(selection: $model.selectedTab) {
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
            .opensDeepLinks(in: model)
            // A song from a widget. Summary is the tab whose stack can be pushed from here.
            // Initial too, for a link that launched the app.
            .onChange(of: model.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                model.selectedTab = .summary
                summaryPath = [route]
                model.pendingRoute = nil
            }
            .observesLibrary(model.library)
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
