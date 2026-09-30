import Foundation
import MusicKit
import Observation
import Synchronization
import MotifCore

/// What Motif's own player is playing from, set by the app as it starts something.
///
/// The player knows whether it queued a station, so its captures don't have to be guessed
/// at. The capture source reads this; the app's player writes it.
@MainActor
public enum MotifPlayerContext {
    /// The station playing, by name, or nil for anything played on demand.
    public static var stationName: String?
    /// Whether the queue is a station. Kept apart from the name, which a station might lack.
    public static var isStation = false

    public static func playingStation(named name: String?) {
        isStation = true
        stationName = name
        startUsing()
    }

    public static func playingOnDemand() {
        isStation = false
        stationName = nil
        startUsing()
    }

    /// Whether Motif's Apple Music player is in use this launch, and so worth reading.
    ///
    /// Always on iPhone, where Play is Motif's own. On the Mac it waits for the first song
    /// Motif plays: reaching `ApplicationMusicPlayer.shared` at all can make Motif the Mac's
    /// Now Playing app, and take the media keys from Music for someone who only ever plays
    /// music there.
    public private(set) static var isInUse: Bool = {
        #if os(iOS)
        true
        #else
        false
        #endif
    }()

    /// Sources waiting for the player to come into use.
    private static var waiting: [@MainActor () -> Void] = []

    private static func startUsing() {
        guard !isInUse else { return }
        isInUse = true
        let ready = waiting
        waiting = []
        ready.forEach { $0() }
    }

    /// Runs `ready` once the player is in use: now, or when Motif first plays.
    public static func whenInUse(_ ready: @escaping @MainActor () -> Void) {
        if isInUse { ready() } else { waiting.append(ready) }
    }

    /// Whether one of Motif's own players is making sound: the Apple Music one or the one
    /// for your own music.
    ///
    /// On the Mac nothing stops Music.app playing at the same time, so capture listens to
    /// Music.app only while this is false, and the app can use it to decide when to pause
    /// Music.app.
    public static var isPlaying: Bool {
        ApplicationMusicPlayerSource.isPlaying || PushedNowPlayingSource.yourMusic.isPlaying
    }
}

/// Observes Motif's own Apple Music player, the one the Play tab uses.
///
/// Unlike the system player on iOS, this one keeps the app running while it plays (the iPhone
/// app declares background audio), so every song it plays is seen as it starts, with or
/// without the app on screen. And since Motif queued the music itself, each observation states
/// whether it came from a station rather than leaving it to ``RadioHeuristic``.
@MainActor
public final class ApplicationMusicPlayerSource: NowPlayingSource, @unchecked Sendable {
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

    /// Starts or ends the observation task to match whether a stream is open. Reads the
    /// wanted state, so a quick stop and start end up right in either order.
    private func reconcile() {
        let wantsObserving = continuation.withLock { $0 != nil }
        if wantsObserving, task == nil {
            guard MotifPlayerContext.isInUse else {
                MotifPlayerContext.whenInUse { [weak self] in self?.reconcile() }
                return
            }
            startObserving()
        } else if !wantsObserving, let task {
            task.cancel()
            self.task = nil
        }
    }

    private func startObserving() {
        let player = ApplicationMusicPlayer.shared
        task = Task { @MainActor [weak self] in
            // The status as well as the entry: resuming a paused song is worth a look, since
            // it may not have played long enough to count before the pause.
            let changes = Observations { ChangeKey(entryID: player.queue.currentEntry?.id, status: player.state.playbackStatus) }
            for await _ in changes {
                if Task.isCancelled { return }
                try? await Task.sleep(for: MusicPlayerReading.settleDelay)
                guard let self else { return }
                guard let observation = Self.currentObservation() else { continue }
                self.continuation.withLock { $0 }?.yield(observation)
            }
        }
    }

    private struct ChangeKey: Equatable {
        let entryID: String?
        let status: MusicPlayer.PlaybackStatus
    }

    /// A one-shot read of what Motif's player has on, or nil when it has nothing.
    public static func currentObservation() -> NowPlayingObservation? {
        guard MotifPlayerContext.isInUse else { return nil }
        let player = ApplicationMusicPlayer.shared
        return observation(
            from: player.queue.currentEntry,
            status: player.state.playbackStatus,
            playbackTime: player.playbackTime,
            isStation: MotifPlayerContext.isStation,
            stationName: MotifPlayerContext.stationName
        )
    }

    /// Whether Motif's player is the one making sound.
    public static var isPlaying: Bool {
        MotifPlayerContext.isInUse && ApplicationMusicPlayer.shared.state.playbackStatus == .playing
    }

    /// The shared reading of the entry, plus what only this player knows.
    static func observation(
        from entry: MusicPlayer.Queue.Entry?,
        status: MusicPlayer.PlaybackStatus,
        playbackTime: TimeInterval,
        isStation: Bool,
        stationName: String?
    ) -> NowPlayingObservation? {
        guard var observation = MusicPlayerReading.observation(
            from: entry,
            status: status,
            playbackTime: playbackTime
        ) else { return nil }
        observation.isStation = isStation
        if isStation { observation.stationName = stationName }
        observation.rawFields["player"] = "application"
        return observation
    }
}
