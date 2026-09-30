import Foundation
import Observation
import MotifCore

/// Brings the connected account's Last.fm history into Motif, and says how that's going.
///
/// Owned by the app model rather than Settings, so a long first import keeps going when
/// Settings closes.
@MainActor
@Observable
final class LastFMHistorySync {
    enum Phase: Equatable {
        case idle
        case importing(LastFMHistoryImporter.Report)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// What's been imported so far, for the account that's connected now.
    private(set) var progress: LastFMHistory.Progress?

    private let store: MotifStore
    private let settings: CaptureSettings
    @ObservationIgnored private var task: Task<Void, Never>?

    init(store: MotifStore, settings: CaptureSettings = CaptureSettings()) {
        self.store = store
        self.settings = settings
        readProgress()
    }

    var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    /// Whether this account's history has been imported at least once.
    var hasImported: Bool { progress?.lastFinished != nil }

    /// Where importing stands, in the terms Settings words it in.
    var state: LastFMHistoryWords.State {
        switch phase {
        case .idle: LastFMHistoryWords.State(progress: progress, running: nil, failure: nil)
        case .importing(let report): LastFMHistoryWords.State(progress: progress, running: report, failure: nil)
        case .failed(let message): LastFMHistoryWords.State(progress: progress, running: nil, failure: message)
        }
    }

    /// Starts a run, or stops the one that's going.
    func startOrStop() {
        isImporting ? stop() : start()
    }

    /// Reads everything Motif doesn't have yet: the whole history the first time, then only
    /// what's new. Does nothing while a run is going.
    func start() {
        guard task == nil else { return }
        guard let session = LastFMSessionStore.current else {
            phase = .failed(ScrobbleService.describe(LastFMError.notConnected))
            return
        }
        guard let client = LastFMClient.configured() else {
            phase = .failed(ScrobbleService.describe(LastFMError.notConfigured))
            return
        }
        phase = .importing(LastFMHistoryImporter.Report())
        let importer = LastFMHistoryImporter(client: client, session: session, store: store, settings: settings)
        task = Task {
            do {
                try await importer.run { [weak self] report in
                    self?.phase = .importing(report)
                    self?.readProgress()
                }
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(ScrobbleService.describe(error))
            }
            readProgress()
            task = nil
        }
    }

    /// Stops a run. What it has read so far stays, and the next run picks up from there.
    func stop() {
        task?.cancel()
    }

    /// Forgets how far imports got, for when the account is disconnected. The plays stay.
    func forgetProgress() {
        task?.cancel()
        settings.lastFMHistoryProgress = nil
        phase = .idle
        progress = nil
    }

    /// Picks up a change of account.
    func readProgress() {
        progress = LastFMSessionStore.current.map { settings.lastFMHistory(for: $0.username) }
    }
}
