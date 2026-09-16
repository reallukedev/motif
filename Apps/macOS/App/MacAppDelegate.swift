import SwiftUI
import AppKit

/// Owns what lives as long as the process, and starts it when the app finishes launching.
///
/// Startup used to hang off the main window's `.task`, which ran it again for every new
/// window (undoing a paused capture) and not at all when macOS restored no window at launch,
/// as it doesn't for an app that was quit with its window closed. Launch is the one moment
/// that happens exactly once, whatever windows there are.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let behaviour = MacAppBehaviour()
    /// Watches Music for the menu bar.
    let monitor = NowPlayingMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        behaviour.applyActivationPolicy()
        Task { await model.startCapture() }
    }
}
