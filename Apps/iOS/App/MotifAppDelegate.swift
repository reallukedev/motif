import UIKit
import Intents

/// Hands Siri's "play" requests to Motif, which handles them itself rather than in an
/// extension: the player lives in the app. And finishes downloads from your servers that
/// completed while Motif wasn't running.
final class MotifAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? PlayMediaIntentHandler() : nil
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Downloads.sessionIdentifier else {
            completionHandler()
            return
        }
        // Making the downloads reconnects to the session, whose delegate calls this once the
        // finished files are in place.
        AppModel.shared.yourMusic.downloads.backgroundCompletion = completionHandler
    }
}
