#if os(iOS)
import Foundation
import MusicKit
import Observation
import Synchronization
import MotifCore

/// Observes the system music player on iOS.
///
/// Uses `Observations` on `MusicPlayer.Queue`, which is `Observable` since 26.4. The queue's
/// `currentEntry` hasn't updated yet when the change fires, hence ``settleDelay``.
@MainActor
public final class SystemMusicPlayerSource: NowPlayingSource, @unchecked Sendable {
    /// How long to wait after a queue change before reading `currentEntry`. Found by trial.
    public static let settleDelay: Duration = .milliseconds(300)

    /// Where observations go: set by ``start()``, cleared by ``stop()``. Behind a lock
    /// because both are nonisolated and must hand back or finish a stream straight away,
    /// before the main actor gets round to the observation task.
    private nonisolated let continuation = Mutex<AsyncStream<NowPlayingObservation>.Continuation?>(nil)
    private var task: Task<Void, Never>?

    public init() {}

    public nonisolated func start() -> AsyncStream<NowPlayingObservation> {
        let (stream, continuation) = AsyncStream<NowPlayingObservation>.makeStream()
        self.continuation.withLock { current in
            current?.finish()
            current = continuation
        }
        Task { @MainActor in self.reconcile() }
        return stream
    }

    public nonisolated func stop() {
        continuation.withLock { current in
            current?.finish()
            current = nil
        }
        Task { @MainActor in self.reconcile() }
    }

    /// Starts or ends the observation task to match whether a stream is open.
    ///
    /// Reads the wanted state rather than acting on each call, so a stop and a start queued
    /// close together end up right whichever order the main actor runs them in.
    private func reconcile() {
        let wantsObserving = continuation.withLock { $0 != nil }
        if wantsObserving, task == nil {
            startObserving()
        } else if !wantsObserving, let task {
            task.cancel()
            self.task = nil
        }
    }

    private func startObserving() {
        let player = SystemMusicPlayer.shared
        task = Task { @MainActor [weak self] in
            let changes = Observations { player.queue.currentEntry?.id }
            for await _ in changes {
                if Task.isCancelled { return }
                try? await Task.sleep(for: Self.settleDelay)
                guard let self else { return }
                guard let observation = Self.observation(from: player) else { continue }
                self.continuation.withLock { $0 }?.yield(observation)
            }
        }
    }

    /// A one-shot read of what's playing, for the App Intent. On iOS the capture loop usually
    /// isn't running, so it can't wait for the next queue change.
    public static func currentObservation() -> NowPlayingObservation? {
        observation(from: SystemMusicPlayer.shared)
    }

    static func observation(from player: SystemMusicPlayer) -> NowPlayingObservation? {
        observation(
            from: player.queue.currentEntry,
            status: player.state.playbackStatus,
            playbackTime: player.playbackTime
        )
    }

    /// Builds an observation, or nil while the entry is unresolved.
    ///
    /// An entry arrives in two stages about a second apart. First the title appears with
    /// `item == nil`: at a station change it's the station name ("Apple Music 1"), otherwise
    /// the track name with no catalog id. Then `item` resolves to `.song` with the id.
    /// Capturing the first stage would save the station as a song.
    ///
    /// Takes the player's values rather than the player, so tests can supply their own.
    static func observation(
        from entry: MusicPlayer.Queue.Entry?,
        status: MusicPlayer.PlaybackStatus,
        playbackTime: TimeInterval
    ) -> NowPlayingObservation? {
        guard let entry else { return nil }

        let identifier = QueueEntryIdentifier(entry.id)
        var raw: [String: String] = [
            "entry.id": entry.id,
            "entry.title": entry.title,
            "entry.subtitle": ProbeFormat.value(entry.subtitle),
            // Not a radio signal: it's `false` for radio and albums alike.
            "entry.isTransient": String(entry.isTransient),
        ]
        if let identifier {
            raw["queueID"] = identifier.queueID
            raw["isStream"] = String(identifier.isStream)
        }

        guard case .song(let song) = entry.item else {
            // Unresolved, so nothing to capture yet. See `announcedStation(from:)`.
            return nil
        }

        // For diagnosis only: it reads `{"kind":"song"}` for radio and on-demand alike.
        // The entry id is what tells them apart.
        if let parameters = entry.item?.playParameters {
            raw["playParameters"] = ProbeFormat.json(parameters)
        }

        return NowPlayingObservation(
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            // iOS never runs a catalog search, so this is the only chance to get artwork.
            // Streams answer MusicKit's private `musicKit://` scheme, which never loads and
            // would make the artwork backfill skip the row. See ``ArtworkURL``.
            artworkURL: ArtworkURL.loadable(song.artwork?.url(width: 300, height: 300)?.absoluteString),
            catalogSongID: song.id.rawValue,
            duration: song.duration,
            playbackState: playbackState(status),
            playerPosition: playbackTime.isFinite ? playbackTime : nil,
            stationName: nil,
            observedAt: .now,
            rawFields: raw
        )
    }

    /// The station name ("Apple Music Chill"), when a queue change has just announced one.
    /// This unresolved entry title is the only source of a station name on iOS.
    static func announcedStation(from player: SystemMusicPlayer) -> String? {
        guard let entry = player.queue.currentEntry,
              entry.item == nil,
              entry.subtitle == nil,
              QueueEntryIdentifier(entry.id)?.isStream == true
        else { return nil }
        return entry.title
    }

    static func playbackState(_ status: MusicPlayer.PlaybackStatus) -> PlaybackState {
        switch status {
        case .playing: .playing
        case .paused: .paused
        default: .stopped
        }
    }
}
#endif
