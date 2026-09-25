import Foundation
import Observation
import SwiftUI
import MusicKit
import MotifCore
import MotifMusic

/// Motif's player, as every screen sees it: what's on, what's next, and the controls.
///
/// The engine plays; this adds what Motif knows on top. It notices skips and remembers them
/// (see ``ListeningSignals``) so the mixes learn, runs the sleep timer, and turns failures
/// into something the screens can explain.
@MainActor
@Observable
final class PlayerModel {
    private(set) var status: PlayerStatus = .stopped
    private(set) var current: PlayerTrack?
    private(set) var upNext: [PlayerTrack] = []
    private(set) var isShuffled = false
    private(set) var repeatMode: PlayerRepeat = .off
    /// When the current song started, for how close it is to counting.
    private(set) var trackStartedAt: Date?
    /// Where the music is coming from. Nil until something has been played this launch.
    private(set) var context: PlayContext?
    /// The last thing that went wrong, until it's dismissed or something plays.
    var problem: PlayerProblem?
    private(set) var sleepTimer: SleepTimer?
    /// Skips and "suggest less", which steer the mixes.
    private(set) var signals: ListeningSignals
    /// Motif Radio's finds that played and had their downloads removed after, newest first, to
    /// keep from Up Next if one was liked.
    private(set) var playedAndRemoved: [PlayerTrack] = []

    /// The song left paused when Motif last closed, shown as the song on until it's played or
    /// replaced. Nothing is handed to the engine until then, so opening Motif never takes the
    /// audio or the media keys from another app. See ``restoreLastSession()``.
    private(set) var waitingSession: LastSession?

    /// Where the person has asked play or pause to go, shown at once while the player catches
    /// up, so the button answers the tap rather than the engine a moment later.
    private(set) var intendsToPlay: Bool?

    @ObservationIgnored private var engine: any PlayerEngine
    /// The player the source was switched to while music played: it takes over from the next
    /// thing played, so switching doesn't stop the music.
    @ObservationIgnored private var nextEngine: (any PlayerEngine)?
    @ObservationIgnored private let signalsStore: SignalsStore
    /// How far the current song got, sampled while playing: at a song change the engine
    /// already reports the new song's time.
    @ObservationIgnored private var lastSample: (trackID: String, time: TimeInterval)?
    /// Until when a song giving way isn't a skip: a new request replaced the queue, and the
    /// player can report the change a moment after the request returns.
    @ObservationIgnored private var replacingQueueUntil = Date.distantPast
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Counts play requests, so a slow one finishing late can't undo a newer one.
    @ObservationIgnored private var latestRequest = 0
    /// Play requests still starting. While one is, nothing is added to the queue it's
    /// replacing, since the live mix's picks belong to the queue that was on.
    @ObservationIgnored private var requestsStarting = 0
    /// Set by Previous: going back isn't a verdict on the song being left.
    @ObservationIgnored private var isGoingBack = false

    /// Sample data: the engine only pretends, and songs play without catalog ids.
    let isDemo: Bool

    init(engine: any PlayerEngine, isDemo: Bool = false, signalsStore: SignalsStore = SignalsStore()) {
        self.engine = engine
        self.isDemo = isDemo
        self.signalsStore = signalsStore
        self.signals = signalsStore.load()
        engine.onChange = { [weak self] in self?.engineChanged() }
        (engine as? LocalPlayerEngine)?.onNotice = { [weak self] in self?.confirm($0) }
        engineChanged()
    }

    var hasQueue: Bool { current != nil }

    /// For an alert: true while there's a problem to show, and clears it when dismissed.
    var isShowingProblem: Bool {
        get { problem != nil }
        set { if !newValue { problem = nil } }
    }

    /// A mix's songs as the player takes them: the ones Apple Music identified, or all of
    /// them for a player that finds songs by name.
    func songs(in mix: Mix) -> [HistorySong] {
        (engine.playsByName ? mix.songs : mix.playableSongs).map(HistorySong.init)
    }

    /// Whether a history song can be played: it has a catalog id, or the player finds songs by
    /// name, as sample data's and your own music's do.
    func canPlay(songID: String) -> Bool {
        engine.playsByName || !songID.isEmpty
    }

    /// Changes the player behind the model, when the music source changes. Whatever was
    /// playing stops, unless it's to keep playing.
    /// - Parameter keepingWhatsPlaying: for a quick switch: a song that's on carries on, and
    ///   the new player takes over from the next thing played.
    func use(_ engine: any PlayerEngine, keepingWhatsPlaying: Bool = false) {
        guard engine !== self.engine else {
            nextEngine = nil
            return
        }
        if keepingWhatsPlaying, current != nil {
            nextEngine = engine
            return
        }
        nextEngine = nil
        // Your own songs can't wait on the Apple Music player, nor Apple Music's on yours.
        if let waitingSession, waitingSession.isYourMusic != (engine is LocalPlayerEngine) {
            self.waitingSession = nil
            current = nil
            upNext = []
            status = .stopped
        }
        self.engine.pause()
        self.engine.deactivate()
        self.engine.onChange = nil
        self.engine = engine
        engine.onChange = { [weak self] in self?.engineChanged() }
        (engine as? LocalPlayerEngine)?.onNotice = { [weak self] in self?.confirm($0) }
        // A request still starting on the old player is no longer the latest, and the song
        // that was on isn't being skipped: the source changed under it.
        latestRequest += 1
        lastSample = nil
        replacingQueueUntil = .now.addingTimeInterval(3)
        live = nil
        liveGetsReady = false
        livePick?.cancel()
        livePick = nil
        context = nil
        intendsToPlay = nil
        sleepTimer = nil
        engineChanged()
    }
    /// Playing, or asked to play and about to. What the play and pause buttons show.
    var isPlaying: Bool { intendsToPlay ?? (status == .playing) }

    /// The current song's position. Not observed: views that show it redraw on a timeline.
    var playbackTime: TimeInterval { waitingSession?.time ?? engine.playbackTime }

    // MARK: - Playing

    /// Replaces the queue and plays.
    ///
    /// Requests can overlap (a lookup can take a while), so each carries a number and only the
    /// newest one decides where the music is coming from.
    func play(_ request: PlayRequest, from context: PlayContext, shuffled: Bool = false) {
        Task { await start(request, from: context, shuffled: shuffled) }
    }

    /// ``play(_:from:shuffled:)``, returning once the player has started or failed: for Siri
    /// and Shortcuts, which mustn't finish before the music does start.
    func start(_ request: PlayRequest, from context: PlayContext, shuffled: Bool = false) async {
        takeOverIfSwitched()
        intendsToPlay = true
        settleIntent()
        problem = nil
        // A new queue is a new song, not the end of this one.
        if sleepTimer == .endOfSong { sleepTimer = nil }
        latestRequest += 1
        let requestID = latestRequest
        replacingQueueUntil = .distantFuture
        // A pick still being looked up for the live mix on now would land in the new queue,
        // and adding to a queue as it starts cuts its start short.
        livePick?.cancel()
        livePick = nil
        requestsStarting += 1
        let engine = self.engine
        let before = engine.current?.id
        defer {
            requestsStarting -= 1
            if requestID == latestRequest { replacingQueueUntil = .now.addingTimeInterval(3) }
        }
        do {
            try await engine.play(request, context: context, shuffled: shuffled)
            // The music source changed while this was starting: the old player mustn't play.
            guard engine === self.engine else {
                engine.pause()
                return
            }
            if requestID == latestRequest {
                self.context = context
                // Anything else playing ends the live mix.
                if context.kind != .endless {
                    live = nil
                    liveGetsReady = false
                }
            }
        } catch {
            // A newer request, or another music source, took over: whatever this one ran into
            // is no longer anything to tell anyone.
            guard engine === self.engine, requestID == latestRequest else { return }
            // The queue may have been replaced before starting failed.
            if engine.current?.id != before { self.context = context }
            report(error)
        }
    }

    /// Play Next and Play Later. Starts playing if nothing is queued, and replaces a station,
    /// which has no queue to add to: songs added to it would be kept as radio.
    func enqueue(_ request: PlayRequest, next: Bool, title: String) {
        // Songs from the source switched to can't join the other's queue: they play instead.
        guard hasQueue, context?.isStation != true, nextEngine == nil else {
            play(request, from: .songs(title))
            return
        }
        problem = nil
        Task {
            do {
                try await engine.enqueue(request, next: next)
                confirm(next ? String(localized: "Playing Next") : String(localized: "Added to Queue"))
            } catch {
                report(error)
            }
        }
    }

    /// Adds to the end of the queue quietly, for songs still loading behind a playlist.
    func append(_ request: PlayRequest) {
        guard hasQueue else { return }
        Task { try? await engine.enqueue(request, next: false) }
    }

    func togglePlayPause() {
        guard waitingSession == nil else {
            resumeWaitingSession()
            return
        }
        let play = !isPlaying
        intendsToPlay = play
        if play {
            Task {
                do { try await engine.resume() } catch { report(error) }
            }
        } else {
            engine.pause()
        }
        settleIntent()
    }

    /// Lets the engine have the last word if it never reaches what was asked, so the button
    /// can't be left showing something that isn't happening.
    private func settleIntent() {
        let asked = intendsToPlay
        Task {
            try? await Task.sleep(for: .seconds(4))
            if intendsToPlay == asked { intendsToPlay = nil }
        }
    }

    func skipToNext() {
        guard waitingSession == nil else {
            resumeWaitingSession(startingAt: 1)
            return
        }
        Task {
            // On a live mix the next song may still be being picked: wait, rather than skip
            // off the end of the queue.
            if isLive, upNext.isEmpty, let livePick { await livePick.value }
            do { try await engine.skipToNext() } catch { report(error) }
        }
    }

    func skipToPrevious() {
        guard waitingSession == nil else {
            // Back to the start of the song, as Previous does part way through one.
            waitingSession?.time = 0
            return
        }
        isGoingBack = true
        Task {
            do { try await engine.skipToPrevious() } catch { report(error) }
            // Previous may only have restarted the song. Either way the next change is
            // the person's own again after a moment.
            try? await Task.sleep(for: .seconds(2))
            isGoingBack = false
        }
    }

    func seek(to time: TimeInterval) {
        guard waitingSession == nil else {
            waitingSession?.time = time
            return
        }
        engine.seek(to: time)
        lastSample = current.map { ($0.id, time) }
    }

    func toggleShuffle() {
        engine.setShuffled(!isShuffled)
    }

    func cycleRepeat() {
        engine.setRepeat(repeatMode.next)
    }

    /// A repeat mode by name, for a menu that lists them.
    func setRepeat(_ mode: PlayerRepeat) {
        engine.setRepeat(mode)
    }

    func jump(toUpNext index: Int) {
        guard waitingSession == nil else {
            resumeWaitingSession(startingAt: index + 1)
            return
        }
        Task {
            do { try await engine.jump(toUpNext: index) } catch { report(error) }
        }
    }

    func removeUpNext(at offsets: IndexSet) {
        if var waiting = waitingSession {
            // Up Next is everything after the first song.
            waiting.tracks.remove(atOffsets: IndexSet(offsets.map { $0 + 1 }))
            waitingSession = waiting
            upNext = Array(waiting.tracks.dropFirst())
            return
        }
        let removed = offsets.compactMap { upNext.indices.contains($0) ? upNext[$0] : nil }
        engine.removeUpNext(at: offsets)
        // On Motif Radio getting songs ready, one taken out is declined: it stops downloading,
        // counts against its artist as a skip would, and another takes its place.
        guard liveGetsReady, let radioDownloads else { return }
        for track in removed {
            radioDownloads.decline(HistorySong(track))
            live?.noteSkipped(track.songIdentity)
            waitingSince[track.songIdentity] = nil
        }
        topUpLiveIfNeeded()
    }

    func moveUpNext(from offsets: IndexSet, to destination: Int) {
        if var waiting = waitingSession {
            var ahead = Array(waiting.tracks.dropFirst())
            ahead.move(fromOffsets: offsets, toOffset: destination)
            waiting.tracks = Array(waiting.tracks.prefix(1)) + ahead
            waitingSession = waiting
            upNext = ahead
            return
        }
        engine.moveUpNext(from: offsets, to: destination)
    }

    // MARK: - Stations and the library

    /// A station made from a song, as Music's Create Station does.
    func playStation(from song: Song) {
        startStation(named: song.title) { try await song.with([.station]).station }
    }

    /// The artist's own station.
    func playStation(from artist: Artist) {
        startStation(named: artist.name) { try await artist.with([.station]).station }
    }

    private func startStation(named name: String, find: @escaping () async throws -> MusicKit.Station?) {
        problem = nil
        if sleepTimer == .endOfSong { sleepTimer = nil }
        Task {
            do {
                try await MusicKitPlayerEngine.checkAccess()
                guard let station = try await find() else {
                    problem = .failed(String(localized: "Apple Music doesn't have a station for \(name)."))
                    return
                }
                play(.station(station), from: PlayContext(kind: .station, title: station.name))
            } catch {
                report(error)
            }
        }
    }

    func addToLibrary(_ song: Song) {
        add { try await Self.addToAppleMusicLibrary(song) }
    }

    func addToLibrary(_ album: Album) {
        add {
            #if os(iOS)
            try await MusicLibrary.shared.add(album)
            #else
            try await Self.sendAddition(of: [album.id], as: .albums)
            #endif
        }
    }

    func addToLibrary(_ playlist: Playlist) {
        add {
            #if os(iOS)
            try await MusicLibrary.shared.add(playlist)
            #else
            try await Self.sendAddition(of: [playlist.id], as: .playlists)
            #endif
        }
    }

    /// MusicKit's own call on iPhone. The Mac doesn't have it, so it asks Apple Music the way
    /// Music does.
    private static func addToAppleMusicLibrary(_ song: Song) async throws {
        #if os(iOS)
        try await MusicLibrary.shared.add(song)
        #else
        try await sendAddition(of: [song.id], as: .songs)
        #endif
    }

    #if os(macOS)
    private static func sendAddition(of ids: [MusicItemID], as kind: AppleMusicLibraryAdd.Kind) async throws {
        // Already in the library, so there's nothing to ask for.
        guard let request = AppleMusicLibraryAdd.request(adding: ids.map(\.rawValue), as: kind) else { return }
        let response = try await MusicDataRequest(urlRequest: request).response()
        guard (200..<300).contains(response.urlResponse.statusCode) else {
            throw PlayerProblem.failed(String(localized: "Apple Music couldn't add this to your library. Try again in a moment."))
        }
    }
    #endif

    // MARK: - Favorites

    /// Which songs are Apple Music favorites, as far as Motif knows: looked up for the songs
    /// on screen, and changed by the star. Missing means not looked up yet.
    private(set) var favorites: [MusicItemID: Bool] = [:]
    @ObservationIgnored private var favoritesToLookUp: Set<MusicItemID> = []
    @ObservationIgnored private var favoritesLookUp: Task<Void, Never>?

    func isFavorite(_ song: Song) -> Bool {
        favorites[song.id] == true
    }

    /// Stars or unstars a song in Apple Music, as the star in Music does. A favorite is added
    /// to the library too, as Music adds them. Shown at once, and put back if it fails.
    func setFavorite(_ song: Song, _ isFavorite: Bool) {
        let was = favorites[song.id]
        favorites[song.id] = isFavorite
        // With sample data there's no Apple Music to tell; the star still shows what happens.
        guard !isDemo else { return }
        Task {
            do {
                try await MusicKitPlayerEngine.checkAccess()
                if isFavorite {
                    try await Self.addToAppleMusicLibrary(song)
                    try await Self.send(AppleMusicFavorites.favorite(songID: song.id.rawValue))
                } else {
                    try await Self.send(AppleMusicFavorites.unfavorite(songID: song.id.rawValue))
                }
            } catch {
                favorites[song.id] = was
                report(error)
            }
        }
    }

    /// Finds out whether a song on screen is already a favorite. Songs asked about together
    /// are looked up in one request.
    func lookUpFavorite(_ song: Song) {
        guard !isDemo, favorites[song.id] == nil else { return }
        favoritesToLookUp.insert(song.id)
        guard favoritesLookUp == nil else { return }
        favoritesLookUp = Task {
            try? await Task.sleep(for: .milliseconds(250))
            // Library songs are rated under another path, and every row here is from the catalog.
            let ids = favoritesToLookUp.filter { favorites[$0] == nil && !$0.rawValue.hasPrefix("i.") }
            favoritesToLookUp = []
            favoritesLookUp = nil
            let all = Array(ids)
            for start in stride(from: 0, to: all.count, by: 50) {
                let chunk = all[start..<min(start + 50, all.count)]
                guard let data = try? await Self.send(AppleMusicFavorites.ratings(songIDs: chunk.map(\.rawValue))) else { continue }
                let loved = AppleMusicFavorites.favoriteIDs(in: data)
                // A star tapped while this was out wins over what came back.
                for id in chunk where favorites[id] == nil {
                    favorites[id] = loved.contains(id.rawValue)
                }
            }
        }
    }

    @discardableResult
    private static func send(_ request: URLRequest) async throws -> Data {
        let response = try await MusicDataRequest(urlRequest: request).response()
        guard (200..<300).contains(response.urlResponse.statusCode) else {
            throw PlayerProblem.failed(String(localized: "Apple Music couldn't change this favorite. Try again in a moment."))
        }
        return response.data
    }

    private func add(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await MusicKitPlayerEngine.checkAccess()
                try await work()
                confirm(String(localized: "Added to Library"))
            } catch {
                report(error)
            }
        }
    }

    /// A short confirmation, shown over everything for a moment, like Music's.
    private(set) var confirmation: String?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    func confirm(_ message: String) {
        confirmation = message
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            confirmation = nil
        }
    }

    // MARK: - Sleep timer

    func setSleepTimer(_ timer: SleepTimer?) {
        sleepTimer = timer
        startTickerIfNeeded()
    }

    /// Time left on a timed sleep timer.
    func sleepRemaining(at date: Date = .now) -> TimeInterval? {
        guard case .at(let end) = sleepTimer else { return nil }
        return max(0, end.timeIntervalSince(date))
    }

    // MARK: - Signals

    func isSuggestingLess(_ songIdentity: String) -> Bool {
        signals.suggestLess.contains(songIdentity)
    }

    func setSuggestLess(_ songIdentity: String, _ isOn: Bool) {
        signals.setSuggestLess(songIdentity, isOn)
        signalsStore.save(signals)
        // A live mix hears it at once, as a skip of that artist.
        if isOn, context?.kind == .endless { live?.noteSkipped(songIdentity) }
        confirm(isOn ? String(localized: "Motif Will Suggest This Less") : String(localized: "Motif Will Suggest This Again"))
    }

    /// Forgets every skip and "suggest less".
    func resetSignals() {
        signals = ListeningSignals()
        signalsStore.save(signals)
    }

    // MARK: - Following the engine

    private func engineChanged() {
        if let waitingSession {
            guard engine.current != nil else {
                // Still waiting: the song left paused stands in for the engine's empty queue.
                current = waitingSession.tracks.first
                upNext = Array(waitingSession.tracks.dropFirst())
                status = .paused
                context = waitingSession.context
                isShuffled = engine.isShuffled
                repeatMode = engine.repeatMode
                return
            }
            // It's playing for real now. The stand-in wasn't a song being left.
            self.waitingSession = nil
            current = nil
        }
        let previous = current
        let next = engine.current
        var stoppedForSleep = false

        if let previous, previous.id != next?.id {
            noteLeaving(previous)
            removeIfPlayedOnce(previous)
            if sleepTimer == .endOfSong, next != nil {
                stopForSleep()
                stoppedForSleep = true
            }
        }

        // A live station can keep one entry while its song changes underneath it. The clock
        // starts when the song first actually plays, as the capture's does, not while it's
        // still loading: a song from a server can take seconds to arrive.
        if next?.id != previous?.id || next?.songIdentity != previous?.songIdentity {
            trackStartedAt = nil
        }
        status = engine.status
        if next != nil, status == .playing, trackStartedAt == nil {
            trackStartedAt = .now
        }
        if let intendsToPlay, (status == .playing) == intendsToPlay || status == .stopped {
            self.intendsToPlay = nil
        }
        current = next
        upNext = engine.upNext
        isShuffled = engine.isShuffled
        repeatMode = engine.repeatMode
        if next == nil {
            context = nil
            // Nothing left to reach the end of.
            if sleepTimer == .endOfSong { sleepTimer = nil }
        }
        // Not straight after the sleep timer stopped the music: a skip would start it again.
        if !stoppedForSleep { skipIfNotAllowed(next) }
        topUpLiveIfNeeded()
        startTickerIfNeeded()
        if previous?.id != next?.id || status != .playing { scheduleSave() }
    }

    // MARK: - Where you left off

    /// Opens on the song that was on when Motif last closed, paused where it was left, if
    /// Settings keeps it and it hasn't waited longer than Settings says to.
    func restoreLastSession() {
        guard !isDemo, current == nil, var session = LastSessionStore.load(),
              session.isYourMusic == (engine is LocalPlayerEngine)
        else { return }
        session.time = ResumePoint.time(leftAt: session.time, duration: session.tracks.first?.duration)
        waitingSession = session
        engineChanged()
    }

    /// Plays the song left paused, from where it was, or a later song of its queue.
    private func resumeWaitingSession(startingAt index: Int = 0) {
        guard let session = waitingSession, session.tracks.indices.contains(index) else { return }
        let tracks = session.tracks
        let request: PlayRequest
        if session.isYourMusic {
            request = .local(tracks.compactMap(\.local), startingAt: index)
        } else if !engine.playsByName, tracks.allSatisfy({ $0.song != nil }) {
            request = .songs(tracks.compactMap(\.song), startingAt: index)
        } else {
            request = .history(tracks.map {
                HistorySong(songID: $0.song?.id.rawValue ?? "", title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle)
            }, startingAt: index)
        }
        let time = index == 0 ? session.time : 0
        let context = session.context ?? .songs(String(localized: "Where You Left Off"))
        Task {
            await start(request, from: context)
            if time > 0, waitingSession == nil, current != nil { seek(to: time) }
        }
    }

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// Saves what's on a moment after it settles, so a run of changes is one write.
    private func scheduleSave() {
        guard !isDemo else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            saveSession()
        }
    }

    /// Keeps what's on, and how far into it, for the next launch. The app calls this as it
    /// goes to the background or quits; the player calls it as songs change and pause.
    func saveSession() {
        guard !isDemo else { return }
        pendingSave?.cancel()
        pendingSave = nil
        if var waiting = waitingSession {
            // Opened and left again: the wait starts over from now.
            waiting.savedAt = .now
            LastSessionStore.save(waiting)
            return
        }
        // Stations can't be picked up part way: the next launch starts with nothing on.
        guard let current, context?.isStation != true else {
            LastSessionStore.save(nil)
            return
        }
        LastSessionStore.save(LastSession(
            tracks: [current] + upNext.prefix(LastSession.keptAhead),
            time: engine.playbackTime,
            contextKind: context?.kind.storedName,
            contextTitle: context?.title,
            savedAt: .now
        ))
    }

    /// The source was switched while music played: the new player takes over now, as
    /// something from it is played.
    private func takeOverIfSwitched() {
        guard let nextEngine else { return }
        use(nextEngine)
    }

    // MARK: - Explicit songs on stations

    /// Explicit songs in a row skipped on a station. A station that only plays them gets
    /// paused rather than skipped through for good.
    @ObservationIgnored private var explicitSkipsInARow = 0
    /// The entry last skipped for being explicit, so it's skipped once.
    @ObservationIgnored private var explicitSkippedEntry: String?
    /// Set while Motif skips a song itself, so the skip isn't taken for the person's.
    @ObservationIgnored private var isAutoSkipping = false

    /// A station can't be filtered before it plays, so an explicit song it picks is skipped
    /// as it starts when explicit songs are off.
    ///
    /// Checked on every change, not just a new entry: a station's entry starts as a bare title
    /// and only says it's explicit once it resolves to its song a moment later.
    private func skipIfNotAllowed(_ track: PlayerTrack?) {
        guard let track, !PlayPreferences.allowsExplicit else { return }
        guard track.isExplicit else {
            // A resolved song that's fine ends the run of explicit ones.
            if track.song != nil { explicitSkipsInARow = 0 }
            return
        }
        guard explicitSkippedEntry != track.id else { return }
        explicitSkippedEntry = track.id
        explicitSkipsInARow += 1
        guard explicitSkipsInARow <= 5 else {
            explicitSkipsInARow = 0
            intendsToPlay = nil
            engine.pause()
            problem = .onlyExplicit
            return
        }
        isAutoSkipping = true
        Task { try? await engine.skipToNext() }
    }

    // MARK: - Live mixes

    /// What's picking the songs while Motif Radio or a mood plays. Nil for anything else.
    @ObservationIgnored private var live: LiveMix?
    /// The pick being queued, which a skip waits for rather than running off the end.
    @ObservationIgnored private var livePick: Task<Void, Never>?
    /// Counts picks, so one cancelled by a new listen doesn't clear the newer one's.
    @ObservationIgnored private var livePickCount = 0
    /// Builds Motif Radio from the history, with its tuning. Set by the app, which has both.
    @ObservationIgnored var makeMotifRadio: (() async -> LiveMix)?
    /// Notices driving, for Motif Radio's Drive mode.
    let drive = DriveDetector()
    /// The moment the Motif Radio playing was made for: the hour it follows, and whether it
    /// plays for the road.
    private(set) var radioMoment: RadioMoment = .anytime
    /// The genres Motif Radio's tuner offers, the ones you play most first. Kept ready by the
    /// app, so the tuner opens with them in place.
    var radioGenres: [String] = []
    /// Your own music, for Motif Radio to start with songs on this iPhone and get its new
    /// finds ready behind them. Set by the app.
    @ObservationIgnored weak var radioDownloads: (any RadioDownloads)? {
        didSet { radioDownloads?.onReady = { [weak self] in self?.songReady($0) } }
    }
    /// Whether the live mix playing does that: Motif Radio, from your own music, with its
    /// setting on.
    @ObservationIgnored private var liveGetsReady = false
    /// When each song waiting in Up Next to be ready was queued: one that's taken too long is
    /// let go, so the radio isn't held on it.
    @ObservationIgnored private var waitingSince: [String: Date] = [:]

    /// Whether the songs are being picked as they play, so Up Next only ever holds the next one.
    var isLive: Bool { context?.kind == .endless && hasQueue }

    var isPlayingMotifRadio: Bool { isLive && context == .motifRadio }

    /// Motif Radio is playing for the road: for its artwork and Now Playing to say so.
    var isRadioDriving: Bool { isPlayingMotifRadio && radioMoment.isDriving }

    /// An endless mix of everything you love, picked as it plays.
    func playMotifRadio() {
        Task { await startMotifRadio() }
    }

    /// ``playMotifRadio()``, returning once it has started or failed.
    func startMotifRadio() async {
        problem = nil
        guard PlayPreferences.isMotifRadioOn else {
            problem = .failed(String(localized: "Motif Radio is off. Turn it on in Settings, under Play."))
            return
        }
        guard let mix = await makeMotifRadio?(), !mix.isEmpty else {
            problem = .failed(String(localized: "Play a few songs first, and Motif Radio will have something to draw from."))
            return
        }
        await startLive(mix, from: .motifRadio)
    }

    /// For a shake: a song Motif thinks you'd like and haven't heard, then Motif Radio on from
    /// it. From your own music, a find that plays at once if there is one, so the shake answers
    /// straight away. Works with Motif Radio hidden too.
    ///
    /// Nothing is added to your library: the song just plays. Says nothing when it starts,
    /// since what's playing is its own answer (the iPhone opens Now Playing on it).
    /// - Returns: whether it started playing.
    @discardableResult
    func playSomethingNew() async -> Bool {
        guard let mix = await makeMotifRadio?(), !mix.isEmpty else {
            problem = .failed(String(localized: "Play a few songs first, and Motif will know what to find you."))
            return false
        }
        var picking = mix
        let ready: (MixSong) -> Bool = { [radioDownloads] song in
            guard MusicSource.current == .yourMusic, let radioDownloads else { return true }
            return radioDownloads.isReady(HistorySong(song))
        }
        guard let first = picking.next(newFinds: true, where: ready)
            ?? picking.next(newFinds: true, where: { _ in true })
            ?? picking.next()
        else { return false }
        await startLive(mix, from: .motifRadio, startingWith: first)
        return problem == nil && hasQueue
    }

    /// Applies a new tuning to Motif Radio while it plays, keeping what it has already picked
    /// and learned. The song queued next stays; the one after follows the new tuning.
    func retuneMotifRadio() async {
        guard isPlayingMotifRadio, let makeMotifRadio else { return }
        retunes += 1
        let retune = retunes
        var mix = await makeMotifRadio()
        guard !mix.isEmpty,
              // Only the latest tuning lands, and only on the radio still playing.
              retune == retunes, isPlayingMotifRadio, let current = live
        else { return }
        // What's been picked while the new mix was made, the song queued next included.
        mix.continueListen(from: current)
        live = mix
        radioMoment = mix.moment
    }

    /// Counts retunes, so one that finishes after a newer one is dropped.
    @ObservationIgnored private var retunes = 0

    /// Plays a live mix: the first song, and one more after it. Each song after that is picked
    /// as the one before starts, from what's been skipped and played through so far.
    /// - Parameter first: a song to start with, as when one is tapped on a mood's page.
    func startLive(_ mix: LiveMix, from context: PlayContext, startingWith first: MixSong? = nil) async {
        var mix = mix
        var songs: [MixSong] = []
        if let first {
            mix.note(picked: first.songIdentity)
            songs.append(first)
        }
        let getsReady = context == .motifRadio && MusicSource.current == .yourMusic && radioDownloads?.downloadsFirst == true
        // Songs that play at once to start with, so the radio begins without a wait.
        if getsReady, let radioDownloads {
            while songs.count < 2, let next = mix.next(where: { radioDownloads.isReady(HistorySong($0)) }) { songs.append(next) }
        }
        while songs.count < 2, let next = mix.next() { songs.append(next) }
        guard !songs.isEmpty else {
            problem = .nothingToPlay
            return
        }
        livePick?.cancel()
        livePick = nil
        live = mix
        radioMoment = context == .motifRadio ? mix.moment : .anytime
        liveGetsReady = getsReady
        waitingSince = [:]
        // Repeat has no place on a mix without an end, and its button isn't shown there.
        if repeatMode != .off { engine.setRepeat(.off) }
        await start(.history(songs.map(HistorySong.init)), from: PlayContext(kind: .endless, title: context.title))
        topUpLiveIfNeeded()
    }

    /// Picks the next song when there's none waiting after this one. Only one is queued ahead,
    /// so every pick knows about the song before it.
    private func topUpLiveIfNeeded() {
        followTheMoment()
        // The live mix's picks are for the queue on now, not one still replacing it.
        guard requestsStarting == 0 else { return }
        if liveGetsReady, let radioDownloads, context?.kind == .endless {
            topUpReadyFirst(radioDownloads)
            return
        }
        guard context?.kind == .endless, status != .loading, livePick == nil, let live,
              current != nil, !upNext.contains(where: { live.hasPicked($0.songIdentity) })
        else { return }
        livePickCount += 1
        let pickID = livePickCount
        livePick = Task {
            defer { if livePickCount == pickID { livePick = nil } }
            // A pick Apple Music can't play (gone, or explicit with those off) is passed over.
            for _ in 0..<5 {
                guard !Task.isCancelled, context?.kind == .endless, let song = self.live?.next() else { return }
                do {
                    try await engine.enqueue(.history([HistorySong(song)]), next: false)
                    return
                } catch {
                    continue
                }
            }
        }
    }

    /// Makes Motif Radio again once the moment it was made for has passed: the hour turned, or
    /// a drive started or ended. The song queued next stays; the one after fits the new moment.
    private func followTheMoment() {
        guard isPlayingMotifRadio, let live, live.moment != MotifRadioSource.moment(drive: drive) else { return }
        Task { await retuneMotifRadio() }
    }

    /// Up Next on Motif Radio getting songs ready: a song that plays at once comes next, and a
    /// new find is got ready behind it, moving up once it's here. Each is picked as the one
    /// before starts, from what's been skipped and played through so far.
    private func topUpReadyFirst(_ radio: any RadioDownloads) {
        guard livePick == nil, current != nil, live != nil else { return }
        livePickCount += 1
        let pickID = livePickCount
        livePick = Task {
            defer { if livePickCount == pickID { livePick = nil } }
            // Let go of a find that's waited too long: its server couldn't get it.
            let now = Date.now
            if let stale = upNext.indices.first(where: { index in
                waitingSince[upNext[index].songIdentity].map { now.timeIntervalSince($0) > Self.longestWait } ?? false
            }) {
                let track = upNext[stale]
                radio.decline(HistorySong(track))
                waitingSince[track.songIdentity] = nil
                engine.removeUpNext(at: IndexSet(integer: stale))
            }
            // Next, a song that plays at once, unless what's next already does.
            if upNext.first.map({ !radio.isReady(HistorySong($0)) }) ?? true {
                if let song = live?.next(where: { radio.isReady(HistorySong($0)) }) {
                    try? await engine.enqueue(.history([HistorySong(song)]), next: true)
                } else if upNext.isEmpty, let song = live?.next() {
                    // Nothing on this iPhone left to pick: the next song streams.
                    try? await engine.enqueue(.history([HistorySong(song)]), next: false)
                }
            }
            guard !Task.isCancelled, liveGetsReady else { return }
            // Behind it, a new find being got ready.
            if !upNext.contains(where: { !radio.isReady(HistorySong($0)) }),
               let find = live?.next(newFinds: true, where: { !radio.isReady(HistorySong($0)) }) {
                radio.prepare(HistorySong(find))
                waitingSince[find.songIdentity] = .now
                try? await engine.enqueue(.history([HistorySong(find)]), next: false)
            }
        }
    }

    /// A new find waiting in Up Next is ready: it plays next, rather than waiting behind the
    /// songs picked to play while it came down.
    private func songReady(_ identity: String) {
        guard liveGetsReady, waitingSince[identity] != nil,
              let position = upNext.firstIndex(where: { $0.songIdentity == identity })
        else { return }
        waitingSince[identity] = nil
        if position > 0 { engine.moveUpNext(from: IndexSet(integer: position), to: 0) }
        // Another find to get ready behind it.
        topUpLiveIfNeeded()
    }

    /// With Delete After Playing on, a find Motif Radio downloaded to play has its download
    /// removed once it's given way, and is kept a while in Up Next to keep after all.
    private func removeIfPlayedOnce(_ track: PlayerTrack) {
        guard context?.kind == .endless, let radioDownloads,
              radioDownloads.finishedPlaying(HistorySong(track))
        else { return }
        playedAndRemoved.removeAll { $0.songIdentity == track.songIdentity }
        playedAndRemoved.insert(track, at: 0)
        if playedAndRemoved.count > 8 { playedAndRemoved.removeLast() }
    }

    /// Keeps a song Motif Radio played and removed: downloaded again, and kept.
    func keepPlayed(_ track: PlayerTrack) {
        radioDownloads?.keep(HistorySong(track))
        playedAndRemoved.removeAll { $0.songIdentity == track.songIdentity }
        confirm(String(localized: "Keeping \u{201C}\(track.title)\u{201D}"))
    }

    /// How long a new find waits in Up Next to be ready before it's let go.
    private static let longestWait: TimeInterval = 20 * 60

    /// Tells the live mix how a song went, so the next picks follow.
    private func noteLive(_ track: PlayerTrack, skipped: Bool) {
        guard context?.kind == .endless else { return }
        if skipped { live?.noteSkipped(track.songIdentity) } else { live?.noteFinished(track.songIdentity) }
    }

    // MARK: - Saving

    /// Saves songs from the history to the Apple Music library as a new playlist.
    func saveAsPlaylist(named name: String, songs: [HistorySong]) {
        Task {
            do {
                try await MusicKitPlayerEngine.checkAccess()
                let found = try await MusicKitPlaybackService.songs(for: songs.map(\.songID).filter { !$0.isEmpty })
                guard !found.isEmpty else {
                    problem = .nothingToPlay
                    return
                }
                let description = String(localized: "Made by Motif from your listening.")
                #if os(iOS)
                _ = try await MusicLibrary.shared.createPlaylist(name: name, description: description, items: found)
                #else
                // MusicKit can't make a playlist on the Mac; the writer asks Apple Music directly.
                let writer = MusicKitPlaylistWriter()
                let playlistID = try await writer.createPlaylist(name: name, description: description)
                try await writer.addSongs(ids: found.map(\.id.rawValue), toPlaylist: playlistID)
                #endif
                confirm(String(localized: "Saved to Your Library"))
            } catch {
                report(error)
            }
        }
    }

    /// The sleep timer's moment: stop, and leave the next song at its start.
    private func stopForSleep() {
        sleepTimer = nil
        intendsToPlay = nil
        engine.pause()
        engine.seek(to: 0)
    }

    /// Records a skip when the song gave way early, and not because a new request replaced it.
    private func noteLeaving(_ track: PlayerTrack) {
        let wentBack = isGoingBack
        let autoSkipped = isAutoSkipping
        isGoingBack = false
        isAutoSkipping = false
        defer { lastSample = nil }
        guard !wentBack, !autoSkipped, Date.now > replacingQueueUntil, context?.isStation != true,
              let lastSample, lastSample.trackID == track.id
        else { return }
        let skipped = ListeningSignals.isSkip(playedFor: lastSample.time, duration: track.duration)
        noteLive(track, skipped: skipped)
        guard skipped else { return }
        signals.recordSkip(of: track.songIdentity)
        signalsStore.save(signals)
    }

    /// Samples the position once a second while playing, and checks the sleep timer. Stops
    /// when there's nothing to watch, so a paused player costs nothing.
    private func startTickerIfNeeded() {
        let needed = status == .playing || sleepTimer != nil
        guard needed else {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tick() {
        if let current, status == .playing {
            let time = engine.playbackTime
            // The same song back at its start after nearly finishing: Repeat One looped it,
            // which is the end of a song even though nothing changed.
            if sleepTimer == .endOfSong, let lastSample, lastSample.trackID == current.id,
               let duration = current.duration, lastSample.time > duration - 5, time < lastSample.time - 5 {
                self.lastSample = nil
                stopForSleep()
                return
            }
            lastSample = (current.id, time)
            // Now and then while playing, so a Mac that loses power, or an app that's ended
            // without warning, still picks up close to where it was.
            savesIn -= 1
            if savesIn <= 0 {
                savesIn = 30
                scheduleSave()
            }
        } else if sleepTimer == .endOfSong, status != .loading, upNext.isEmpty,
                  let current, let lastSample, lastSample.trackID == current.id,
                  let duration = current.duration, lastSample.time > duration - 3 {
            // The last song of the queue ran out: the timer has nothing left to wait for.
            sleepTimer = nil
        }
        if case .at(let end) = sleepTimer, Date.now >= end {
            sleepTimer = nil
            intendsToPlay = nil
            engine.pause()
        }
        if status != .playing, sleepTimer == nil {
            ticker?.cancel()
            ticker = nil
        }
    }

    /// Ticks until the next save while playing.
    @ObservationIgnored private var savesIn = 30

    private func report(_ error: any Error) {
        // Overtaken by something newer, which speaks for itself.
        if !(error is PlayerProblem), PlaybackFailure(error) == .superseded { return }
        intendsToPlay = nil
        problem = PlayerProblem(error)
    }
}

/// Keeps ``ListeningSignals`` on this device, in the app's own defaults.
struct SignalsStore {
    var defaults: UserDefaults = .standard
    static let key = "playListeningSignals"

    func load() -> ListeningSignals {
        guard let data = defaults.data(forKey: Self.key),
              let signals = try? JSONDecoder().decode(ListeningSignals.self, from: data)
        else { return ListeningSignals() }
        return signals
    }

    func save(_ signals: ListeningSignals) {
        guard let data = try? JSONEncoder().encode(signals) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
