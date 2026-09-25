import UIKit
import CarPlay
import MusicKit
import MotifCore

/// Motif in the car: four tabs made for a glance and one tap.
///
/// Listen Now leads with the same For You cards as the phone, then your mixes and what you
/// played last. Radio has Motif Radio and Apple's live stations.
/// Library has your playlists and newest albums. Insights has the week's top artists and songs,
/// each a tap from playing. Everything in the car is something to play: CarPlay is for audio.
///
/// Everything plays through the same player as the phone, so every song is kept.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    private var interface: CPInterfaceController?
    private var scale: CGFloat = 2
    private let model = AppModel.shared
    private var watch: Task<Void, Never>?
    private var refresh: Task<Void, Never>?
    /// What the Library tab was last built for: the source, and Apple Music access or the
    /// size of your own library.
    private var libraryBuiltFor: String?

    private lazy var listenNow = tab(String(localized: "Listen Now"), symbol: "play.circle")
    private lazy var radio = tab(String(localized: "Radio"), symbol: "dot.radiowaves.left.and.right")
    private lazy var library = tab(String(localized: "Library"), symbol: "music.note.list")
    private lazy var insights = tab(String(localized: "Insights"), symbol: "chart.bar.xaxis")

    // MARK: - Connecting

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        scale = interfaceController.carTraitCollection.displayScale
        configureNowPlaying()
        let tabs = CPTabBarTemplate(templates: [listenNow, radio, library, insights])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)

        // The car can start Motif with no phone window, so nothing else has started capture.
        Task { await model.startCapture() }
        Task {
            await model.prepareForPlaying()
            rebuild()
            await model.playFeed.loadAppleMusic()
            await model.playFeed.loadFromYourArtists()
            rebuild()
        }
        watch = Task { [weak self] in
            guard let model = self?.model else { return }
            let (feed, library, yourMusic) = (model.playFeed, model.library, model.yourMusic)
            let changes = Observations {
                ContentKey(
                    revision: library.revision,
                    mixes: feed.mixes.all.map(\.id),
                    shelves: (feed.recentlyPlayed + feed.liveStations).map(\.id),
                    discover: feed.discover.count,
                    source: model.musicSource,
                    yourMusic: yourMusic.index.tracks.count
                )
            }
            for await _ in changes {
                self?.rebuild()
            }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        watch?.cancel()
        refresh?.cancel()
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
    }

    private struct ContentKey: Equatable {
        let revision: Int
        let mixes: [String]
        let shelves: [String]
        let discover: Int
        let source: MusicSource
        let yourMusic: Int
    }

    private func tab(_ title: String, symbol: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: symbol)
        template.emptyViewTitleVariants = [String(localized: "Loading…")]
        return template
    }

    /// Rebuilds every tab, a moment after the last change, since a capture changes the
    /// history, the mixes and the stats one after another.
    private func rebuild() {
        refresh?.cancel()
        refresh = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let listen = await listenNowSections()
            guard !Task.isCancelled else { return }
            listenNow.updateSections(listen)
            let stations = await radioSections()
            guard !Task.isCancelled else { return }
            radio.updateSections(stations)
            let week = await insightsSections()
            guard !Task.isCancelled else { return }
            insights.updateSections(week)
            // The Apple Music library doesn't change with a capture: once, and again if access
            // changes.
            let key = model.musicSource == .yourMusic
                ? "yourMusic.\(model.yourMusic.index.albums.count)"
                : "appleMusic.\(MusicAuthorization.currentStatus)"
            if libraryBuiltFor != key {
                let shelves = model.musicSource == .yourMusic ? await yourMusicSections() : await librarySections()
                guard !Task.isCancelled else { return }
                library.updateSections(shelves)
                libraryBuiltFor = key
            }
        }
    }

    // MARK: - Listen Now

    private func listenNowSections() async -> [CPListSection] {
        let feed = model.playFeed
        let player = model.player
        guard !model.library.history.isEmpty || !feed.recentlyPlayed.isEmpty else {
            listenNow.emptyViewTitleVariants = [String(localized: "Nothing Played Yet")]
            listenNow.emptyViewSubtitleVariants = [String(localized: "Motif makes mixes from what you play. Try the Radio tab.")]
            return []
        }
        var sections: [CPListSection] = []

        // For You: the phone's cards, as CarPlay's large cards.
        var cards: [(element: CPListImageRowItemCardElement, action: () async -> Void)] = []
        let cardSide = CPListImageRowItemCardElement.maximumFullHeightImageSize
        if let lead = feed.mixes.rightNow ?? feed.mixes.mixes.first {
            cards.append(await card(for: lead, side: cardSide))
        }
        if PlayPreferences.isMotifRadioOn, model.library.history.captures.count >= 20 {
            let covers = (feed.mixes.mixes.first { $0.kind == .allTimeFavorites } ?? feed.mixes.all.first)?.covers ?? []
            let image = await CarPlayImages.mosaic(covers, side: cardSide.height, scale: scale)
            cards.append((
                CPListImageRowItemCardElement(image: image, showsImageFullHeight: true, title: String(localized: "Motif Radio"), subtitle: String(localized: "Your station"), tintColor: nil),
                { await player.startMotifRadio() }
            ))
        }
        if model.musicSource == .appleMusic, !feed.discover.isEmpty, let first = feed.discover.first {
            let image = await CarPlayImages.cover(first.artwork.map(CoverArt.artwork) ?? .url(nil, seed: first.title), side: cardSide.height, scale: scale)
            let songs = feed.discover
            cards.append((
                CPListImageRowItemCardElement(image: image, showsImageFullHeight: true, title: String(localized: "Discover"), subtitle: String(localized: "New to you"), tintColor: nil),
                { await player.start(.songs(songs), from: PlayContext(kind: .mix, title: String(localized: "Discover")), shuffled: true) }
            ))
        }
        for mix in feed.mixes.otherTimes {
            cards.append(await card(for: mix, side: cardSide))
        }
        if !cards.isEmpty {
            let row = CPListImageRowItem(text: String(localized: "For You"), cardElements: cards.map(\.element), allowsMultipleLines: false)
            let actions = cards.map(\.action)
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard actions.indices.contains(index) else { return completion() }
                self?.play(actions[index], completion: completion)
            }
            sections.append(CPListSection(items: [row]))
        }

        // With your own music, only the mixes enough of whose songs you have.
        let yourMusic = model.yourMusic
        let mixes = model.musicSource == .appleMusic
            ? feed.mixes.mixes
            : feed.mixes.mixes.filter { mix in mix.songs.lazy.filter { yourMusic.track(for: HistorySong($0)) != nil }.count >= 5 }
        if !mixes.isEmpty {
            var items: [CPListItem] = []
            for mix in mixes {
                let image = await CarPlayImages.mosaic(mix.covers, side: CPListItem.maximumImageSize.height, scale: scale)
                let item = CPListItem(text: mix.kind.title, detailText: mix.kind.tileLine, image: image)
                let songs = player.songs(in: mix)
                item.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.history(songs), from: PlayContext(kind: .mix, title: mix.kind.title)) }, completion: completion)
                }
                items.append(item)
            }
            sections.append(CPListSection(items: items, header: String(localized: "Made from Your Listening"), sectionIndexTitle: nil))
        }

        if model.musicSource == .appleMusic, !feed.recentlyPlayed.isEmpty {
            sections.append(CPListSection(
                items: await items(for: Array(feed.recentlyPlayed.prefix(8))),
                header: String(localized: "Recently Played"),
                sectionIndexTitle: nil
            ))
        }

        // Moods last, and only as many as the car's list has room for, so they never push
        // what you played off the end.
        let model = self.model
        let room = CPListTemplate.maximumItemCount - sections.reduce(0) { $0 + $1.items.count }
        let moods = Mood.allCases.prefix(max(0, room)).map { mood in
            let item = CPListItem(text: mood.title, detailText: nil, image: CarPlayImages.symbol(mood.symbol, tint: UIColor(mood.color)))
            item.handler = { [weak self] _, completion in
                self?.play({ await MoodPlayback.start(mood, model: model) }, completion: completion)
            }
            return item
        }
        if !moods.isEmpty {
            sections.append(CPListSection(items: moods, header: String(localized: "Moods"), sectionIndexTitle: nil))
        }
        return sections
    }

    private func card(for mix: Mix, side: CGSize) async -> (element: CPListImageRowItemCardElement, action: () async -> Void) {
        let image = await CarPlayImages.mosaic(mix.covers, side: side.height, scale: scale)
        let songs = model.player.songs(in: mix)
        let player = model.player
        return (
            CPListImageRowItemCardElement(image: image, showsImageFullHeight: true, title: mix.kind.title, subtitle: mix.kind.tileLine, tintColor: nil),
            { await player.start(.history(songs), from: PlayContext(kind: .mix, title: mix.kind.title)) }
        )
    }

    // MARK: - Radio

    private func radioSections() async -> [CPListSection] {
        let feed = model.playFeed
        let player = model.player
        var sections: [CPListSection] = []

        if PlayPreferences.isMotifRadioOn, model.library.history.captures.count >= 20 {
            let station = CPListItem(
                text: String(localized: "Motif Radio"),
                detailText: String(localized: "Your station, picked as it plays"),
                image: CarPlayImages.symbol("dot.radiowaves.left.and.right")
            )
            station.handler = { [weak self] _, completion in
                self?.play({ await player.startMotifRadio() }, completion: completion)
            }
            sections.append(CPListSection(items: [station]))
        }
        // Apple's stations only play from Apple Music.
        guard model.musicSource == .appleMusic else {
            if sections.isEmpty {
                radio.emptyViewTitleVariants = [String(localized: "Motif Radio Is Off")]
                radio.emptyViewSubtitleVariants = [String(localized: "Turn it on in Motif's settings to play your own station here.")]
            }
            return sections
        }
        if !feed.liveStations.isEmpty {
            sections.append(CPListSection(items: await items(for: feed.liveStations), header: String(localized: "Live"), sectionIndexTitle: nil))
        }
        if sections.isEmpty {
            radio.emptyViewTitleVariants = [String(localized: "No Stations Yet")]
            radio.emptyViewSubtitleVariants = [String(localized: "Motif needs Apple Music access to play radio.")]
        }
        return sections
    }

    // MARK: - Library

    private func librarySections() async -> [CPListSection] {
        guard MusicAuthorization.currentStatus == .authorized, !model.isDemoLaunch else {
            library.emptyViewTitleVariants = [String(localized: "Library Unavailable")]
            library.emptyViewSubtitleVariants = [String(localized: "Motif needs Apple Music access to show your library.")]
            return []
        }
        var sections: [CPListSection] = []

        var playlistRequest = MusicLibraryRequest<Playlist>()
        playlistRequest.sort(by: \.lastPlayedDate, ascending: false)
        playlistRequest.limit = 20
        if let playlists = try? await playlistRequest.response().items, !playlists.isEmpty {
            sections.append(CPListSection(
                items: await items(for: playlists.map(FeedItem.init(playlist:))),
                header: String(localized: "Playlists"),
                sectionIndexTitle: nil
            ))
        }

        var albumRequest = MusicLibraryRequest<Album>()
        albumRequest.sort(by: \.libraryAddedDate, ascending: false)
        albumRequest.limit = 12
        if let albums = try? await albumRequest.response().items, !albums.isEmpty {
            sections.append(CPListSection(
                items: await items(for: FeedItem.versions(albums.map(FeedItem.init(album:)))),
                header: String(localized: "Recently Added"),
                sectionIndexTitle: nil
            ))
        }
        if sections.isEmpty {
            library.emptyViewTitleVariants = [String(localized: "Nothing in Your Library")]
        }
        return sections
    }

    /// Your own music's albums: the ones added lately, then every one, as far as the car allows.
    private func yourMusicSections() async -> [CPListSection] {
        let music = model.yourMusic
        let player = model.player
        guard !music.index.isEmpty else {
            library.emptyViewTitleVariants = [String(localized: "No Music Yet")]
            library.emptyViewSubtitleVariants = [String(localized: "Add songs or connect a server in Motif on your iPhone.")]
            return []
        }
        func rows(_ albums: [LocalAlbum]) async -> [CPListItem] {
            var rows: [CPListItem] = []
            for album in albums {
                let image = await CarPlayImages.cover(
                    url: music.artworkURL(album.artwork)?.absoluteString,
                    seed: album.title,
                    side: CPListItem.maximumImageSize.height,
                    scale: scale
                )
                let item = CPListItem(text: album.title, detailText: album.artist, image: image)
                let tracks = album.tracks
                item.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.local(tracks.filter(music.isPlayable)), from: PlayContext(kind: .album, title: album.title)) }, completion: completion)
                }
                rows.append(item)
            }
            return rows
        }
        let recent = Array(music.index.recentlyAdded.prefix(12))
        let room = max(0, CPListTemplate.maximumItemCount - recent.count)
        let everything = music.index.albums.filter { album in !recent.contains { $0.id == album.id } }.prefix(room)
        return [
            CPListSection(items: await rows(recent), header: String(localized: "Recently Added"), sectionIndexTitle: nil),
            CPListSection(items: await rows(Array(everything)), header: String(localized: "Albums"), sectionIndexTitle: nil),
        ].filter { !$0.items.isEmpty }
    }

    /// Rows for stations, albums and playlists. In the car they all play at a tap.
    private func items(for feedItems: [FeedItem]) async -> [CPListItem] {
        let player = model.player
        var items: [CPListItem] = []
        for feedItem in feedItems {
            let image = await CarPlayImages.cover(feedItem.cover, side: CPListItem.maximumImageSize.height, scale: scale)
            let item = CPListItem(text: feedItem.title, detailText: feedItem.subtitle, image: image)
            item.isExplicitContent = feedItem.isExplicit
            item.handler = { [weak self] _, completion in
                self?.play({ await Self.play(feedItem, player: player) }, completion: completion)
            }
            items.append(item)
        }
        return items
    }

    private static func play(_ item: FeedItem, player: PlayerModel) async {
        switch item.content {
        case .station, .demoStation:
            if let (request, context) = item.stationRequest {
                await player.start(request, from: context)
            }
        case .album(let album):
            await player.start(.album(album), from: PlayContext(kind: .album, title: album.title))
        case .playlist(let playlist):
            await player.start(.playlist(playlist), from: PlayContext(kind: .playlist, title: playlist.name))
        }
    }

    // MARK: - Insights

    private func insightsSections() async -> [CPListSection] {
        let (history, sessions) = (model.library.history, model.library.sessions)
        guard !history.isEmpty else {
            insights.emptyViewTitleVariants = [String(localized: "No Listening Yet")]
            insights.emptyViewSubtitleVariants = [String(localized: "Your week shows up here as you listen.")]
            return []
        }
        let (week, artistSongs) = await OffMainActor.run {
            let week = StatsCalculator.summary(range: .week, history: history, sessions: sessions, topLimit: 5)
            // Each top artist's most played songs, for playing them at a tap. Worked out here,
            // off the main actor, since it walks the whole history.
            let songs = Dictionary(uniqueKeysWithValues: week.topArtists.prefix(5).map {
                ($0.id, Self.mostPlayed(byArtist: $0.id, in: history))
            })
            return (week, songs)
        }
        var sections: [CPListSection] = []

        // Top artists: a tap plays your most played songs by them.
        if !week.topArtists.isEmpty {
            var rows: [CPListItem] = []
            for artist in week.topArtists.prefix(5) {
                let image = await CarPlayImages.cover(url: artist.artworkURL, seed: artist.name, side: CPListItem.maximumImageSize.height, scale: scale)
                let plays = String(AttributedString(localized: "^[\(artist.count) play](inflect: true)").characters)
                let row = CPListItem(text: artist.name, detailText: "\(plays) · \(Format.listening(artist.listeningSeconds))", image: image)
                let songs = artistSongs[artist.id] ?? []
                let player = model.player
                row.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.history(songs), from: PlayContext(kind: .artist, title: artist.name), shuffled: true) }, completion: completion)
                }
                rows.append(row)
            }
            // The week's total rides in the first header: a fact to glance at, on a list you play.
            let header = String(localized: "Top Artists · \(Format.listening(week.listeningSeconds)) This Week")
            sections.append(CPListSection(items: rows, header: header, sectionIndexTitle: nil))
        }

        // Top songs: a tap plays down the chart from there.
        if !week.topSongs.isEmpty {
            let songs = week.topSongs.map { HistorySong(songID: $0.songID, title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle, artworkURL: $0.artworkURL) }
            var rows: [CPListItem] = []
            for (index, song) in week.topSongs.prefix(5).enumerated() {
                let image = await CarPlayImages.cover(url: song.artworkURL, seed: song.albumTitle ?? song.title, side: CPListItem.maximumImageSize.height, scale: scale)
                let plays = String(AttributedString(localized: "^[\(song.count) play](inflect: true)").characters)
                let row = CPListItem(text: song.title, detailText: "\(song.artistName) · \(plays)", image: image)
                let player = model.player
                row.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.history(songs, startingAt: index), from: .songs(String(localized: "Top Songs This Week"))) }, completion: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Top Songs This Week"), sectionIndexTitle: nil))
        }
        return sections
    }

    /// An artist's songs, most played first, for playing them from Insights.
    nonisolated private static func mostPlayed(byArtist identity: String, in history: ListeningHistory) -> [HistorySong] {
        var plays: [String: (count: Int, song: HistorySong)] = [:]
        for capture in history.captures where capture.artistIdentity == identity && !capture.songID.isEmpty {
            let song = HistorySong(songID: capture.songID, title: capture.title, artistName: capture.artistName, albumTitle: capture.albumTitle, artworkURL: capture.artworkURL)
            plays[capture.songIdentity] = ((plays[capture.songIdentity]?.count ?? 0) + 1, song)
        }
        return plays.values.sorted { $0.count > $1.count }.prefix(40).map(\.song)
    }

    // MARK: - Playing

    /// Plays, then shows Now Playing, or says what went wrong.
    private func play(_ action: @escaping () async -> Void, completion: @escaping () -> Void) {
        // Asking for Apple Music access from the car would put a prompt on a phone no one is
        // looking at, and leave the row spinning. Decided here, not from a problem left over
        // from the phone, which would otherwise stop every row playing.
        let needsAccess = !model.isDemoLaunch && model.musicSource == .appleMusic
            && MusicAuthorization.currentStatus != .authorized
        model.player.problem = needsAccess ? .accessDenied : nil
        Task { [weak self] in
            if !needsAccess { await action() }
            completion()
            guard let self else { return }
            if let problem = model.player.problem {
                model.player.problem = nil
                let alert = CPAlertTemplate(
                    titleVariants: [problem.title],
                    actions: [CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                        self?.interface?.dismissTemplate(animated: true, completion: nil)
                    }]
                )
                interface?.presentTemplate(alert, animated: true, completion: nil)
            } else if !(interface?.topTemplate is CPNowPlayingTemplate) {
                interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
        }
    }

    // MARK: - Now Playing

    private func configureNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.add(self)
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = String(localized: "Up Next")
        let player = model.player
        var buttons: [CPNowPlayingButton] = [
            CPNowPlayingShuffleButton { _ in player.toggleShuffle() },
            CPNowPlayingRepeatButton { _ in player.cycleRepeat() },
        ]
        if let image = UIImage(systemName: "hand.thumbsdown") {
            // "Not for me": out of the mixes, and on to the next song.
            buttons.append(CPNowPlayingImageButton(image: image) { _ in
                guard let track = player.current else { return }
                player.setSuggestLess(track.songIdentity, true)
                player.skipToNext()
            })
        }
        if let image = UIImage(systemName: "plus") {
            buttons.append(CPNowPlayingImageButton(image: image) { _ in
                if let song = player.current?.song { player.addToLibrary(song) }
            })
        }
        nowPlaying.updateNowPlayingButtons(buttons)
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        let player = model.player
        let items = player.upNext.prefix(40).map { track in
            let item = CPListItem(text: track.title, detailText: track.artistName)
            item.isExplicitContent = track.isExplicit
            item.handler = { [weak self] _, completion in
                // By the song, not its place: the queue may have moved on since the list opened.
                if let index = player.upNext.firstIndex(where: { $0.id == track.id }) {
                    player.jump(toUpNext: index)
                }
                completion()
                self?.interface?.popTemplate(animated: true, completion: nil)
            }
            return item
        }
        let queue = CPListTemplate(title: String(localized: "Up Next"), sections: [CPListSection(items: items)])
        queue.emptyViewTitleVariants = [
            player.context?.isStation == true ? String(localized: "A Station Picks as It Goes")
                : player.isLive ? String(localized: "Picking the Next Song")
                : String(localized: "Nothing Queued"),
        ]
        interface?.pushTemplate(queue, animated: true, completion: nil)
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {}
}
