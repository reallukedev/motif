import BackgroundTasks
import Foundation
import MotifCore

/// Background App Refresh: iOS wakes Motif now and then, for about 30 seconds, to catch up
/// on what played while it was closed.
///
/// It can't watch the player. iOS gives no app a way to follow another app's playback in the
/// background, so songs heard meanwhile still arrive through Recently Played, dated when
/// they're found. Refreshing between launches keeps those dates closer to the truth and
/// picks songs up before they fall off the end of Apple's list.
enum BackgroundRefresh {
    /// Also listed under `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let identifier = "\(Bundle.main.bundleIdentifier ?? "Motif").refresh"

    /// The soonest to ask for. iOS decides when it actually runs, from how often the app is
    /// used and the battery, so it can be hours.
    private static let interval: TimeInterval = 15 * 60

    /// When a background refresh last finished, and why the last request was refused. Both
    /// are shown in Settings: without them there's no way to tell "iOS hasn't woken us yet"
    /// from "this has never been set up properly".
    static let lastRunKey = "backgroundRefreshLastRun"
    static let lastErrorKey = "backgroundRefreshLastError"

    private static var defaults: UserDefaults { CaptureSettings.sharedDefaults }

    static var lastRun: Date? {
        defaults.object(forKey: lastRunKey) as? Date
    }

    /// Why the last request was refused, or nil if it was accepted.
    static var lastError: String? {
        defaults.string(forKey: lastErrorKey)
    }

    /// Asks for the next refresh. A new request replaces the pending one.
    static func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(interval)
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            defaults.removeObject(forKey: lastErrorKey)
        } catch {
            // Always refused in the Simulator, and when Background App Refresh is off. Kept
            // rather than swallowed so Settings can say so instead of looking idle.
            defaults.set(error.localizedDescription, forKey: lastErrorKey)
        }
    }

    /// Recovers what played, then sends whatever is owed: playlist writes, covers, scrobbles.
    static func run(_ model: AppModel) async {
        guard !model.isDemoLaunch, let capture = model.capture else { return }
        await capture.catchUp()
        defaults.set(Date.now, forKey: lastRunKey)
        // The refresher waits a few seconds for saves to settle, and iOS may suspend the app
        // before then.
        WidgetRefresher.shared?.reloadIfChanged()
    }
}
