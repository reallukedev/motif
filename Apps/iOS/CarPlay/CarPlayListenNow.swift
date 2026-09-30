import UIKit
import CarPlay
import MusicKit
import MotifCore

/// Listen Now: a few cards to start from, then a handful of shelves, so the tab is a short scan
/// of pictures rather than of words, as Music's is. Yours come first (what you played, your
/// mixes, your week), then a little of Apple Music's. Each image row carries its own name,
/// which gives it room above and below in the car's list.
extension CarPlaySceneDelegate {
    func listenNowSections() async -> [CPListSection] {
        let feed = model.playFeed
        let player = model.player
        let model = self.model
        listenNow.emptyViewTitleVariants = [String(localized: "Nothing Played Yet")]
        listenNow.emptyViewSubtitleVariants = [String(localized: "Pick a mood in Radio to start. Motif makes mixes from what you play.")]
        let isAppleMusic = model.musicSource == .appleMusic
        var sections: [CPListSection] = []

        // For You: where you left off, the mix for right now, Motif Radio (or Driving, until
        // there's enough listening for it) and Discover. Square covers on cards of their own
        // colour, as Music's, since a square cover can't fill a tall card without being
        // squashed. Each card has only its name, one line, so they all line up; the For You
        // page has each one's line.
        var cards: [(element: CPListImageRowItemCardElement, row: CarRow)] = []
        var carded: Set<String> = []
        let side = CPListImageRowItemCardElement.maximumImageSize.height
        // What was playing when Motif last closed, first: getting in the car is picking up.
        // The car's own Play button can't reach it, since Motif doesn't hand it to the player
        // until asked, so it doesn't take the audio from another app.
        if let waiting = player.waitingSession?.tracks.first {
            let image = await cover(for: waiting, side: side)
            let title = String(localized: "Continue")
            let card = CPListImageRowItemCardElement(image: image, showsImageFullHeight: false, title: title, subtitle: nil, tintColor: CarPlayImages.tint(of: image))
            // Only if it's still waiting: resumed some other way since, it's already playing.
            cards.append((card, CarRow(image: image, title: title, detail: "\(waiting.title) · \(waiting.artistName)") {
                if player.waitingSession != nil { player.togglePlayPause() }
            }))
        }
        if let lead = feed.mixes.rightNow ?? feed.mixes.mixes.first {
            cards.append(await card(for: lead, side: side))
            carded.insert(lead.id)
        }
        if hasMotifRadio {
            let image = await CarPlayImages.motifRadio(side: side, scale: scale)
            let title = String(localized: "Motif Radio")
            let card = CPListImageRowItemCardElement(
                image: image,
                showsImageFullHeight: false,
                title: title,
                subtitle: nil,
                // Deep, as the other cards are, so the tile stands on it rather than melting in.
                tintColor: CarPlayImages.tint(of: image)
            )
            cards.append((card, CarRow(image: image, title: title, detail: String(localized: "Your station, picked as you drive")) { [weak self] in
                await self?.startOrResumeMotifRadio()
            }))
        } else {
            // Before Motif Radio: the mood made for the car.
            let image = await CarPlayImages.mood(.drive, side: side, scale: scale)
            let title = Mood.drive.title
            let card = CPListImageRowItemCardElement(image: image, showsImageFullHeight: false, title: title, subtitle: nil, tintColor: CarPlayImages.tint(of: image))
            cards.append((card, CarRow(image: image, title: title, detail: String(localized: "Songs for the road")) { await MoodPlayback.start(.drive, model: model) }))
        }
        if isAppleMusic, let first = feed.discover.first {
            let art = first.artwork.map(CoverArt.artwork) ?? .url(nil, seed: first.title)
            let image = await CarPlayImages.cover(art, side: side, scale: scale)
            let songs = feed.discover
            let title = String(localized: "Discover")
            let card = CPListImageRowItemCardElement(image: image, showsImageFullHeight: false, title: title, subtitle: nil, tintColor: CarPlayImages.tint(of: image))
            cards.append((card, CarRow(image: image, title: title, detail: String(localized: "Songs new to you, by artists like the ones you love")) {
                await player.start(.songs(songs), from: PlayContext(kind: .mix, title: title), shuffled: true)
            }))
        }
        for mix in feed.mixes.otherTimes where cards.count < 6 {
            cards.append(await card(for: mix, side: side))
            carded.insert(mix.id)
        }
        if !cards.isEmpty {
            let title = String(localized: "For You")
            let row = CPListImageRowItem(text: title, cardElements: cards.map(\.element), allowsMultipleLines: false)
            // What the cards play, so a mix remade under the same name still reloads.
            row.userInfo = Self.contentToken(
                [player.waitingSession?.tracks.first?.id ?? ""]
                    + feed.mixes.all.flatMap { [$0.id] + $0.songs.map(\.songIdentity) }
                    + feed.discover.map(\.id.rawValue)
            )
            let rows = cards.map(\.row)
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard rows.indices.contains(index) else { return completion() }
                self?.play(rows[index].action, completion: completion)
            }
            // Its name opens it as a list, with each card's whole line.
            row.handler = { [weak self] _, completion in
                self?.openPage(title, rows)
                completion()
            }
            sections.append(CPListSection(items: [row]))
        }

        if isAppleMusic, let recent = await shelf(String(localized: "Recently Played"), feed.recentlyPlayed) {
            sections.append(recent)
        }

        // The rest of your mixes, each once. With your own music, only the ones enough of
        // whose songs you have.
        let yourMusic = model.yourMusic
        let mixes = feed.mixes.mixes.filter { mix in
            guard !carded.contains(mix.id) else { return false }
            guard !isAppleMusic else { return true }
            return mix.songs.lazy.filter { yourMusic.track(for: HistorySong($0)) != nil }.count >= 5
        }
        if !mixes.isEmpty {
            var items: [CPListItem] = []
            for mix in mixes {
                let image = await CarPlayImages.mix(mix, side: CPListItem.maximumImageSize.height, scale: scale)
                let item = CPListItem(text: mix.kind.title, detailText: mix.kind.tileLine, image: image)
                item.userInfo = Self.contentToken(mix.songs.map(\.songIdentity))
                item.isPlaying = isPlaying(mix.kind.title)
                let songs = player.songs(in: mix)
                item.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.history(songs), from: PlayContext(kind: .mix, title: mix.kind.title)) }, completion: completion)
                }
                items.append(item)
            }
            sections.append(CPListSection(items: items, header: String(localized: "Your Mixes"), sectionIndexTitle: nil))
        }

        sections += await weekSections()

        // A little of Apple Music's own: two of its picks for you and your artists' new
        // releases. Charts and genre shelves are for browsing, not the road.
        if isAppleMusic {
            for group in feed.recommendations.filter({ !$0.title.isEmpty && $0.items.count >= 3 }).prefix(2) {
                if let picks = await shelf(group.title, group.items) { sections.append(picks) }
            }
            if let releases = await shelf(String(localized: "New from Your Artists"), feed.newReleases) {
                sections.append(releases)
            }
        }
        return sections
    }

    private func card(for mix: Mix, side: CGFloat) async -> (element: CPListImageRowItemCardElement, row: CarRow) {
        // No symbol in the corner on a card: the card says what it is under the cover.
        let image = await CarPlayImages.mix(mix, side: side, scale: scale, badged: false)
        let songs = model.player.songs(in: mix)
        let player = model.player
        // Only the name fits a card; the mix's line is on the For You page.
        let card = CPListImageRowItemCardElement(image: image, showsImageFullHeight: false, title: mix.kind.title, subtitle: nil, tintColor: CarPlayImages.tint(of: image))
        return (card, CarRow(image: image, title: mix.kind.title, detail: mix.kind.tileLine) {
            await player.start(.history(songs), from: PlayContext(kind: .mix, title: mix.kind.title))
        })
    }

    /// A shelf of albums, playlists or stations: covers with their names under them, a tap
    /// from playing.
    private func shelf(_ title: String, _ all: [FeedItem]) async -> CPListSection? {
        // One line of covers: past that the car keeps the room and draws nothing. The
        // chevron has the rest.
        let items = Array(all.prefix(shelfLength))
        guard items.count >= 3, !title.isEmpty else { return nil }
        let player = model.player
        var tiles: [CPListImageRowItemImageGridElement] = []
        for item in items {
            let image = await CarPlayImages.cover(for: item, side: CPListImageRowItemImageGridElement.maximumImageSize.height, scale: scale)
            tiles.append(CPListImageRowItemImageGridElement(image: image, imageShape: .roundedRectangle, title: item.title, accessorySymbolName: nil))
        }
        let row = CPListImageRowItem(text: title, imageGridElements: tiles, allowsMultipleLines: false)
        row.userInfo = Self.contentToken(all.map(\.id))
        row.listImageRowHandler = { [weak self] _, index, completion in
            guard items.indices.contains(index) else { return completion() }
            let item = items[index]
            self?.play({ await Self.play(item, player: player) }, completion: completion)
        }
        let listed = Array(all.prefix(CPListTemplate.maximumItemCount))
        row.handler = { [weak self] _, completion in
            guard let self else { return completion() }
            Task {
                var rows: [CarRow] = []
                for item in listed {
                    let image = await CarPlayImages.cover(for: item, side: CPListItem.maximumImageSize.height, scale: scale)
                    rows.append(CarRow(image: image, title: item.title, detail: item.subtitle) { await Self.play(item, player: player) })
                }
                openPage(title, rows)
                completion()
            }
        }
        return CPListSection(items: [row])
    }

    // MARK: - Your week

    /// The week's top songs, a tap from playing down the chart, and the artists you've played
    /// most, round as Apple Music draws artists: the stats, as something to play.
    private func weekSections() async -> [CPListSection] {
        let (history, sessions) = (model.library.history, model.library.sessions)
        guard !history.isEmpty else { return [] }
        let (week, artistSongs) = await OffMainActor.run {
            let week = StatsCalculator.summary(range: .week, history: history, sessions: sessions, topLimit: 8)
            // Worked out here, off the main actor, since it walks the whole history.
            let songs = Dictionary(uniqueKeysWithValues: week.topArtists.prefix(6).map {
                ($0.id, Self.mostPlayed(byArtist: $0.id, in: history))
            })
            return (week, songs)
        }
        let player = model.player
        var sections: [CPListSection] = []

        let top = Array(week.topSongs.prefix(min(8, Int(CPMaximumNumberOfGridImages))))
        if top.count >= 3 {
            let songs = week.topSongs.map { HistorySong(songID: $0.songID, title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle, artworkURL: $0.artworkURL) }
            var elements: [CPListImageRowItemRowElement] = []
            for song in top {
                let image = await CarPlayImages.cover(url: song.artworkURL, seed: song.albumTitle ?? song.title, side: CPListImageRowItemRowElement.maximumImageSize.height, scale: scale)
                elements.append(CPListImageRowItemRowElement(image: image, title: song.title, subtitle: song.artistName))
            }
            let title = String(localized: "Top Songs This Week")
            let row = CPListImageRowItem(text: title, elements: elements, allowsMultipleLines: false)
            row.listImageRowHandler = { [weak self] _, index, completion in
                self?.play({ await player.start(.history(songs, startingAt: index), from: .songs(title)) }, completion: completion)
            }
            let chart = Array(week.topSongs.prefix(CPListTemplate.maximumItemCount))
            row.handler = { [weak self] _, completion in
                guard let self else { return completion() }
                Task {
                    var rows: [CarRow] = []
                    for (index, song) in chart.enumerated() {
                        let image = await CarPlayImages.cover(url: song.artworkURL, seed: song.albumTitle ?? song.title, side: CPListItem.maximumImageSize.height, scale: scale)
                        let plays = String(AttributedString(localized: "^[\(song.count) play](inflect: true)").characters)
                        rows.append(CarRow(image: image, title: "\(index + 1). \(song.title)", detail: "\(song.artistName) · \(plays)") {
                            await player.start(.history(songs, startingAt: index), from: .songs(title))
                        })
                    }
                    openPage(title, rows)
                    completion()
                }
            }
            sections.append(CPListSection(items: [row]))
        }

        let artists = Array(week.topArtists.prefix(6))
        if artists.count >= 3 {
            var elements: [CPListImageRowItemCondensedElement] = []
            for artist in artists {
                let image = await CarPlayImages.cover(url: artist.artworkURL, seed: artist.name, side: CPListImageRowItemCondensedElement.maximumImageSize.height, scale: scale)
                let plays = String(AttributedString(localized: "^[\(artist.count) play](inflect: true)").characters)
                elements.append(CPListImageRowItemCondensedElement(image: image, imageShape: .circular, title: artist.name, subtitle: plays, accessorySymbolName: nil))
            }
            // Not "On Repeat", which is a mix's name on the cards above.
            let title = String(localized: "Top Artists This Week")
            let row = CPListImageRowItem(text: title, condensedElements: elements, allowsMultipleLines: false)
            row.handler = { [weak self] _, completion in
                guard let self else { return completion() }
                Task {
                    var rows: [CarRow] = []
                    for artist in artists {
                        let image = await CarPlayImages.cover(url: artist.artworkURL, seed: artist.name, side: CPListItem.maximumImageSize.height, scale: scale)
                        let plays = String(AttributedString(localized: "^[\(artist.count) play](inflect: true)").characters)
                        let songs = artistSongs[artist.id] ?? []
                        rows.append(CarRow(image: image, title: artist.name, detail: "\(plays) · \(Format.listening(artist.listeningSeconds))") {
                            await player.start(.history(songs), from: PlayContext(kind: .artist, title: artist.name), shuffled: true)
                        })
                    }
                    openPage(title, rows)
                    completion()
                }
            }
            row.listImageRowHandler = { [weak self] _, index, completion in
                guard artists.indices.contains(index) else { return completion() }
                let artist = artists[index]
                let songs = artistSongs[artist.id] ?? []
                self?.play({ await player.start(.history(songs), from: PlayContext(kind: .artist, title: artist.name), shuffled: true) }, completion: completion)
            }
            sections.append(CPListSection(items: [row]))
        }
        return sections
    }

    /// An artist's songs, most played first, for playing them from the week's row.
    nonisolated private static func mostPlayed(byArtist identity: String, in history: ListeningHistory) -> [HistorySong] {
        var plays: [String: (count: Int, song: HistorySong)] = [:]
        for capture in history.captures where capture.artistIdentity == identity && !capture.songID.isEmpty {
            let song = HistorySong(songID: capture.songID, title: capture.title, artistName: capture.artistName, albumTitle: capture.albumTitle, artworkURL: capture.artworkURL)
            plays[capture.songIdentity] = ((plays[capture.songIdentity]?.count ?? 0) + 1, song)
        }
        return plays.values.sorted { $0.count > $1.count }.prefix(40).map(\.song)
    }

    // MARK: - Pages

    /// A shelf's page: everything on it as rows, each with its whole line, a tap from playing.
    func openPage(_ title: String, _ rows: [CarRow]) {
        let items = rows.map { row in
            let item = CPListItem(text: row.title, detailText: row.detail, image: row.image)
            item.handler = { [weak self] _, completion in
                self?.play(row.action, completion: completion)
            }
            return item
        }
        interface?.pushTemplate(CPListTemplate(title: title, sections: [CPListSection(items: items)]), animated: true, completion: nil)
    }

    // MARK: - Feed items

    /// Plays a station, album or playlist from the feed or the library, whole.
    static func play(_ item: FeedItem, player: PlayerModel) async {
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
}

/// A row on a shelf's page: its picture, its name, its line, and what a tap plays.
struct CarRow {
    let image: UIImage
    let title: String
    let detail: String?
    let action: () async -> Void
}
