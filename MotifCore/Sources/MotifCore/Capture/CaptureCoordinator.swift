import Foundation
import SwiftData

/// The capture loop: observations in, rows and playlist writes out.
///
/// Deciding and inserting happen in one synchronous step, before any `await`, so two
/// observations of the same song (macOS polls every 10 seconds) can't both pass the dedupe
/// check. The slow work (catalog lookup, playlist write) happens afterwards, from the saved row.
@MainActor
public final class CaptureCoordinator {
    private let store: MotifStore
    private let settings: CaptureSettings
    private let playlistWriter: any PlaylistWriter
    /// Catalog ids (macOS, where the notification has none), artwork, and the station's
    /// name when Motif starts mid-station. Nil in tests that don't need it.
    private let catalogResolver: (any CatalogResolving)?
    private let sessionPolicy: SessionPolicy

    /// The most recent decision, for the UI and the probe to show.
    public private(set) var lastDecision: CaptureDecision?
    /// Station name learned from the last announcement, applied to subsequent captures.
    public private(set) var currentStationName: String?
    /// Whether we've already asked Apple which station is on. It's a network call, so once
    /// per station.
    private var hasAskedForStationName = false

    /// Songs in the playlist as of the last count, kept so the cap doesn't cost a request on
    /// every drain. Counted afresh when it's unknown or ``countIsStaleAfter`` has passed;
    /// incremented in between as songs go in.
    private var knownTrackCount: Int?
    private var countedAt: Date?

    /// How long a count stands for. Long enough that a listening session costs one or two
    /// counts, short enough that trimming the playlist in Apple Music frees it up soon after.
    private static let countIsStaleAfter: TimeInterval = 10 * 60

    /// True when the playlist was at its limit on the last drain, so captures are being kept
    /// without being written. Read by the probe and the tests.
    public private(set) var playlistIsFull = false

    public init(
        store: MotifStore,
        settings: CaptureSettings = CaptureSettings(),
        playlistWriter: any PlaylistWriter,
        catalogResolver: (any CatalogResolving)? = nil,
        sessionPolicy: SessionPolicy = .default
    ) {
        self.store = store
        self.settings = settings
        self.playlistWriter = playlistWriter
        self.catalogResolver = catalogResolver
        self.sessionPolicy = sessionPolicy
    }

    // MARK: - Ingest

    /// When the current song was first seen, for the minimum listening time.
    private var pendingKey: String?
    private var pendingSince: Date?

    /// Handles one observation. Returns the decision so callers can log it.
    ///
    /// - Parameter force: skip the minimum listening time. Used by the App Intent and the
    ///   Action Button.
    @discardableResult
    public func handle(
        _ observation: NowPlayingObservation,
        now: Date = .now,
        force: Bool = false
    ) async -> CaptureDecision {
        // Station announcements aren't captured, but they're where the station name comes from.
        if let station = observation.announcedStationName {
            currentStationName = station
            hasAskedForStationName = true
        } else if currentStationName == nil, !hasAskedForStationName {
            // The app started mid-station, so there was no announcement. Ask Apple.
            hasAskedForStationName = true
            currentStationName = try? await catalogResolver?.mostRecentStationName()
        }

        var observation = observation
        if observation.stationName == nil { observation.stationName = currentStationName }

        let policy = CapturePolicy(
            dedupe: settings.dedupePolicy,
            excludedStations: settings.excludedStations,
            forceCapture: settings.forceCapture,
            capturesOnDemand: settings.capturesOnDemand
        )

        // Must stay synchronous: no `await` between the dedupe check and the insert.
        let decision = decideAndInsert(observation, policy: policy, now: now, force: force)
        lastDecision = decision

        // Drain on every observation, not just new captures, so a failed write is retried
        // within 10 seconds instead of waiting for the next song. Cheap when nothing is owed.
        await drainPendingWrites()
        return decision
    }

    /// The transaction. Reads the dedupe state and writes the row without yielding.
    private func decideAndInsert(
        _ observation: NowPlayingObservation,
        policy: CapturePolicy,
        now: Date,
        force: Bool = false
    ) -> CaptureDecision {
        let songKey = observation.catalogSongID ?? Self.metadataKey(for: observation)
        let lastSeen = try? store.lastCaptureDate(songKey: songKey)
        let decision = policy.decide(observation, lastSeen: lastSeen, now: now)

        guard case .capture(let capturable) = decision else { return decision }

        // After the policy, which is pure: this needs state kept across observations.
        if let waiting = timeStillOwed(songKey: songKey, now: now, force: force) {
            return .ignore(waiting)
        }

        // Only radio belongs to a session. On-demand plays mustn't extend one.
        let session = capturable.kind == .radio
            ? try? store.openSession(stationName: capturable.stationName, policy: sessionPolicy, now: now)
            : nil
        _ = try? store.insertCapture(
            songKey: songKey,
            catalogSongID: capturable.catalogSongID,
            observation: capturable.observation,
            kind: capturable.kind,
            session: session,
            now: now
        )
        return decision
    }

    /// Nil once the song has played long enough, otherwise how much is left.
    ///
    /// The clock starts when a song is first seen and resets when a different one arrives.
    private func timeStillOwed(songKey: String, now: Date, force: Bool) -> CaptureDecision.Reason? {
        let minimum = settings.minimumListenSeconds
        guard !force, minimum > 0 else { return nil }

        if pendingKey != songKey {
            pendingKey = songKey
            pendingSince = now
        }
        let playedFor = now.timeIntervalSince(pendingSince ?? now)
        guard playedFor < minimum else { return nil }
        return .tooShort(playedFor: playedFor, needs: minimum)
    }

    /// Identity for a track with no catalog ID yet (macOS, before the search runs).
    static func metadataKey(for observation: NowPlayingObservation) -> String {
        "\(observation.title)\u{1F}\(observation.artistName)".lowercased()
    }

    // MARK: - Resolution and playlist writes

    /// The drain in progress, which later callers wait on rather than starting their own.
    ///
    /// Launch, every observation, the Mac's poll and the housekeeping timer all drain, and a
    /// drain spends most of its time waiting on Apple with the rows it fetched. Two at once
    /// both wrote the same songs, so the playlist got them twice.
    private var runningDrain: Task<Void, Never>?
    /// Set when someone asked for a drain while one was running, so a capture made after the
    /// running drain fetched its rows still gets written without waiting for the next song.
    private var wantsAnotherDrain = false

    /// Leaves the Apple Music API alone for a while after writes fail for reasons that aren't
    /// any one song's fault.
    private(set) var writeBackoff = RetryBackoff()
    /// The clock, replaceable so tests can step past the backoff.
    var now: () -> Date = { .now }

    /// How long to leave a song the catalog had no cover for before asking about it again.
    /// Apple does add artwork to old releases, just not often.
    static let artworkMissRetryAfter: TimeInterval = 7 * 24 * 60 * 60
    /// The most songs remembered as having no cover, so the list, which goes into the query,
    /// can't grow without end. The ones due soonest are dropped first.
    static let artworkMissLimit = 2_000

    /// Resolves missing catalog IDs, backfills artwork, then writes to the playlist.
    /// Cheap when there's nothing to do.
    ///
    /// If a drain is already running this waits for it, and that drain takes one more look
    /// before it finishes.
    public func drainPendingWrites() async {
        if let runningDrain {
            wantsAnotherDrain = true
            await runningDrain.value
            return
        }
        let task = Task {
            repeat {
                wantsAnotherDrain = false
                await drainOnce()
            } while wantsAnotherDrain
            // Cleared here rather than by the caller, with nothing in between that can
            // suspend, so a caller can't join a drain that has already finished looking.
            runningDrain = nil
        }
        runningDrain = task
        await task.value
    }

    private func drainOnce() async {
        await resolveMissingCatalogIDs()
        await backfillArtwork()
        guard settings.autoAddToPlaylist else { return }
        guard writeBackoff.allows(at: now()) else { return }

        // Saved first, so every row has the identity it will keep. Only identities are held
        // across the requests below: sync can merge a row away while one is out.
        try? store.context.save()
        let pending = (try? store.context.fetch(MotifStore.pendingPlaylistWrites())) ?? []
        let writable = pending.filter { !$0.songID.isEmpty }.map(\.persistentModelID)
        guard !writable.isEmpty else { return }

        guard let playlistID = await ensurePlaylist() else { return }

        // How many will fit. Rows beyond it keep `needsPlaylistWrite`, without an attempt
        // against them, so raising the limit or trimming the playlist lets them through.
        var room = await roomInPlaylist(playlistID)
        playlistIsFull = room == 0
        guard room > 0 else { return }

        // A service failure not yet put down to its song. An outage and a song Apple chokes
        // on look the same from one request, so the next write decides: if it goes through,
        // the service is up and that song gets the attempt; if it fails too, it's an outage
        // and neither does.
        var unexplained: (id: PersistentIdentifier, message: String)?

        writing: for id in writable {
            guard room > 0 else {
                playlistIsFull = true
                break
            }
            // Looked up again each time: an earlier write's wait is long enough for a merge
            // to delete this row, or to fold it into one already in the playlist.
            guard let capture = liveCapture(id), capture.needsPlaylistWrite, !capture.songID.isEmpty
            else { continue }
            let songID = capture.songID

            do {
                try await playlistWriter.addSongs(ids: [songID], toPlaylist: playlistID)
                room -= 1
                noteSongAdded()
                writeBackoff.reset()
                if let capture = liveCapture(id) {
                    capture.needsPlaylistWrite = false
                    capture.addedToPlaylistAt = now()
                    capture.lastPlaylistWriteError = nil
                }
                if let earlier = unexplained {
                    unexplained = nil
                    chargeWriteAttempt(earlier.id, message: earlier.message)
                }
            } catch {
                let message = String(describing: error)
                switch Self.blame(for: error) {
                case .song:
                    // A deleted playlist also answers 404, and charging the song for it would
                    // drop every pending song one after another. Forget the playlist instead,
                    // keep the rows, and the next drain creates a new one.
                    if Self.isNotFound(error),
                       (try? await playlistWriter.playlistExists(playlistID)) == false {
                        forgetPlaylist()
                        liveCapture(id)?.lastPlaylistWriteError = message
                        break writing
                    }
                    // Won't succeed on retry, so stop trying this row.
                    chargeWriteAttempt(id, message: message)
                    liveCapture(id)?.needsPlaylistWrite = false
                case .service:
                    liveCapture(id)?.lastPlaylistWriteError = message
                    if unexplained == nil {
                        unexplained = (id, message)
                    } else {
                        // Two in a row. The rows stay as they were and the queue waits.
                        unexplained = nil
                        writeBackoff.recordFailure(at: now())
                        break writing
                    }
                case .setup:
                    // No token or no subscription fails every write the same way, and none
                    // of it is the song's doing. Kept pending for when it's sorted out.
                    liveCapture(id)?.lastPlaylistWriteError = message
                    writeBackoff.recordFailure(at: now())
                    break writing
                }
            }
        }
        // The last write failed and nothing came after to tell why. Assume the service, so
        // nothing is charged, but wait before asking again.
        if unexplained != nil { writeBackoff.recordFailure(at: now()) }
        try? store.context.save()
    }

    /// Whose fault a failed playlist write was, which decides what the queue does next.
    enum WriteFailure: Equatable {
        /// The song or the request for it. Charged to the row.
        case song
        /// The network or Apple's servers. Retried later, for nothing.
        case service
        /// The token or the subscription. Every write would fail, so the queue waits.
        case setup
    }

    static func blame(for error: any Error) -> WriteFailure {
        // Anything the writer didn't classify came from below it: a URL error, a
        // cancellation. Neither says anything about the song.
        guard let writeError = error as? PlaylistWriteError else { return .service }
        return switch writeError {
        case .permanent: .song
        case .transient: .service
        case .notConfigured, .notSubscribed: .setup
        }
    }

    static func isNotFound(_ error: any Error) -> Bool {
        if case .permanent(let status, _) = error as? PlaylistWriteError { return status == 404 }
        return false
    }

    /// The user deleted the playlist. Its cached size belonged to it too.
    private func forgetPlaylist() {
        settings.playlistID = nil
        knownTrackCount = nil
        countedAt = nil
        playlistIsFull = false
    }

    private func chargeWriteAttempt(_ id: PersistentIdentifier, message: String) {
        guard let capture = liveCapture(id) else { return }
        capture.playlistWriteAttempts += 1
        capture.lastPlaylistWriteError = message
    }

    /// The row, if it still exists. See ``MotifStore/existingCaptures(_:)``.
    private func liveCapture(_ id: PersistentIdentifier) -> Capture? {
        store.existingCaptures([id])[id]
    }

    /// How many more songs the playlist will take, or `Int.max` with the limit off.
    ///
    /// The count comes from Apple rather than from our own rows: someone can trim the
    /// playlist by hand, and the other device writes into the same library playlist.
    /// A count that fails leaves the writes alone — refusing to add because we couldn't ask
    /// would lose songs over a flaky network.
    private func roomInPlaylist(_ playlistID: String) async -> Int {
        guard settings.limitsPlaylistSize else { return .max }
        let limit = settings.playlistSizeLimit

        if let knownTrackCount, let countedAt,
           Date.now.timeIntervalSince(countedAt) < Self.countIsStaleAfter {
            return PlaylistSizeLimit.room(existing: knownTrackCount, limit: limit)
        }

        guard let counted = try? await playlistWriter.trackCount(
            inPlaylist: playlistID,
            upTo: limit
        ) else { return .max }

        knownTrackCount = counted
        countedAt = .now
        settings.playlistTrackCount = counted
        return PlaylistSizeLimit.room(existing: counted, limit: limit)
    }

    /// Keeps the cached count in step with what we just wrote.
    private func noteSongAdded() {
        guard let current = knownTrackCount else { return }
        knownTrackCount = current + 1
        settings.playlistTrackCount = current + 1
    }

    /// macOS has no catalog ID until we search for one.
    private func resolveMissingCatalogIDs() async {
        guard let catalogResolver else { return }
        try? store.context.save()
        let unresolved = ((try? store.context.fetch(MotifStore.awaitingCatalogID())) ?? []).map {
            (
                id: $0.persistentModelID,
                query: CatalogQuery(
                    title: $0.title,
                    artistName: $0.artistName,
                    duration: nil,
                    albumTitle: $0.albumTitle
                )
            )
        }

        for row in unresolved {
            let match: CatalogCandidate?
            do {
                match = try await catalogResolver.resolve(row.query)
            } catch {
                // The search itself failed: no network, or MusicKit can't get a developer
                // token (a new App ID can take a while to get one). That says nothing about
                // this song, so it isn't an attempt, and every other row would fail the same
                // way. The next drain tries again. Kept on the row so the probe can show why.
                liveCapture(row.id)?.lastPlaylistWriteError = "Catalog search failed: \(error)"
                break
            }
            // Gone, or given an ID some other way, while the search was out.
            guard let capture = liveCapture(row.id), capture.songID.isEmpty else { continue }
            guard let match else {
                capture.catalogLookupAttempts += 1
                // No confident match. Give up after a few tries.
                if capture.catalogLookupAttempts >= maxCatalogLookupAttempts {
                    capture.needsPlaylistWrite = false
                    capture.lastPlaylistWriteError = "No confident catalog match"
                }
                continue
            }
            capture.songID = match.id
            capture.lastPlaylistWriteError = nil
            if capture.artworkURL == nil { capture.artworkURL = match.artworkURL }
            if capture.albumTitle == nil { capture.albumTitle = match.albumTitle }
        }
        try? store.context.save()
    }

    /// Fills in artwork for rows that have a catalog ID but no cover, in one request.
    ///
    /// Songs the catalog comes back with no cover for are set aside in
    /// ``CaptureSettings/artworkMisses`` for ``artworkMissRetryAfter``. Before that, the newest
    /// fifty rows without a cover were asked about on every pass, and when the catalog had
    /// none for them no older row was ever reached.
    ///
    /// - Returns: how many songs were asked about and how many rows got a cover, or nil when
    ///   there was nothing to ask or the request failed.
    @discardableResult
    private func backfillArtwork() async -> (asked: Int, filled: Int)? {
        guard let catalogResolver else { return nil }
        let excluded = currentArtworkMisses()
        try? store.context.save()
        let missing = ((try? store.context.fetch(
            MotifStore.missingArtwork(excludingSongIDs: Array(excluded.keys))
        )) ?? []).map { (id: $0.persistentModelID, songID: $0.songID) }
        guard !missing.isEmpty else { return nil }

        let songIDs = Array(Set(missing.map(\.songID)))
        guard let urls = try? await catalogResolver.artworkURLs(forSongIDs: songIDs) else { return nil }

        let rows = store.existingCaptures(missing.map(\.id))
        var filled = 0
        for row in missing {
            guard let capture = rows[row.id],
                  capture.artworkURL == nil,
                  capture.songID == row.songID,
                  let url = urls[row.songID]
            else { continue }
            capture.artworkURL = url
            filled += 1
        }
        try? store.context.save()

        let unanswered = Set(songIDs).subtracting(urls.keys)
        if !unanswered.isEmpty {
            let retryAt = now().addingTimeInterval(Self.artworkMissRetryAfter)
            var misses = excluded
            for songID in unanswered { misses[songID] = retryAt }
            if misses.count > Self.artworkMissLimit {
                misses = Dictionary(
                    uniqueKeysWithValues: misses.sorted { $0.value > $1.value }.prefix(Self.artworkMissLimit).map { ($0.key, $0.value) }
                )
            }
            settings.artworkMisses = misses
        }
        return (songIDs.count, filled)
    }

    /// The remembered misses that haven't come due, forgetting the ones that have.
    private func currentArtworkMisses() -> [String: Date] {
        let stored = settings.artworkMisses
        let current = stored.filter { $0.value > now() }
        if current.count != stored.count { settings.artworkMisses = current }
        return current
    }

    /// Fetches covers for every row missing one, not just the first batch.
    ///
    /// ``drainPendingWrites()`` does a batch per pass, which keeps up with live listening but
    /// would take a long time to fill in a history after ``MotifStore/clearArtwork(urls:)``.
    ///
    /// Asked for from Settings, so the songs set aside as having no cover are asked about
    /// again too.
    ///
    /// - Returns: how many covers were found.
    @discardableResult
    public func backfillAllArtwork() async -> Int {
        settings.artworkMisses = [:]
        var total = 0
        // Every pass either fills its rows or sets their songs aside, so the next reaches
        // different ones, and the loop ends when nothing is left or a request fails. The
        // bound is only a backstop, at fifty rows a pass.
        for _ in 0..<2_000 {
            guard let pass = await backfillArtwork(), pass.asked > 0 else { break }
            total += pass.filled
        }
        return total
    }

    /// Creates the playlist on first use and remembers its ID.
    private func ensurePlaylist() async -> String? {
        if let existing = settings.playlistID { return existing }
        do {
            let id = try await playlistWriter.createPlaylist(
                name: settings.playlistName,
                description: "Songs Motif captured from Apple Music Radio."
            )
            settings.playlistID = id
            return id
        } catch {
            return nil
        }
    }
}

/// Stop searching for a song the catalog will not confidently identify.
public let maxCatalogLookupAttempts = 3
