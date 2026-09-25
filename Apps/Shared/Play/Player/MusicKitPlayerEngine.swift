import Foundation
import MusicKit
import Observation
import SwiftUI
import MotifCore
import MotifMusic

/// Plays through MusicKit's application player: Apple Music, inside Motif.
///
/// It keeps playing in the background (the app declares background audio), which is what lets
/// Motif keep every song it plays. The lock screen, Control Center and AirPlay come with it.
///
/// On the Mac the player isn't touched until Motif first plays something (see
/// `MotifPlayerContext.isInUse`), so someone who only plays music in Music keeps their media
/// keys there.
@MainActor
final class MusicKitPlayerEngine: PlayerEngine {
    var onChange: (() -> Void)?

    private(set) var current: PlayerTrack?
    private(set) var upNext: [PlayerTrack] = []
    /// Requests between being made and the player starting, while songs are looked up. A
    /// count, since a second request can arrive before the first has started.
    private var starting = 0
    /// Counts play requests. A request that a newer one overtook while its songs were looked up
    /// stops there, rather than setting its queue over the newer one's: two queues set one after
    /// the other cut the first one's start short (MPMusicPlayerControllerErrorDomain error 2) and
    /// could leave the older request playing.
    private var latestPlay = 0
    /// The request whose queue has been set and hasn't started yet. Until it has, the player
    /// can pass through the queue's first song on the way to the one asked for, which isn't
    /// shown: the song on changes once, to the one that starts.
    private var queueStarting: Int?
    /// Covers with an ordinary web address for the songs queued, by song id. The player's own
    /// entries often carry a `musicKit://` cover only MusicKit's ArtworkImage can draw, which
    /// can lose its picture as the mini player opens into Now Playing (see ``CoverImage``);
    /// these are drawn from Motif's own cache instead.
    private var queuedCovers: [String: Artwork] = [:]
    private var player: ApplicationMusicPlayer { ApplicationMusicPlayer.shared }
    private var watch: Task<Void, Never>?

    init() {
        MotifPlayerContext.whenInUse { [weak self] in self?.follow() }
    }

    /// Follows the player's queue and state, once it's in use.
    private func follow() {
        guard watch == nil else { return }
        watch = Task { [weak self] in
            guard let player = self?.player else { return }
            let changes = Observations {
                QueueState(
                    entryIDs: player.queue.entries.map(\.id),
                    currentID: player.queue.currentEntry?.id,
                    // An entry resolves from a bare title to its song a moment after it starts.
                    currentIsResolved: player.queue.currentEntry?.item != nil,
                    status: player.state.playbackStatus,
                    shuffle: player.state.shuffleMode,
                    repeatMode: player.state.repeatMode
                )
            }
            for await _ in changes {
                guard let self else { return }
                self.refresh()
            }
        }
    }

    private struct QueueState: Equatable {
        let entryIDs: [String]
        let currentID: String?
        let currentIsResolved: Bool
        let status: MusicPlayer.PlaybackStatus
        let shuffle: MusicPlayer.ShuffleMode?
        let repeatMode: MusicPlayer.RepeatMode?
    }

    // MARK: - State

    var status: PlayerStatus {
        if starting > 0 { return .loading }
        guard MotifPlayerContext.isInUse else { return .stopped }
        switch player.state.playbackStatus {
        case .playing, .seekingForward, .seekingBackward: return .playing
        case .paused, .interrupted: return current == nil ? .stopped : .paused
        case .stopped: return current == nil ? .stopped : .paused
        @unknown default: return current == nil ? .stopped : .paused
        }
    }

    var playbackTime: TimeInterval {
        guard MotifPlayerContext.isInUse else { return 0 }
        let time = player.playbackTime
        return time.isFinite ? max(0, time) : 0
    }

    var isShuffled: Bool { MotifPlayerContext.isInUse && player.state.shuffleMode == .songs }

    var repeatMode: PlayerRepeat {
        guard MotifPlayerContext.isInUse else { return .off }
        return switch player.state.repeatMode {
        case .one: .one
        case .all: .all
        default: .off
        }
    }

    private func refresh() {
        guard queueStarting == nil else {
            onChange?()
            return
        }
        let entries = Array(player.queue.entries)
        let currentEntry = player.queue.currentEntry
        current = currentEntry.map(track(from:))
        if MotifPlayerContext.isStation {
            upNext = []
        } else if let currentEntry, let index = entries.firstIndex(where: { $0.id == currentEntry.id }) {
            upNext = entries[(index + 1)...].map(track(from:))
        } else {
            upNext = entries.map(track(from:))
        }
        onChange?()
    }

    private func track(from entry: MusicPlayer.Queue.Entry) -> PlayerTrack {
        var song: Song?
        if case .song(let resolved) = entry.item { song = resolved }
        let title = song?.title ?? entry.title
        var artwork = song?.artwork ?? entry.artwork
        if artwork.flatMap(Self.loadableCover) == nil, let queued = song.flatMap({ queuedCovers[$0.id.rawValue] }) {
            artwork = queued
        }
        return PlayerTrack(
            id: entry.id,
            title: title,
            artistName: song?.artistName ?? entry.subtitle ?? "",
            albumTitle: song?.albumTitle,
            cover: artwork.map(CoverArt.artwork) ?? .url(nil, seed: title),
            // A station's songs report a length, but it can't be scrubbed or counted down.
            duration: MotifPlayerContext.isStation ? nil : song?.duration,
            isExplicit: song?.contentRating == .explicit,
            song: song
        )
    }

    // MARK: - Playing

    func play(_ request: PlayRequest, context: PlayContext, shuffled: Bool) async throws {
        latestPlay += 1
        let playID = latestPlay
        starting += 1
        onChange?()
        defer {
            starting -= 1
            if queueStarting == playID { queueStarting = nil }
            refresh()
        }
        try await Self.checkAccess()
        let allowsExplicit = PlayPreferences.allowsExplicit

        let queue: ApplicationMusicPlayer.Queue
        var systemShuffle = false
        // The song tapped, when it isn't the first: the queue is checked to be on it before
        // any of it plays.
        var startSong: StartSong?
        var queued: [Song] = []
        switch request {
        case .history(let songs, let start):
            let wanted = songs.indices.contains(start) && !shuffled ? songs[start].songID : nil
            let found = try await Self.lookUp(songs)
            let allowed = Self.allowed(found, allowsExplicit: allowsExplicit)
            try Self.checkStart(wanted, in: found.map(\.id.rawValue), allowed: allowed.map(\.id.rawValue))
            let index = allowed.firstIndex { $0.id.rawValue == wanted }
            startSong = StartSong(allowed, at: index)
            queued = allowed
            queue = try Self.queue(of: allowed, startingAt: index, shuffled: shuffled)
        case .songs(let songs, let start):
            let wanted = songs.indices.contains(start) && !shuffled ? songs[start].id.rawValue : nil
            let allowed = Self.allowed(songs, allowsExplicit: allowsExplicit)
            try Self.checkStart(wanted, in: songs.map(\.id.rawValue), allowed: allowed.map(\.id.rawValue))
            let index = allowed.firstIndex { $0.id.rawValue == wanted }
            startSong = StartSong(allowed, at: index)
            queued = allowed
            queue = try Self.queue(of: allowed, startingAt: index, shuffled: shuffled)
        case .station(let station):
            // A station can't be filtered ahead of time; the player model skips what's not allowed.
            queue = ApplicationMusicPlayer.Queue(for: [station])
        case .album(let album):
            if allowsExplicit {
                queue = ApplicationMusicPlayer.Queue(for: [album])
                systemShuffle = shuffled
            } else {
                queued = Self.allowed(try await Self.tracks(of: album), allowsExplicit: false)
                queue = try Self.queue(of: queued, startingAt: nil, shuffled: shuffled)
            }
        case .playlist(let playlist):
            if allowsExplicit {
                queue = ApplicationMusicPlayer.Queue(for: [playlist])
                systemShuffle = shuffled
            } else {
                queued = Self.allowed(try await Self.tracks(of: playlist), allowsExplicit: false)
                queue = try Self.queue(of: queued, startingAt: nil, shuffled: shuffled)
            }
        case .demoStation, .local:
            throw PlayerProblem.nothingToPlay
        }

        // Overtaken while the songs were looked up: the newer request plays instead.
        guard playID == latestPlay else { throw CancellationError() }

        // Everything about the queue is settled before it's handed over, and nothing touches
        // it after until it plays: a change while it gets ready can start it over from its
        // first song, which is then heard before the one tapped.
        // Counted, so Apple Music's own recommendations and Recently Played learn from it too.
        queue.affectsListeningHistory = true
        #if os(iOS)
        // As MusicKit asks, so the first change already uses it.
        player.transition = PlayPreferences.musicTransition
        #endif
        player.state.shuffleMode = systemShuffle ? .songs : .off
        if context.isStation { player.state.repeatMode = MusicPlayer.RepeatMode.none }
        queueStarting = playID
        queuedCovers = Self.covers(of: queued)
        player.queue = queue
        // In the same main-actor turn as the queue change, so nothing reading the player
        // (the capture source, its recheck) can see the new queue under the old flag, or the
        // old song under the new one.
        if context.isStation {
            MotifPlayerContext.playingStation(named: context.title)
        } else {
            MotifPlayerContext.playingOnDemand()
        }
        try await start(playID, on: startSong)
    }

    /// Starts the queue just set. If starting fails and no newer request is the reason, it's
    /// tried once more, quietly, a moment later: the player often manages it the second time,
    /// after something touched the queue while it was getting ready.
    private func start(_ playID: Int, on startSong: StartSong?) async throws {
        do {
            try await ready(playID, on: startSong)
            try await ApplicationPlayerCommands.play()
            return
        } catch {
            guard playID == latestPlay else { throw CancellationError() }
            guard PlaybackFailure(error).isWorthRetrying else { throw PlayerProblem(error) }
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard playID == latestPlay else { throw CancellationError() }
        do {
            try await ready(playID, on: startSong)
            try await ApplicationPlayerCommands.play()
        } catch {
            guard playID == latestPlay else { throw CancellationError() }
            throw PlayerProblem(error)
        }
    }

    /// A song tapped part way down a list, as the queue was made.
    private struct StartSong {
        let id: String
        let index: Int
        let listCount: Int

        /// Nil for the first song, or none: a queue starts there anyway.
        init?(_ songs: [Song], at index: Int?) {
            guard let index, index > 0 else { return nil }
            id = songs[index].id.rawValue
            self.index = index
            listCount = songs.count
        }
    }

    /// Gets a queue started part way down ready, and puts it on the song tapped if it isn't
    /// already, before any of it plays. Told only where to start, the player can begin on the
    /// queue's first song and move on a moment later, after its first seconds are heard.
    private func ready(_ playID: Int, on startSong: StartSong?) async throws {
        guard let startSong else { return }
        try await ApplicationPlayerCommands.prepare()
        guard playID == latestPlay else { throw CancellationError() }
        let entries = Array(player.queue.entries)
        let currentID = player.queue.currentEntry?.id
        let move = QueueStart.correction(
            wantedID: startSong.id,
            wantedIndex: startSong.index,
            listCount: startSong.listCount,
            entryIDs: entries.map { $0.item?.id.rawValue },
            current: entries.firstIndex { $0.id == currentID }
        )
        if let move { player.queue.currentEntry = entries[move] }
    }

    func enqueue(_ request: PlayRequest, next: Bool) async throws {
        // Songs looked up for the queue that's on now. If another replaces it meanwhile, they
        // aren't added to that one, nor while it's still getting ready to play.
        let queueID = latestPlay
        try await Self.checkAccess()
        let allowsExplicit = PlayPreferences.allowsExplicit
        let songs: [Song]
        switch request {
        case .history(let history, _):
            songs = try await Self.lookUp(history)
        case .songs(let list, _):
            songs = list
        case .album(let album):
            guard !allowsExplicit else {
                try await ApplicationPlayerCommands.insert([album], next: next)
                refresh()
                return
            }
            songs = try await Self.tracks(of: album)
        case .playlist(let playlist):
            guard !allowsExplicit else {
                try await ApplicationPlayerCommands.insert([playlist], next: next)
                refresh()
                return
            }
            songs = try await Self.tracks(of: playlist)
        case .station, .demoStation, .local:
            // A station replaces the queue; there's nothing to add it after.
            throw PlayerProblem.nothingToPlay
        }
        let allowed = Self.allowed(songs, allowsExplicit: allowsExplicit)
        guard !allowed.isEmpty else { throw Self.emptyProblem(allowsExplicit: allowsExplicit) }
        try Task.checkCancellation()
        guard queueID == latestPlay, starting == 0 else { throw CancellationError() }
        queuedCovers.merge(Self.covers(of: allowed)) { _, new in new }
        try await ApplicationPlayerCommands.insert(allowed, next: next)
        refresh()
    }

    func pause() {
        // Switching the music source pauses the old player, which may never have played.
        guard MotifPlayerContext.isInUse else { return }
        player.pause()
    }

    func resume() async throws {
        do {
            try await ApplicationPlayerCommands.play()
        } catch {
            throw PlayerProblem(error)
        }
    }

    func skipToNext() async throws {
        try await ApplicationPlayerCommands.skipToNext()
    }

    /// Back to the start of the song after the first few seconds, as every player does, and
    /// to the song before otherwise.
    func skipToPrevious() async throws {
        if playbackTime > 3 || upNext.isEmpty && MotifPlayerContext.isStation {
            player.restartCurrentEntry()
        } else {
            try await ApplicationPlayerCommands.skipToPrevious()
        }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = max(0, time)
    }

    func setShuffled(_ isShuffled: Bool) {
        player.state.shuffleMode = isShuffled ? .songs : .off
    }

    func setRepeat(_ mode: PlayerRepeat) {
        player.state.repeatMode = switch mode {
        case .off: MusicPlayer.RepeatMode.none
        case .all: .all
        case .one: .one
        }
    }

    func jump(toUpNext index: Int) async throws {
        guard let base = upNextStart else { return }
        let entries = player.queue.entries
        let target = entries.index(entries.startIndex, offsetBy: base + index, limitedBy: entries.endIndex)
        guard let target, target < entries.endIndex else { return }
        player.queue.currentEntry = entries[target]
        try await ApplicationPlayerCommands.play()
    }

    func removeUpNext(at offsets: IndexSet) {
        guard let base = upNextStart else { return }
        player.queue.entries.remove(atOffsets: IndexSet(offsets.map { $0 + base }))
    }

    func moveUpNext(from offsets: IndexSet, to destination: Int) {
        guard let base = upNextStart else { return }
        player.queue.entries.move(fromOffsets: IndexSet(offsets.map { $0 + base }), toOffset: destination + base)
    }

    /// Where ``upNext`` starts in the player's own list.
    private var upNextStart: Int? {
        let entries = player.queue.entries
        guard let currentID = player.queue.currentEntry?.id,
              let index = entries.firstIndex(where: { $0.id == currentID })
        else { return nil }
        return entries.distance(from: entries.startIndex, to: index) + 1
    }

    // MARK: - Helpers

    /// Asks for Apple Music access if it hasn't been asked, since the person just pressed
    /// Play and the reason is plain. Then makes sure the account can play the catalog.
    static func checkAccess() async throws {
        var authorization = MusicAuthorization.currentStatus
        if authorization == .notDetermined {
            authorization = await MusicAuthorization.request()
        }
        guard authorization == .authorized else { throw PlayerProblem.accessDenied }
        // Can't tell offline, and a network hiccup mustn't stop music already downloaded.
        if let subscription = try? await MusicSubscription.current, !subscription.canPlayCatalogContent {
            throw PlayerProblem.needsSubscription(canSubscribe: subscription.canBecomeSubscriber)
        }
    }

    /// History songs as Apple Music songs, in order, leaving out any that can't be found.
    private static func lookUp(_ songs: [HistorySong]) async throws -> [Song] {
        let ids = songs.map(\.songID).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }
        do {
            return try await MusicKitPlaybackService.songs(for: ids)
        } catch {
            throw PlayerProblem(error)
        }
    }

    /// A queue of songs, in order or freshly shuffled. Throws when there's nothing left.
    private static func queue(of songs: [Song], startingAt start: Int?, shuffled: Bool) throws -> ApplicationMusicPlayer.Queue {
        guard !songs.isEmpty else { throw emptyProblem(allowsExplicit: PlayPreferences.allowsExplicit) }
        if shuffled { return ApplicationMusicPlayer.Queue(for: fresh(songs)) }
        return ApplicationMusicPlayer.Queue(for: songs, startingAt: start.map { songs[$0] })
    }

    /// The song someone tapped was left out for being explicit: say so, rather than quietly
    /// playing the list from somewhere else.
    private static func checkStart(_ wanted: String?, in all: [String], allowed: [String]) throws {
        guard let wanted, all.contains(wanted), !allowed.contains(wanted) else { return }
        throw PlayerProblem.explicitSong
    }

    /// Everything, or everything but the explicit songs.
    private static func allowed(_ songs: [Song], allowsExplicit: Bool) -> [Song] {
        allowsExplicit ? songs : songs.filter { $0.contentRating != .explicit }
    }

    /// Nothing to play: because every song was explicit, or because none could be found.
    private static func emptyProblem(allowsExplicit: Bool) -> PlayerProblem {
        allowsExplicit ? .nothingToPlay : .onlyExplicit
    }

    /// An album's songs, for playing it without its explicit ones.
    private static func tracks(of album: Album) async throws -> [Song] {
        do {
            return songs(in: try await album.with([.tracks]).tracks)
        } catch {
            throw PlayerProblem(error)
        }
    }

    /// A playlist's songs, every page of them up to a couple of thousand.
    private static func tracks(of playlist: Playlist) async throws -> [Song] {
        do {
            var batch = try await playlist.with([.tracks]).tracks
            var songs = Self.songs(in: batch)
            while let current = batch, current.hasNextBatch, songs.count < 2_000 {
                batch = try await current.nextBatch()
                songs += Self.songs(in: batch)
            }
            return songs
        } catch {
            throw PlayerProblem(error)
        }
    }

    private static func songs(in tracks: MusicItemCollection<Track>?) -> [Song] {
        (tracks ?? []).compactMap { track in
            if case .song(let song) = track { return song }
            return nil
        }
    }

    /// The songs' covers that have an ordinary web address, by song id.
    private static func covers(of songs: [Song]) -> [String: Artwork] {
        var covers: [String: Artwork] = [:]
        for song in songs {
            if let artwork = song.artwork, loadableCover(artwork) != nil { covers[song.id.rawValue] = artwork }
        }
        return covers
    }

    private static func loadableCover(_ artwork: Artwork) -> URL? {
        CoverImage.loadableURL(of: artwork, pixels: CoverImage.pixels(for: 0))
    }

    private static func fresh(_ songs: [Song]) -> [Song] {
        FreshShuffle.order(songs, artist: { StatsCalculator.folded($0.artistName) }, seed: .random(in: 0...UInt64.max))
    }
}
