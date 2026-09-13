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
            // Flush before iOS suspends the app, which can happen inside the settle delay.
            if phase == .background, !model.isDemoLaunch { WidgetRefresher.shared?.reloadIfChanged() }
        }
    }
}
