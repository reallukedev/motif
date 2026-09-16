import Testing
import Foundation
import SwiftData
@testable import MotifCore

/// Records what was asked of it, and can be told to fail.
final class FakePlaylistWriter: PlaylistWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var _created: [String] = []
    private var _added: [(ids: [String], playlist: String)] = []
    var createResult: Result<String, any Error> = .success("p.fake")
    var addResult: Result<Void, any Error> = .success(())
    /// What the playlist already held before this test started.
    var existingTracks = 0
    /// Fails the count, as a flaky network would.
    var countFails = false

    var created: [String] { lock.withLock { _created } }
    var added: [(ids: [String], playlist: String)] { lock.withLock { _added } }
    var addedIDs: [String] { added.flatMap(\.ids) }
    /// How many times the playlist was counted, so the cache can be checked.
    private(set) var countRequests = 0

    func createPlaylist(name: String, description: String?) async throws -> String {
        lock.withLock { _created.append(name) }
        return try createResult.get()
    }

    func addSongs(ids: [String], toPlaylist playlistID: String) async throws {
        lock.withLock { _added.append((ids, playlistID)) }
        try addResult.get()
    }

    /// Counts what the playlist started with plus what this fake has been told to add, so a
    /// test doesn't have to keep the two in step itself.
    func trackCount(inPlaylist playlistID: String, upTo ceiling: Int?) async throws -> Int {
        lock.withLock { countRequests += 1 }
        if countFails { throw URLError(.notConnectedToInternet) }
        return existingTracks + addedIDs.count
    }
}

struct FakeCatalogResolver: CatalogResolving {
    let result: CatalogCandidate?
    var artwork: [String: String] = [:]
    var stationName: String?
    /// The search request fails, as it does offline or without a MusicKit developer token.
    var searchFails = false
    func resolve(_ query: CatalogQuery) async throws -> CatalogCandidate? {
        if searchFails { throw URLError(.notConnectedToInternet) }
        return result
    }
    func artworkURLs(forSongIDs ids: [String]) async throws -> [String: String] {
        artwork.filter { ids.contains($0.key) }
    }
    func mostRecentStationName() async throws -> String? { stationName }
}

@MainActor
@Suite("Capture pipeline")
struct CaptureCoordinatorTests {
    let store: MotifStore
    let writer = FakePlaylistWriter()
    /// Removes the defaults suite when the test finishes.
    private let scratch = ScratchDefaults()
    let settings: CaptureSettings

    /// A fresh store and defaults per test, since tests run in parallel.
    init() throws {
        store = try MotifStore(inMemory: true)
        settings = scratch.settings
        // The minimum listening time has its own suite below.
        settings.minimumListenSeconds = 0
    }

    func coordinator(resolver: (any CatalogResolving)? = nil) -> CaptureCoordinator {
        CaptureCoordinator(
            store: store,
            settings: settings,
            playlistWriter: writer,
            catalogResolver: resolver
        )
    }

    /// Oldest first, so the order is the same on every run. A fetch with no sort comes back in
    /// whatever order the store likes, which made "the first session" a guess.
    static var sessionsInOrder: FetchDescriptor<Session> {
        FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)])
    }

    func radio(
        title: String = "Dai Dai",
        artist: String = "Shakira & Burna Boy",
        id: String? = "6768469976"
    ) -> NowPlayingObservation {
        NowPlayingObservation(
            title: title,
            artistName: artist,
            catalogSongID: id,
            duration: 223,
            rawFields: ["entry.id": "PxDIf4ejk::STREAM"]
        )
    }

    @Test("a radio track is stored and added to the playlist")
    func capturesAndWrites() async throws {
        let decision = await coordinator().handle(radio())
        #expect(decision.isCapture)

        let captures = try store.context.fetch(MotifStore.radioCaptures())
        #expect(captures.count == 1)
        #expect(captures.first?.songID == "6768469976")
        #expect(writer.created == ["Heard on Radio"])
        #expect(writer.addedIDs == ["6768469976"])
        #expect(captures.first?.needsPlaylistWrite == false)
    }

    /// `playerInfo` repeats the same track every ~16 seconds.
    @Test("repeated observations of one track produce a single capture")
    func dedupesHeartbeat() async throws {
        let subject = coordinator()
        let start = Date()
        for offset in stride(from: 0, through: 64, by: 16) {
            await subject.handle(radio(), now: start.addingTimeInterval(Double(offset)))
        }

        let captures = try store.context.fetch(MotifStore.radioCaptures())
        #expect(captures.count == 1)
        #expect(writer.addedIDs == ["6768469976"])
    }

    /// Two observations arriving together mustn't both pass the dedupe check.
    @Test("concurrent observations of one track still produce a single capture")
    func concurrentObservationsDeduped() async throws {
        let subject = coordinator()
        async let first = subject.handle(radio())
        async let second = subject.handle(radio())
        _ = await (first, second)

        #expect(try store.context.fetch(MotifStore.radioCaptures()).count == 1)
    }

    @Test("the playlist is created once and reused")
    func createsPlaylistOnce() async throws {
        let subject = coordinator()
        await subject.handle(radio(title: "One", id: "1"))
        await subject.handle(radio(title: "Two", id: "2"))

        #expect(writer.created.count == 1)
        #expect(writer.addedIDs == ["1", "2"])
        #expect(settings.playlistID == "p.fake")
    }

    @Test("an on-demand track is neither stored nor written")
    func ignoresOnDemand() async throws {
        var observation = radio()
        observation.rawFields["entry.id"] = "PRhKeIIy0::6ostOUDHU"
        await coordinator().handle(observation)

        #expect(try store.context.fetch(MotifStore.radioCaptures()).isEmpty)
        #expect(writer.added.isEmpty)
    }

    /// macOS: no catalog id at capture time, so the row is stored first and resolved after.
    @Test("a macOS capture is resolved by catalog search before being written")
    func resolvesCatalogID() async throws {
        let subject = coordinator(
            resolver: FakeCatalogResolver(
                result: CatalogCandidate(
                    id: "9999",
                    title: "Nostalgia",
                    artistName: "Lossapardo",
                    albumTitle: "Nostalgia",
                    artworkURL: "https://example.test/art.jpg"
                )
            )
        )
        let observation = NowPlayingObservation(
            title: "Nostalgia",
            artistName: "Lossapardo",
            albumTitle: "Nostalgia - Single",
            catalogSongID: nil,
            duration: nil,
            playerPosition: 0
        )
        await subject.handle(observation)

        let captures = try store.context.fetch(MotifStore.radioCaptures())
        #expect(captures.first?.songID == "9999")
        #expect(writer.addedIDs == ["9999"])
        // macOS gets no artwork from playerInfo, so the match has to supply it.
        #expect(captures.first?.artworkURL == "https://example.test/art.jpg")
    }

    /// A wrong match would write the wrong song into someone's library.
    @Test("a track the catalog cannot identify is stored but never written")
    func unresolvableIsNotWritten() async throws {
        let subject = coordinator(resolver: FakeCatalogResolver(result: nil))
        let observation = NowPlayingObservation(
            title: "Nostalgia", artistName: "Lossapardo", catalogSongID: nil, playerPosition: 0
        )
        for _ in 0..<maxCatalogLookupAttempts { await subject.handle(observation) }

        let captures = try store.context.fetch(MotifStore.radioCaptures())
        #expect(captures.count == 1)
        #expect(captures.first?.songID.isEmpty == true)
        #expect(writer.added.isEmpty)
        #expect(captures.first?.needsPlaylistWrite == false)
    }

    /// Seen on a new App ID: every search failed with `developerTokenRequestFailed` until
    /// MusicKit caught up, and the songs from that window never got an id or a cover.
    @Test("a failed search doesn't use up the song's lookup attempts")
    func failedSearchIsRetried() async throws {
        let observation = NowPlayingObservation(
            title: "Nostalgia", artistName: "Lossapardo", catalogSongID: nil, playerPosition: 0
        )
        var failing = FakeCatalogResolver(result: nil)
        failing.searchFails = true
        let offline = coordinator(resolver: failing)
        for _ in 0...maxCatalogLookupAttempts { await offline.handle(observation) }

        let capture = try #require(try store.context.fetch(MotifStore.radioCaptures()).first)
        #expect(capture.catalogLookupAttempts == 0)
        #expect(capture.needsPlaylistWrite)
        #expect(capture.lastPlaylistWriteError?.hasPrefix("Catalog search failed") == true)

        let working = coordinator(
            resolver: FakeCatalogResolver(
                result: CatalogCandidate(
                    id: "9999",
                    title: "Nostalgia",
                    artistName: "Lossapardo",
                    albumTitle: "Nostalgia",
                    artworkURL: "https://example.test/art.jpg"
                )
            )
        )
        await working.handle(observation)
        #expect(capture.songID == "9999")
        #expect(capture.artworkURL == "https://example.test/art.jpg")
        #expect(capture.lastPlaylistWriteError == nil)
    }

    @Test("a transient write failure leaves the capture pending")
    func transientFailureRetries() async throws {
        writer.addResult = .failure(PlaylistWriteError.transient(statusCode: 503, message: ""))
        await coordinator().handle(radio())

        let capture = try #require(try store.context.fetch(MotifStore.radioCaptures()).first)
        #expect(capture.needsPlaylistWrite)
        // An outage isn't the song's fault, so it costs no attempt. See `PlaylistQueueTests`.
        #expect(capture.playlistWriteAttempts == 0)
    }

    /// A request Apple rejects won't succeed on retry, and retrying would stall the queue.
    /// A setup problem, by contrast, keeps the song: see `PlaylistQueueTests`.
    @Test("a permanent write failure stops the capture being retried")
    func permanentFailureStops() async throws {
        writer.addResult = .failure(
            PlaylistWriteError.permanent(statusCode: 400, message: "bad request")
        )
        await coordinator().handle(radio())

        let capture = try #require(try store.context.fetch(MotifStore.radioCaptures()).first)
        #expect(!capture.needsPlaylistWrite)
    }

    /// Artwork used to come only from catalog search, which iOS rows never go through.
    @Test("artwork is backfilled for a row that already has a catalog id")
    func backfillsArtwork() async throws {
        let subject = coordinator(
            resolver: FakeCatalogResolver(
                result: nil,
                artwork: ["6768469976": "https://example.test/cover.jpg"]
            )
        )
        await subject.handle(radio())

        let capture = try #require(try store.context.fetch(MotifStore.radioCaptures()).first)
        #expect(capture.artworkURL == "https://example.test/cover.jpg")
    }

    /// Starting the app mid-station misses the tune-in, which used to leave the session
    /// called "Radio".
    @Test("the station is looked up when no tune-in was witnessed")
    func stationLookedUpWhenNotAnnounced() async throws {
        let subject = coordinator(
            resolver: FakeCatalogResolver(result: nil, stationName: "Apple Música Uno")
        )
        await subject.handle(radio())

        let sessions = try store.context.fetch(Self.sessionsInOrder)
        try #require(sessions.count == 1)
        let session = sessions[0]
        #expect(session.station?.name == "Apple Música Uno")
    }

    @Test("an announced station beats the lookup")
    func announcedStationWins() async throws {
        let subject = coordinator(
            resolver: FakeCatalogResolver(result: nil, stationName: "Something Else")
        )
        await subject.handle(NowPlayingObservation(title: "Apple Music 1", artistName: ""))
        await subject.handle(radio())

        let sessions = try store.context.fetch(Self.sessionsInOrder)
        try #require(sessions.count == 1)
        let session = sessions[0]
        #expect(session.station?.name == "Apple Music 1")
    }

    @Test("turning off auto-add stores the capture without writing it")
    func autoAddOff() async throws {
        settings.autoAddToPlaylist = false
        await coordinator().handle(radio())

        #expect(try store.context.fetch(MotifStore.radioCaptures()).count == 1)
        #expect(writer.added.isEmpty)
    }

    @Test("songs stop going in once the playlist reaches its limit")
    func stopsAtTheLimit() async throws {
        settings.limitsPlaylistSize = true
        settings.playlistSizeLimit = 50
        writer.existingTracks = 49

        let subject = coordinator()
        await subject.handle(radio(title: "One", id: "1"))
        await subject.handle(radio(title: "Two", id: "2"))

        // Room for one, so the second song is kept but not written.
        #expect(writer.addedIDs == ["1"])
        #expect(try store.context.fetch(MotifStore.radioCaptures()).count == 2)
        #expect(subject.playlistIsFull)
    }

    /// Raising the limit, or trimming the playlist, has to let the waiting songs through, so
    /// they must still be owed a write and must not have burned an attempt.
    @Test("a song held back by the limit stays pending without a failed attempt")
    func heldBackSongStaysPending() async throws {
        settings.limitsPlaylistSize = true
        settings.playlistSizeLimit = 50
        writer.existingTracks = 50

        let subject = coordinator()
        await subject.handle(radio(title: "One", id: "1"))

        let capture = try #require(try store.context.fetch(MotifStore.radioCaptures()).first)
        #expect(writer.added.isEmpty)
        #expect(capture.needsPlaylistWrite)
        #expect(capture.playlistWriteAttempts == 0)
        #expect(capture.lastPlaylistWriteError == nil)
    }

    @Test("turning the limit off writes however many songs there are")
    func limitOffWritesEverything() async throws {
        settings.limitsPlaylistSize = false
        writer.existingTracks = 5_000

        await coordinator().handle(radio(title: "One", id: "1"))

        #expect(writer.addedIDs == ["1"])
        // Nothing to count when there's no ceiling to check against.
        #expect(writer.countRequests == 0)
    }

    /// Refusing to write because we couldn't ask how full the playlist is would lose songs
    /// over a flaky network, which is worse than overshooting the limit.
    @Test("a failed count lets the write go ahead")
    func failedCountDoesNotBlockWrites() async throws {
        settings.limitsPlaylistSize = true
        writer.countFails = true

        await coordinator().handle(radio(title: "One", id: "1"))

        #expect(writer.addedIDs == ["1"])
    }

    /// macOS drains every 10 seconds, so counting the playlist each time would be a request
    /// per poll.
    @Test("the playlist is counted once and then tracked locally")
    func countIsCached() async throws {
        settings.limitsPlaylistSize = true
        settings.playlistSizeLimit = 250
        writer.existingTracks = 10

        let subject = coordinator()
        await subject.handle(radio(title: "One", id: "1"))
        await subject.handle(radio(title: "Two", id: "2"))
        await subject.handle(radio(title: "Three", id: "3"))

        #expect(writer.addedIDs == ["1", "2", "3"])
        #expect(writer.countRequests == 1)
        // Counted 10, then three went in.
        #expect(settings.playlistTrackCount == 13)
    }

    @Test("a station announcement names the session without being captured")
    func stationAnnouncementNamesSession() async throws {
        let subject = coordinator()
        await subject.handle(NowPlayingObservation(title: "Apple Music 1", artistName: ""))
        await subject.handle(radio())

        #expect(try store.context.fetch(MotifStore.radioCaptures()).count == 1)
        let sessions = try store.context.fetch(Self.sessionsInOrder)
        try #require(sessions.count == 1)
        let session = sessions[0]
        #expect(session.station?.name == "Apple Music 1")
    }
}

/// The minimum listening time: skipping through songs records nothing, and a song left to
/// play is recorded once.
@MainActor
@Suite("Minimum listening time")
struct MinimumListenTests {
    let store: MotifStore
    /// Removes the defaults suite when the test finishes.
    private let scratch = ScratchDefaults()
    let settings: CaptureSettings
    let writer: FakePlaylistWriter
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        store = try MotifStore(inMemory: true)
        settings = scratch.settings
        settings.minimumListenSeconds = 30
        writer = FakePlaylistWriter()
    }

    func coordinator() -> CaptureCoordinator {
        CaptureCoordinator(store: store, settings: settings, playlistWriter: writer)
    }

    func song(_ title: String) -> NowPlayingObservation {
        NowPlayingObservation(
            title: title,
            artistName: "An Artist",
            catalogSongID: title,
            duration: 200,
            rawFields: ["entry.id": "x::STREAM"]
        )
    }

    @Test("a song is not captured the moment it starts")
    func waitsBeforeCapturing() async throws {
        let decision = await coordinator().handle(song("Walkin"), now: start)
        guard case .ignore(.tooShort(let played, let needs)) = decision else {
            Issue.record("Expected tooShort, got \(decision)")
            return
        }
        #expect(played == 0)
        #expect(needs == 30)
        #expect(try store.context.fetch(MotifStore.allCaptures()).isEmpty)
    }

    @Test("it is captured once it has played long enough")
    func capturesAfterTheThreshold() async {
        let coordinator = coordinator()
        _ = await coordinator.handle(song("Walkin"), now: start)
        let decision = await coordinator.handle(song("Walkin"), now: start.addingTimeInterval(31))
        #expect(decision.isCapture)
    }

    @Test("skipping through songs records none of them")
    func skippingRecordsNothing() async throws {
        let coordinator = coordinator()
        for (index, title) in ["One", "Two", "Three", "Four"].enumerated() {
            let decision = await coordinator.handle(
                song(title), now: start.addingTimeInterval(Double(index) * 5)
            )
            #expect(!decision.isCapture, "\(title) should not have been captured")
        }
        #expect(try store.context.fetch(MotifStore.allCaptures()).isEmpty)
    }

    @Test("the clock restarts when the song changes")
    func clockRestartsPerSong() async {
        let coordinator = coordinator()
        _ = await coordinator.handle(song("One"), now: start)
        // Long enough for "One", but "Two" has only just arrived.
        let decision = await coordinator.handle(song("Two"), now: start.addingTimeInterval(40))
        guard case .ignore(.tooShort(let played, _)) = decision else {
            Issue.record("Expected tooShort, got \(decision)")
            return
        }
        #expect(played == 0)
    }

    /// The user asked for it explicitly.
    @Test("forcing skips the wait")
    func forceBypassesTheThreshold() async {
        let decision = await coordinator().handle(song("Walkin"), now: start, force: true)
        #expect(decision.isCapture)
    }

    @Test("zero means capture straight away")
    func zeroDisablesTheWait() async {
        settings.minimumListenSeconds = 0
        let decision = await coordinator().handle(song("Walkin"), now: start)
        #expect(decision.isCapture)
    }

    /// The caller schedules its re-check from the remaining time.
    @Test("the reported wait counts down")
    func reportsTimeRemaining() async {
        let coordinator = coordinator()
        _ = await coordinator.handle(song("Walkin"), now: start)
        let decision = await coordinator.handle(song("Walkin"), now: start.addingTimeInterval(20))
        guard case .ignore(.tooShort(let played, let needs)) = decision else {
            Issue.record("Expected tooShort, got \(decision)")
            return
        }
        #expect(played == 20)
        #expect(needs - played == 10)
    }
}
