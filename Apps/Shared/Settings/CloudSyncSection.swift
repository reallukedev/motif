import SwiftUI
import CloudKit
import MotifCore

/// Shows whether iCloud sync is actually working. CloudKit failures (an ungranted container,
/// a signed-out account, iCloud Drive off) otherwise look the same as having nothing new
/// to sync.
struct CloudSyncSection: View {
    let store: MotifStore
    /// What the mirror has reported since launch. An open, synced store can still have every
    /// change refused.
    let monitor: CloudSyncMonitor?

    @State private var accountStatus: CKAccountStatus?
    @State private var accountError: String?
    @State private var isEnabled = CloudSync.isEnabled

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    CloudSync.isEnabled = newValue
                }

            LabeledContent("Status") {
                Label(state.summary, systemImage: state.symbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(state.tint)
            }

            if let detail = state.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("""
                Your listening history, stations and sessions are mirrored to your private \
                iCloud database, so they appear on your other devices and survive losing \
                this one. Your settings and the songs you've removed follow along, so a \
                change made on one device holds everywhere. Songs are stored as catalog \
                identifiers, not audio. Turning this off takes effect the next time Motif \
                starts.
                """)
        }
        .task { await readAccountStatus() }
    }

    private var state: SyncState {
        // Account problems come before the store's state, since they're usually the cause.
        if !CloudSync.isEnabled {
            return SyncState(
                summary: "Off",
                symbol: "icloud.slash",
                tint: .secondary,
                detail: isEnabled ? "Starts syncing the next time Motif opens." : nil
            )
        }
        if let accountError {
            return SyncState(
                summary: "Unavailable", symbol: "exclamationmark.icloud",
                tint: .orange, detail: accountError
            )
        }
        switch accountStatus {
        case .noAccount:
            return SyncState(
                summary: "Not signed in", symbol: "exclamationmark.icloud", tint: .orange,
                detail: "Sign in to iCloud in System Settings to back up your listening history."
            )
        case .restricted:
            return SyncState(
                summary: "Restricted", symbol: "exclamationmark.icloud", tint: .orange,
                detail: "iCloud is restricted on this device, so Motif cannot sync."
            )
        case .temporarilyUnavailable:
            return SyncState(
                summary: "Temporarily unavailable", symbol: "arrow.trianglehead.2.clockwise",
                tint: .secondary, detail: "iCloud is not reachable right now. Motif will try again."
            )
        case .available where store.backing.isSynced:
            if let failure = monitor?.failure {
                return SyncState(
                    summary: "Not syncing", symbol: "exclamationmark.icloud", tint: .orange,
                    detail: failure.detail
                )
            }
            return SyncState(summary: "On", symbol: "checkmark.icloud", tint: .green, detail: nil)
        case .available:
            return SyncState(
                summary: "Not running", symbol: "exclamationmark.icloud", tint: .orange,
                // A working account but an unsynced store means the container was refused.
                // The user can't fix that, so just say what happened.
                detail: store.syncFailureReason ?? "The iCloud container could not be opened."
            )
        case .couldNotDetermine, .none:
            return SyncState(
                summary: "Checking…", symbol: "arrow.trianglehead.2.clockwise",
                tint: .secondary, detail: nil
            )
        @unknown default:
            return SyncState(
                summary: "Unknown", symbol: "questionmark.circle", tint: .secondary, detail: nil
            )
        }
    }

    private func readAccountStatus() async {
        guard let identifier = CloudSync.containerIdentifier else {
            accountError = "This build has no iCloud container configured."
            return
        }
        do {
            accountStatus = try await CKContainer(identifier: identifier).accountStatus()
        } catch {
            accountError = error.localizedDescription
        }
    }

    private struct SyncState {
        let summary: String
        let symbol: String
        let tint: Color
        let detail: String?
    }
}

private extension CloudSyncMonitor.Failure {
    /// Which way the failure stops things, then iCloud's own words for why.
    var detail: String {
        let consequence = switch activity {
        case .setup: "iCloud sync couldn't start, so this device isn't sending or receiving history."
        case .export: "iCloud isn't accepting this device's history, so other devices won't see it."
        case .import: "This device couldn't fetch history from iCloud."
        }
        return "\(consequence) \(message)"
    }
}
