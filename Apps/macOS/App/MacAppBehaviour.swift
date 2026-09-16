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

    /// The login item's status as last read. Kept here, rather than read from
    /// `SMAppService` in a view, so Settings redraws when it changes.
    private(set) var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status

    init() {
        showsDockIcon = UserDefaults.standard.object(forKey: Self.showsDockIconKey) as? Bool ?? true
    }

    /// `.accessory` hides the Dock icon and app menu but keeps windows usable. Applied at
    /// launch as well as on change.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)
    }

    /// Whether Motif is set to open at login. Waiting for approval in System Settings counts:
    /// the choice has been made, and showing the switch off would invite a second attempt.
    var launchesAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    /// Registered, but the user still has to allow it under Login Items.
    var launchAtLoginNeedsApproval: Bool {
        loginItemStatus == .requiresApproval
    }

    /// Reads the status again without registering anything. The user can change it in
    /// System Settings at any time.
    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    /// Registers or unregisters the login item. On failure the status stays as it was and
    /// ``launchAtLoginError`` says why.
    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // Fails for unsigned or unnotarised builds, such as development copies.
            launchAtLoginError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }
}
