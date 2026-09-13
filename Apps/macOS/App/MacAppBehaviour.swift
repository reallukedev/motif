import SwiftUI
import AppKit
import ServiceManagement

/// Whether the app shows in the Dock, and whether it starts at login.
@MainActor
@Observable
final class MacAppBehaviour {
    static let showsDockIconKey = "showsDockIcon"

    /// On by default, since the window is the main way to use the app.
    var showsDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showsDockIcon, forKey: Self.showsDockIconKey)
            applyActivationPolicy()
        }
    }

    private(set) var launchAtLoginError: String?

    init() {
        showsDockIcon = UserDefaults.standard.object(forKey: Self.showsDockIconKey) as? Bool ?? true
    }

    /// `.accessory` hides the Dock icon and app menu but keeps windows usable. Applied at
    /// launch as well as on change.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginError = nil
            } catch {
                // Fails for unsigned or unnotarised builds, such as development copies.
                launchAtLoginError = error.localizedDescription
            }
        }
    }
}
