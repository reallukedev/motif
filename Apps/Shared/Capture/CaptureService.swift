import Foundation
import Observation
import MotifCore
import MotifMusic

/// Owns the one `NowPlayingSource` and feeds it to the coordinator.
///
/// Keep this a single instance. On macOS a second observer means duplicate notifications
/// and duplicate captures.
@MainActor
@Observable
public final class CaptureService {
    public private(set) var isRunning = false
    public private(set) var lastCapture: CaptureSnapshot?
    public private(set) var lastDecision: CaptureDecision?
    public private(set) var currentStation: String?

    /// Whether music is audible, as of the last poll. The status item reads this because
    /// `NowPlayingMonitor` only polls while the popup is open.
    ///
    /// Nil until the first poll returns, so launch doesn't briefly blank the status item.
    public private(set) var isSomethingPlaying: Bool?

    /// What is audible right now, captured or not. A song plays from its first second but
    /// only becomes ``lastCapture`` once it passes the minimum listening time.
    public private(set) var nowPlaying: NowPlaying?
    /// The session in progress, if any. Nil once silence closes it.
    public private(set) var openSession: Session?

    private let store: MotifStore
    private let settings: CaptureSettings
    private let scrobbler: ScrobbleService
    private let coordinator: CaptureCoordinator
    private let source: any NowPlayingSource
    private var pump: Task<Void, Never>?
    private var housekeeping: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var recheck: Task<Void, Never>?
    private var artworkLookup: Task<Void, Never>?
    /// The song artwork was last looked up for, so a failed lookup is not retried every poll.
    private var artworkLookupKey: String?
    /// What that lookup found. Kept separately because `nowPlaying` is rebuilt from each
    /// poll, and the observation carries no artwork.
    private var artworkLookupResult: String?

    /// How often to ask Music.app what is playing. Each poll is one Apple event.
    private static let pollInterval: TimeInterval = 10

    /// How long a station has to be stopped before the day's captures are played back.
    /// Long enough to skip gaps between tracks, short enough that the listener is likely
    /// still there to hear it.
    private static let autoPlaybackDelay: TimeInterval = 120

    /// Called when a station has stopped and the day still has unplayed captures. Set by
    /// the app, which owns the player.
    public var autoPlayback: (@MainActor () async -> Void)?

    /// When the music stopped, or nil while something is playing.
    private var silentSince: Date?
    /// One play-back per listening session. Cleared when a station starts again.
    private var hasAutoPlayedThisSession = false

    public init(store: MotifStore, settings: CaptureSettings = CaptureSettings()) {
        self.store = store
        self.settings = settings
        self.scrobbler = ScrobbleService(store: store, settings: settings)

        #if os(macOS)
        // The macOS payload has no catalog id, so it needs a resolver.
        self.source = PlayerInfoSource()
        let resolver: (any CatalogResolving)? = CatalogLookup()
        #else
        self.source = SystemMusicPlayerSource()
        // iOS reads the id straight off the queue entry; no search is needed.
        let resolver: (any CatalogResolving)? = nil
        #endif

        self.coordinator = CaptureCoordinator(
            store: store,
            settings: settings,
            playlistWriter: MusicKitPlaylistWriter(),
            catalogResolver: resolver
        )
    }

    /// Retries whatever is outstanding: unresolved ids, missing artwork, failed playlist
    /// writes, unsent scrobbles. Called at launch.
    public func catchUp() async {
        closeStaleSessions()
        mergeSyncedDuplicates()
        await importRecentlyPlayed()
        await coordinator.drainPendingWrites()
        await scrobbler.drain()
    }

    /// Picks up listening that happened while Motif wasn't running, from Apple's
    /// recently-played list. See ``HistoryImport`` for what an import can and can't record.
    @discardableResult
    public func importRecentlyPlayed() async -> Int {
        guard settings.importsRecentlyPlayed else { return 0 }
        guard let songs = try? await RecentlyPlayedSource().recentlyPlayed(limit: 30) else { return 0 }
        let imported = (try? store.importPlayedSongs(songs)) ?? 0
        if imported > 0, lastCapture == nil {
            lastCapture = (try? store.context.fetch(MotifStore.allCaptures(limit: 1)))?
                .first?
                .snapshot
        }
        return imported
    }

    /// Folds together the duplicate rows iCloud sync produces. Runs at launch and on the
    /// housekeeping timer, since synced rows can arrive at any time.
    ///
    /// Not gated on sync being on: duplicates outlive sync being turned off. The merge is
    /// idempotent and cheap.
    private func mergeSyncedDuplicates() {
        _ = try? store.mergeDuplicateStations()
        _ = try? store.mergeDuplicateCaptures()
        _ = try? store.clearUnloadableArtwork()
    }

    /// Ends sessions that have gone quiet. Silence produces no observations, so this runs on
    /// a timer as well as at launch.
    private func closeStaleSessions() {
        _ = try? store.closeStaleSessions()
        openSession = try? store.currentOpenSession()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        // Seed from the store so the menu bar has something to show before the next capture.
        if lastCapture == nil {
            lastCapture = (try? store.context.fetch(MotifStore.allCaptures(limit: 1)))?
                .first?
                .snapshot
        }
        source.start()
        // Well inside the fifteen minute silence timeout, and the query is cheap.
        housekeeping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await MainActor.run {
                    self?.closeStaleSessions()
                    self?.mergeSyncedDuplicates()
                }
                // Catches scrobbles queued before a Last.fm account was connected mid-session.
                await self?.scrobbler.drain()
            }
        }
        pump = Task { [source, coordinator] in
            for await observation in source.observations {
                if Task.isCancelled { return }
                let decision = await coordinator.handle(observation)
                await MainActor.run { self.record(decision, observation: observation) }
                if case .capture = decision { await self.scrobbler.drain() }
            }
        }
        #if os(macOS)
        startPolling()
        #endif
    }

    #if os(macOS)
    /// Polls Music.app on a timer as well as listening for notifications.
    ///
    /// A radio station changing track doesn't reliably post `com.apple.Music.playerInfo`;
    /// in one eleven minute session only two songs were captured. Scripting reports the
    /// live track correctly, so the poll is the fallback and the notification stays for
    /// speed. Polling the same song again is harmless: it has the same dedupe key and is
    /// rejected before the store.
    private func startPolling() {
        poll = Task { [weak self] in
            var isFirst = true
            while !Task.isCancelled {
                // Poll straight away on launch.
                if isFirst {
                    isFirst = false
                } else {
                    try? await Task.sleep(for: .seconds(Self.pollInterval))
                }
                guard let self, self.isRunning else { return }

                // Off the main actor: an Apple event blocks its thread until Music answers
                // or times out.
                let observation = await ScriptingQueue.run { PlayerInfoSource.currentObservation() }

                guard let observation, observation.playbackState == .playing else {
                    self.isSomethingPlaying = false
                    self.nowPlaying = nil
                    if self.silentSince == nil { self.silentSince = .now }
                    await self.considerAutoPlayback()
                    continue
                }

                self.isSomethingPlaying = true
                self.silentSince = nil
                self.hasAutoPlayedThisSession = false

                let decision = await self.coordinator.handle(observation)
                self.record(decision, observation: observation)
                if case .capture = decision { await self.scrobbler.drain() }
            }
        }
    }
    /// Plays the day's captures back once the station has stopped, so radio listens count
    /// as plays in Apple Music.
    ///
    /// Only fires when someone is at the machine (unknown presence counts as absent), once
    /// per listening session, and when nothing else is playing (the caller checks that).
    /// Playing into an empty room would log plays nobody heard.
    private func considerAutoPlayback() async {
        guard settings.autoPlayBack, !hasAutoPlayedThisSession else { return }
        guard let silentSince,
              Date.now.timeIntervalSince(silentSince) >= Self.autoPlaybackDelay
        else { return }
        guard UserPresence.isPresent() else { return }

        let unplayed = (try? store.playBackQueue()) ?? []
        guard !unplayed.isEmpty else { return }

        hasAutoPlayedThisSession = true
        await autoPlayback?()
    }
    #endif

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        // Nothing is being watched, so don't claim to know what's playing.
        isSomethingPlaying = nil
        nowPlaying = nil
        pump?.cancel()
        pump = nil
        housekeeping?.cancel()
        housekeeping = nil
        poll?.cancel()
        poll = nil
        recheck?.cancel()
        recheck = nil
        artworkLookup?.cancel()
        artworkLookup = nil
        artworkLookupKey = nil
        artworkLookupResult = nil
        source.stop()
    }

    /// Checks again once a song has played long enough to count.
    ///
    /// iOS only observes on a queue change, so without this a song waiting out its minimum
    /// listening time would never be captured.
    private func scheduleRecheck(after remaining: TimeInterval) {
        recheck?.cancel()
        recheck = Task { [weak self] in
            // Slightly past due, so rounding can't make it fire early and reschedule.
            try? await Task.sleep(for: .seconds(max(0.5, remaining) + 0.5))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            guard let observation = await self.currentObservation(),
                  observation.playbackState == .playing
            else { return }
            let decision = await self.coordinator.handle(observation)
            self.record(decision, observation: observation)
        }
    }

    /// - Parameter observation: what was playing when this was decided, so the display
    ///   follows the music rather than the writes.
    private func record(_ decision: CaptureDecision, observation: NowPlayingObservation? = nil) {
        lastDecision = decision
        updateNowPlaying(observation)
        if case .ignore(.tooShort(let playedFor, let needs)) = decision {
            scheduleRecheck(after: needs - playedFor)
        }
        currentStation = coordinator.currentStationName
        openSession = try? store.currentOpenSession()

        if case .capture = decision {
            lastCapture = (try? store.context.fetch(MotifStore.allCaptures(limit: 1)))?
                .first?
                .snapshot
            return
        }

        guard let observation, observation.playbackState == .playing,
              observation.isIdentifiable
        else { return }

        // Skipping back to an already captured song should still update `lastCapture`.
        let descriptor = MotifStore.mostRecentCapture(
            title: observation.title,
            artistName: observation.artistName
        )
        let existing = try? store.context.fetch(descriptor).first
        if let existing { lastCapture = existing.snapshot }
    }

    /// Updates ``nowPlaying`` from every playing observation, captured or not. Artwork comes
    /// from an earlier capture of the same song, or a catalog lookup, since the macOS
    /// notification carries none.
    private func updateNowPlaying(_ observation: NowPlayingObservation?) {
        guard let observation, observation.playbackState == .playing,
              observation.isIdentifiable, observation.announcedStationName == nil
        else {
            nowPlaying = nil
            return
        }
        let existing = try? store.context.fetch(MotifStore.mostRecentCapture(
            title: observation.title,
            artistName: observation.artistName
        )).first
        let key = Self.songKey(for: observation)
        nowPlaying = NowPlaying(
            title: observation.title,
            artistName: observation.artistName,
            albumTitle: observation.albumTitle ?? existing?.albumTitle,
            artworkURL: observation.artworkURL
                ?? existing?.artworkURL
                ?? (artworkLookupKey == key ? artworkLookupResult : nil)
        )
        if nowPlaying?.artworkURL == nil { lookUpArtwork(for: observation) }
    }

    /// Fetches a cover for a song that has no capture to borrow one from. Runs once per
    /// song, and a failure is remembered too so it isn't retried every poll.
    private func lookUpArtwork(for observation: NowPlayingObservation) {
        #if os(macOS)
        let key = Self.songKey(for: observation)
        guard artworkLookupKey != key else { return }
        artworkLookupKey = key
        artworkLookupResult = nil
        artworkLookup?.cancel()

        let query = CatalogQuery(
            title: observation.title,
            artistName: observation.artistName,
            duration: observation.duration,
            albumTitle: observation.albumTitle
        )
        artworkLookup = Task { [weak self] in
            guard let match = try? await CatalogLookup().resolve(query),
                  let artwork = match.artworkURL,
                  !Task.isCancelled
            else { return }
            guard let self, self.nowPlaying?.title == observation.title else { return }
            // So the next poll's rebuild of `nowPlaying` keeps it.
            self.artworkLookupResult = artwork
            self.nowPlaying = NowPlaying(
                title: observation.title,
                artistName: observation.artistName,
                albumTitle: self.nowPlaying?.albumTitle ?? match.albumTitle,
                artworkURL: artwork
            )
        }
        #endif
    }

    /// The single-capture path used by the App Intent, Action Button and Back Tap. Works
    /// without the capture loop running, which on iOS is most of the time.
    @discardableResult
    public func captureCurrentSong() async -> CaptureDecision {
        guard let observation = await currentObservation() else {
            return .ignore(.unidentifiable)
        }
        // The user asked for this song, so skip the minimum listening time.
        let decision = await coordinator.handle(observation, force: true)
        record(decision, observation: observation)
        return decision
    }

    static func songKey(for observation: NowPlayingObservation) -> String {
        "\(observation.title)\u{1F}\(observation.artistName)"
    }

    private func currentObservation() async -> NowPlayingObservation? {
        #if os(iOS)
        return SystemMusicPlayerSource.currentObservation()
        #else
        return PlayerInfoSource.currentObservation()
        #endif
    }
}
