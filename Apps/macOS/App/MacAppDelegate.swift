import SwiftUI
import AppKit
import Observation

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

    /// Held while capture is running. See ``trackCaptureActivity()``.
    private var captureActivity: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        behaviour.applyActivationPolicy()
        trackCaptureActivity()
        Task { await model.startCapture() }
    }

    /// Declares the work the app is doing while capture is running, so that the system
    /// doesn't quietly kill it as it sits in the menu bar.
    ///
    /// An app with no window open counts as non-interactive, and macOS reclaims those first:
    /// on a nearly full disk, `deleted` asks RunningBoard to terminate the app so it can
    /// purge the container's caches (exit reason 0xBADDD15C, CacheDeleteAppContainerCaches).
    /// Nothing crashes and no report is written, so it reads as the app quitting at random
    /// hours or days after launch, with everything played from then on unrecorded. An
    /// activity raises the app's termination resistance, and rules out the sudden and
    /// automatic termination AppKit would otherwise allow.
    ///
    /// Not `.userInitiated`, which also holds off idle sleep: capture has no reason to keep
    /// the Mac awake, and stops when it sleeps anyway. Dropped while capture is paused, when
    /// being terminated costs the user nothing.
    private func trackCaptureActivity() {
        guard let capture = model.capture else { return }
        withObservationTracking {
            switch (capture.isRunning, captureActivity) {
            case (true, nil):
                captureActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.background, .suddenTerminationDisabled, .automaticTerminationDisabled],
                    reason: "Recording listening history"
                )
            case (false, let activity?):
                ProcessInfo.processInfo.endActivity(activity)
                captureActivity = nil
            default:
                break
            }
        } onChange: { [weak self] in
            // Fires just before the change lands, so the new state is read back on the main
            // actor, where tracking is also set up again for the change after it.
            Task { @MainActor in self?.trackCaptureActivity() }
        }
    }
}
