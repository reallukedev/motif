import SwiftUI
import CloudKit
import Observation
import MotifCore

/// What Settings knows about iCloud sync: the switch, the account, and what the mirror
/// reported. One per Settings screen, so the root row and the page never disagree.
@Observable
final class CloudSyncSettings {
    private let store: MotifStore
    private let monitor: CloudSyncMonitor?

    /// The switch. Read once when the store opens, so a change applies next launch.
    var wantsSync = CloudSync.isEnabled {
        didSet { CloudSync.isEnabled = wantsSync }
    }

    private var account: CloudSyncStatus.Account?
    private var accountError: String?

    init(store: MotifStore, monitor: CloudSyncMonitor?) {
        self.store = store
        self.monitor = monitor
    }

    var status: CloudSyncStatus {
        CloudSyncStatus.resolve(
            isConfigured: CloudSync.isConfigured,
            wantsSync: wantsSync,
            isRunning: store.backing.isSynced,
            startFailure: store.syncFailureReason,
            account: account,
            accountError: accountError,
            failure: monitor?.failure,
            lastSynced: monitor?.lastSynced
        )
    }

    /// Asks CloudKit about the account. Never prompts; it only reads.
    func refresh() async {
        guard let identifier = CloudSync.containerIdentifier else { return }
        do {
            let status = try await CKContainer(identifier: identifier).accountStatus()
            accountError = nil
            account = switch status {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            case .temporarilyUnavailable: .temporarilyUnavailable
            case .couldNotDetermine: .unknown
            @unknown default: .unknown
            }
        } catch {
            accountError = error.localizedDescription
        }
    }
}

/// iCloud sync: the switch, where it stands, and what it carries. An iPhone page, and the
/// Mac's iCloud pane.
struct CloudSyncPage: View {
    @Bindable var sync: CloudSyncSettings

    var body: some View {
        // Relative times ("synced 5 minutes ago") keep up while the page is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let status = sync.status
            Form {
                SettingsHero(
                    "iCloud",
                    subtitle: status.tone.apply(to: Text(status.line(now: context.date))),
                    systemImage: "icloud.fill",
                    tint: .blue
                ) {
                    heroControl(status)
                }

                #if os(iOS)
                if status != .unavailable {
                    Section {
                        Toggle("Sync with iCloud", isOn: $sync.wantsSync)
                    } footer: {
                        Text(sync.wantsSync
                            ? "Changes sync on their own, so there’s nothing to press."
                            : "Your history stays on this iPhone only.")
                            .contentTransition(.opacity)
                    }
                }
                #endif

                if let reason = status.reason {
                    Section {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("What iCloud Said")
                    }
                }

                if let fix = fix(for: status) {
                    Section {
                    } footer: {
                        Text(fix)
                    }
                }

                Section {
                    Text("Your listening history, stations and sessions, your settings, and the songs you’ve removed.")
                } header: {
                    Text("What Syncs")
                } footer: {
                    Text("It all goes to your private iCloud database. Songs are kept as Apple Music catalog identifiers, never audio.")
                }
            }
            .animation(.default, value: status)
        }
        .task { await sync.refresh() }
        #if os(macOS)
        .settingsPane()
        #else
        .settingsPage("iCloud")
        .refreshable { await sync.refresh() }
        #endif
    }

    /// The pane's switch on the Mac. On iPhone it's a row of its own, as in Settings.
    @ViewBuilder
    private func heroControl(_ status: CloudSyncStatus) -> some View {
        #if os(macOS)
        if status != .unavailable {
            Toggle("Sync with iCloud", isOn: $sync.wantsSync)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        #endif
    }

    /// Where to go when the fix is in the system's settings, not here.
    private func fix(for status: CloudSyncStatus) -> LocalizedStringKey? {
        switch status {
        case .notSignedIn:
            #if os(iOS)
            "Sign in at the top of the Settings app, then come back to Motif."
            #else
            "Sign in under System Settings ▸ Apple Account, then come back to Motif."
            #endif
        case .restricted:
            "Screen Time or a device profile doesn’t allow iCloud for Motif."
        default:
            nil
        }
    }
}
