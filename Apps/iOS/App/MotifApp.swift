import SwiftUI
import MotifCore

/// iOS has no headless mode, so `@main` lives here. On the Mac it's `Main.swift`.
@main
struct MotifApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            guard !model.isDemoLaunch else { return }
            switch phase {
            case .active:
                // iOS suspends the app within about thirty seconds of it going away, so
                // nothing has been pulled from iCloud since. Catch up before the user looks.
                model.syncOnForeground()
            case .background:
                // Flush before iOS suspends the app, which can happen inside the settle delay.
                WidgetRefresher.shared?.reloadIfChanged()
                Task { await BackgroundRefresh.schedule() }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [model] in
            // Ask for the next one first, so a refresh that runs out of time still has one.
            await BackgroundRefresh.schedule()
            await BackgroundRefresh.run(model)
        }
    }
}
