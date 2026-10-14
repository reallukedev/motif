import SwiftUI
import TracksCore

/// Your listening history searched, laid out as the other scopes are: the best match, the
/// songs, then the artists and albums. Each opens its page of stats. Before you type, what you
/// searched lately and who and what you play most.
struct HistorySearchResults: View {
    let query: String
    /// Puts a recent search back in the field.
    let search: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openRoute
    @AppStorage("recentHistorySearches") private var recentStorage = ""
    @State private var results = SearchResults.empty
    /// The query `results` answer, so No Results waits for the current one.
    @State private var answeredQuery: String?
    @State private var topArtists: [ArtistTally] = []
    @State private var topAlbums: [AlbumTally] = []
    /// Built once per change to the history, so each letter typed only filters it.
    @State private var index: SearchIndex?
    /// Bumped as each new index lands, so results on screen are searched again.
    @State private var indexGeneration = 0
    @State private var showsAllSongs = false

    private static let songsShown = 8

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                if isBlank {
                    blank
                } else {
                    // What was found last stays while the next search runs, so typing never blinks.
                    resultSections
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay { overlay }
        // A play that just finished, or one deleted or synced in, shows up in results already
        // on screen.
        .task(id: model.library.revision) {
            let history = model.library.history
            let next = await OffMainActor.run { SearchIndex(history: history) }
            guard !Task.isCancelled else { return }
            index = next
            indexGeneration += 1
            topArtists = next.topArtists(limit: 10)
            topAlbums = next.topAlbums(limit: 10)
        }
        .task(id: SearchKey(query: query, indexGeneration: indexGeneration)) {
            guard let index else { return }
            let query = query
            if !isBlank {
                // A short pause so typing doesn't search on every letter.
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            let next = await OffMainActor.run { index.search(query) }
            guard !Task.isCancelled else { return }
            results = next
            answeredQuery = query
        }
        .onChange(of: query) { showsAllSongs = false }
    }

    // MARK: - Before searching

    @ViewBuilder
    private var blank: some View {
        if !recents.isEmpty {
            RecentSearchesSection(recents: recents, clear: { recentStorage = "" }, search: search) {
                recentStorage = RecentSearches.removing($0, from: recentStorage)
            }
        }
        if !topArtists.isEmpty {
            Shelf(title: String(localized: "Your Top Artists"), items: topArtists) { artist in
                artistTile(artist)
            }
        }
        if !topAlbums.isEmpty {
            Shelf(title: String(localized: "Your Top Albums"), items: topAlbums) { album in
                albumTile(album)
            }
        }
    }

    // MARK: - Results

    private var topKind: SearchTopKind? {
        SearchRanking.topKind(
            for: query,
            artist: results.artists.first?.name,
            album: results.albums.first?.title,
            song: results.songs.first?.title
        )
    }

    @ViewBuilder
    private var resultSections: some View {
        let kind = topKind
        let top = kind.flatMap(card)
        // The top result's song isn't listed again under it.
        let songs = kind == .song ? Array(results.songs.dropFirst()) : results.songs
        let shownSongs = showsAllSongs ? songs : Array(songs.prefix(Self.songsShown))
        SearchLead(top: top, hasSongs: !shownSongs.isEmpty) {
            songsTitle(total: songs.count)
        } songs: {
            songRows(shownSongs, all: results.songs)
        }

        let artists = kind == .artist ? Array(results.artists.dropFirst()) : results.artists
        if !artists.isEmpty {
            Shelf(title: String(localized: "Artists"), items: Array(artists.prefix(10))) { artist in
                artistTile(artist)
            }
        }
        let albums = kind == .album ? Array(results.albums.dropFirst()) : results.albums
        if !albums.isEmpty {
            Shelf(title: String(localized: "Albums"), items: Array(albums.prefix(10))) { album in
                albumTile(album)
            }
        }
    }

    private func songsTitle(total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SearchSectionTitle("Songs")
            Spacer()
            if total > Self.songsShown {
                Button(showsAllSongs ? "Show Less" : "See All") {
                    withAnimation(PlayMotion.panel) { showsAllSongs.toggle() }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.tint)
            }
        }
    }

    /// Songs that open their stats; their menus play them.
    private func songRows(_ shown: [SongTally], all: [SongTally]) -> some View {
        SearchSongGrid(items: shown) { song in
            Button {
                remember()
                push(.song(song.id))
            } label: {
                TrackRow(
                    title: song.title,
                    subtitle: [song.artistName, song.albumTitle].compactMap(\.self).joined(separator: " · "),
                    cover: .url(song.artworkURL, seed: song.albumTitle ?? song.title),
                    isCurrent: player.current?.songIdentity == song.id
                )
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                HistorySongMenu(song: MixSong(tally: song)) { play(all, from: song) }
            }
        }
    }

    private func artistTile(_ artist: ArtistTally) -> some View {
        Button {
            remember()
            push(.artist(artist.id))
        } label: {
            VStack(spacing: 8) {
                ArtistPicture(cover: artist.artworkURL.map { .url($0, seed: artist.name) }, name: artist.name, size: 120)
                Text(artist.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 120)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(artist.name)
    }

    private func albumTile(_ album: AlbumTally) -> some View {
        Button {
            remember()
            push(.album(album.id))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoverImage(cover: .url(album.artworkURL, seed: album.title), size: PlayMetrics.tile)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(album.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: PlayMetrics.tile, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The top result

    private func card(for kind: SearchTopKind) -> SearchTopResult? {
        switch kind {
        case .artist:
            guard let artist = results.artists.first else { return nil }
            let name = StatsCalculator.folded(artist.name)
            let theirs = results.songs.filter { StatsCalculator.folded($0.artistName) == name }
            return SearchTopResult(
                title: artist.name,
                kind: String(localized: "Artist"),
                cover: artist.artworkURL.map { .url($0, seed: artist.name) },
                isArtist: true,
                open: { remember(); push(.artist(artist.id)) },
                play: playable(theirs).isEmpty ? nil : { remember(); play(theirs, from: nil) }
            )
        case .album:
            guard let album = results.albums.first else { return nil }
            return SearchTopResult(
                title: album.title,
                kind: String(localized: "Album · \(album.artistName)"),
                cover: .url(album.artworkURL, seed: album.title),
                open: { remember(); push(.album(album.id)) },
                play: nil
            )
        case .song:
            guard let song = results.songs.first else { return nil }
            return SearchTopResult(
                title: song.title,
                kind: String(localized: "Song · \(song.artistName)"),
                cover: .url(song.artworkURL, seed: song.albumTitle ?? song.title),
                open: { remember(); push(.song(song.id)) },
                play: playable([song]).isEmpty ? nil : { remember(); play(results.songs, from: song) }
            )
        }
    }

    // MARK: - Playing

    private func playable(_ songs: [SongTally]) -> [SongTally] {
        songs.filter { player.canPlay(songID: $0.songID) }
    }

    /// The songs that can play, from `song` on, in Tracks' player.
    private func play(_ songs: [SongTally], from song: SongTally?) {
        let queue = playable(songs)
        guard !queue.isEmpty else { return }
        let start = song.flatMap { song in queue.firstIndex { $0.id == song.id } } ?? 0
        let ordered = Array(queue[start...]) + Array(queue[..<start])
        player.play(.history(ordered.map { HistorySong(MixSong(tally: $0)) }), from: .songs(String(localized: "Search")))
    }

    private func push(_ route: Route) {
        openRoute(.stats(route))
    }

    // MARK: - States

    @ViewBuilder
    private var overlay: some View {
        if model.library.isLoaded, model.library.history.captures.isEmpty, recents.isEmpty || !isBlank {
            ContentUnavailableView(
                "Nothing Played Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Songs you play show up here to search, with how often you’ve played them.")
            )
        } else if !isBlank, answeredQuery == query, results.isEmpty {
            SearchNoResults(query: query)
        }
    }

    private var isBlank: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Recent searches

    private var recents: [String] {
        RecentSearches.list(recentStorage)
    }

    private func remember() {
        recentStorage = RecentSearches.adding(query, to: recentStorage)
    }
}

private struct SearchKey: Equatable {
    let query: String
    let indexGeneration: Int
}
