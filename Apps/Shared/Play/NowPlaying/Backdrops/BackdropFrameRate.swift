import Foundation
import Observation

/// How often a moving background draws. On the Mac every frame lays out the window it's in,
/// so a background whose motion is decoration draws at 30 frames a second there; at these
/// speeds the eye can't tell. Reduce Motion's calmer movement needs fewer still, and so does
/// Low Power Mode, which keeps the motion at fewer frames.
enum BackdropFrameRate {
    static func interval(reduceMotion: Bool) -> Double {
        if reduceMotion || LowPowerMode.shared.isOn { return 1 / 20 }
        #if os(macOS)
        return 1 / 30
        #else
        return 1 / 60
        #endif
    }
}

/// Whether Low Power Mode is on, for views to read as it changes.
@Observable
final class LowPowerMode {
    static let shared = LowPowerMode()
    private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                LowPowerMode.shared.isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
