import SwiftUI
import MusicKit
import MotifCore

/// Apple Music results for a search, from the catalog or the library, in Music's order:
/// artists, songs, albums, playlists, stations. With no query, recent searches.
struct MusicSearchResults: View {
    let query: String
    let scope: SearchScope
    /// Puts a recent search back in the field.
    let search: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed
    @Environment(\.openPlayRoute) private var openRoute
    @State private var results = Results()
    @State private var state: LoadState = .idle
    @AppStorage("recentMusicSearches") private var recentStorage = ""
    @AppStorage(PlayPreferences.allowsExplicitKey) private var allowsExplicit = true

    enum LoadState: Equatable { case idle, loading, loaded, failed }

    struct Results {
        var artists: [Artist] = []
        var songs: [Song] = []
        var albums: [Album] = []
        var playlists: [Playlist] = []
        var stations: [MusicKit.Station] = []

        var isEmpty: Bool {
            artists.isEmpty && songs.isEmpty && albums.isEmpty && playlists.isEmpty && stations.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                if model.isShowingSampleData {
                    // Sample data never reaches Apple Music.
                } else if isBlank {
                    blank
                } else if !results.isEmpty {
                    resultSections
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
            .animation(.snappy, value: results.isEmpty)
        }
        .overlay { overlay }
        .task(id: SearchKey(query: query, scope: scope, authorization: model.musicAuthorization, allowsExplicit: allowsExplicit)) {
            await runSearch()
        }
    }

    // MARK: - Before searching

    /// What you looked for lately, as chips to look again, and the moods to browse by.
    @ViewBuilder
    private var blank: some View {
        if !recents.isEmpty {
            RecentSearchesSection(recents: recents, clear: { recentStorage = "" }, search: search)
        }
        if scope == .appleMusic, model.musicAuthorization == .authorized {
            BrowseByMoodSection()
        }
    }

    // MARK: - Results

    /// The best match, if there's a clear one: an artist whose name is what was typed, or the
    /// first song.
    private var topResult: TopResult? {
        let term = StatsCalculator.folded(query.trimmingCharacters(in: .whitespaces))
        if let artist = results.artists.first, StatsCalculator.folded(artist.name).hasPrefix(term) || term.hasPrefix(StatsCalculator.folded(artist.name)) {
            return .artist(artist)
        }
        if let album = results.albums.first, StatsCalculator.folded(album.title) == term {
            return .album(album)
        }
        return results.songs.first.map(TopResult.song)
    }

    enum TopResult {
        case artist(Artist), album(Album), song(Song)
    }

    /// The top result as the card shows it.
    private func card(for result: TopResult) -> SearchTopResult {
        switch result {
        case .artist(let artist):
            SearchTopResult(
                title: artist.name,
                kind: String(localized: "Artist"),
                cover: artist.artwork.map(CoverArt.artwork),
                isArtist: true,
                open: { remember(); openRoute(.artist(artist)) },
                play: { remember(); Task { await ArtistPlayback.playTopSongs(of: artist, player: player) } }
            )
        case .album(let album):
            SearchTopResult(
                title: CollectionKind.of(album).title,
                kind: String(localized: "Album · \(album.artistName)"),
                cover: album.artwork.map(CoverArt.artwork) ?? .url(nil, seed: album.title),
                open: { remember(); openRoute(.album(album)) },
                play: { remember(); player.play(.album(album), from: PlayContext(kind: .album, title: album.title)) }
            )
        case .song(let song):
            SearchTopResult(
                title: song.title,
                kind: String(localized: "Song · \(song.artistName)"),
                cover: song.artwork.map(CoverArt.artwork) ?? .url(nil, seed: song.albumTitle ?? song.title),
                open: { remember(); player.play(.songs([song]), from: .songs(String(localized: "Search"))) },
                play: { remember(); player.play(.songs([song]), from: .songs(String(localized: "Search"))) }
            )
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        let top = topResult
        let songs = Array(results.songs.prefix(8))
        #if os(macOS)
        // The top result beside the first songs, as Music lays them out.
        HStack(alignment: .top, spacing: 28) {
            if let top {
                VStack(alignment: .leading, spacing: 10) {
                    SearchSectionTitle("Top Result")
                    TopResultCard(result: card(for: top))
                }
                .frame(width: 340)
            }
            if !songs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SearchSectionTitle("Songs")
                    songRows(Array(songs.prefix(4)), all: songs)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, PlayMetrics.margin)
        if songs.count > 4 {
            songRows(Array(songs.dropFirst(4)), all: songs)
                .padding(.horizontal, PlayMetrics.margin)
                .padding(.top, -PlayMetrics.sectionSpacing + 8)
        }
        #else
        if let top {
            VStack(alignment: .leading, spacing: 10) {
                SearchSectionTitle("Top Result")
                TopResultCard(result: card(for: top))
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SearchSectionTitle("Songs")
                songRows(songs, all: songs)
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
        #endif

        if results.artists.count > (top.isArtist ? 1 : 0) {
            Shelf(title: String(localized: "Artists"), items: Array(results.artists.dropFirst(top.isArtist ? 1 : 0).prefix(10))) { artist in
                NavigationLink(value: PlayRoute.artist(artist)) {
                    VStack(spacing: 8) {
                        CoverImage(cover: artist.artwork.map(CoverArt.artwork) ?? .url(nil, seed: artist.name), size: 120, isCircle: true)
                        Text(artist.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(width: 120)
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { remember() })
            }
        }
        if !results.albums.isEmpty {
            Shelf(title: String(localized: "Albums"), items: results.albums.prefix(10).map(FeedItem.init(album:))) { item in
                FeedTile(item: item)
                    .simultaneousGesture(TapGesture().onEnded { remember() })
            }
        }
        if !results.playlists.isEmpty {
            Shelf(title: String(localized: "Playlists"), items: results.playlists.prefix(10).map(FeedItem.init(playlist:))) { item in
                FeedTile(item: item)
                    .simultaneousGesture(TapGesture().onEnded { remember() })
            }
        }
        if !results.stations.isEmpty {
            Shelf(title: String(localized: "Stations"), items: results.stations.prefix(8).map { FeedItem(station: $0) }) { item in
                FeedTile(item: item)
                    .simultaneousGesture(TapGesture().onEnded { remember() })
            }
        }
    }

    /// Songs in rows, two columns of them on the Mac.
    private func songRows(_ shown: [Song], all: [Song]) -> some View {
        SearchSongGrid(items: shown) { song in
            Button {
                remember()
                // The song, then the rest of the results, as playing from any list does.
                player.play(.songs(all, startingAt: all.firstIndex(of: song) ?? 0), from: .songs(String(localized: "Search")))
            } label: {
                TrackRow(
                    title: song.title,
                    subtitle: [song.artistName, song.albumTitle].compactMap(\.self).joined(separator: " · "),
                    cover: song.artwork.map(CoverArt.artwork) ?? .url(nil, seed: song.title),
                    isExplicit: song.isExplicit,
                    isCurrent: player.current?.songIdentity == HistoryImport.key(title: song.title, artistName: song.artistName)
                )
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu { SongMenu(song: song) }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.isShowingSampleData {
            ContentUnavailableView(
                "Not Available with Sample Data",
                systemImage: "music.note",
                description: Text("Search History to look through the sample listening.")
            )
        } else if model.musicAuthorization != .authorized {
            ContentUnavailableView {
                Label("Search Apple Music", systemImage: "magnifyingglass")
            } description: {
                Text("Let Motif use Apple Music to search its catalog and your library.")
            } actions: {
                if model.musicAuthorization == .notDetermined {
                    Button("Allow Apple Music Access") { Task { await model.requestMusicAccess() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else if isBlank, recents.isEmpty {
            ContentUnavailableView(
                scope == .appleMusic ? "Search Apple Music" : "Search Your Library",
                systemImage: "magnifyingglass",
                description: Text(scope == .appleMusic
                    ? "Find any song, album, artist or station, and play it here."
                    : "Find songs, albums, artists and playlists you've added.")
            )
        } else if !isBlank, state == .failed {
            ContentUnavailableView {
                Label("Couldn't Search", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await runSearch() } }
            }
        } else if !isBlank, state == .loaded, results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if !isBlank, state == .loading, results.isEmpty {
            ProgressView()
        }
    }

    // MARK: - Searching

    private var isBlank: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !model.isShowingSampleData, model.musicAuthorization == .authorized else {
            results = Results()
            state = .idle
            return
        }
        // A short pause so typing doesn't search on every letter.
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        state = .loading
        do {
            let found = scope == .library ? try await Self.searchLibrary(term) : try await Self.searchCatalog(term)
            guard !Task.isCancelled else { return }
            // One version of each song and album: Apple Music lists both.
            var picked = found
            picked.songs = PlayPreferences.versions(of: found.songs, allowsExplicit: allowsExplicit)
            picked.albums = PlayPreferences.versions(of: found.albums, allowsExplicit: allowsExplicit)
            results = picked
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed
        }
    }

    private static func searchCatalog(_ term: String) async throws -> Results {
        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Artist.self, Song.self, Album.self, Playlist.self, MusicKit.Station.self]
        )
        request.limit = 12
        let response = try await request.response()
        return Results(
            artists: Array(response.artists),
            songs: Array(response.songs),
            albums: Array(response.albums),
            playlists: Array(response.playlists),
            stations: Array(response.stations)
        )
    }

    private static func searchLibrary(_ term: String) async throws -> Results {
        var request = MusicLibrarySearchRequest(term: term, types: [Artist.self, Song.self, Album.self, Playlist.self])
        request.limit = 12
        let response = try await request.response()
        return Results(
            artists: Array(response.artists),
            songs: Array(response.songs),
            albums: Array(response.albums),
            playlists: Array(response.playlists)
        )
    }

    // MARK: - Recent searches

    private var recents: [String] {
        RecentSearches.list(recentStorage)
    }

    /// Keeps the query once someone acts on a result, newest first, eight at most.
    private func remember() {
        recentStorage = RecentSearches.adding(query, to: recentStorage)
    }
}

private struct SearchKey: Equatable {
    let query: String
    let scope: SearchScope
    let authorization: MusicAuthorization.Status
    let allowsExplicit: Bool
}

private extension Optional where Wrapped == MusicSearchResults.TopResult {
    var isArtist: Bool {
        if case .artist = self { true } else { false }
    }
}
