import SwiftUI
import MusicKit
import MotifCore

/// A library row of the sidebar: Apple Music's library, or your own music's, following the
/// music source.
struct LibraryPage: View {
    let item: SidebarItem
    let source: MusicSource
    #if DEBUG
    @Environment(AppModel.self) private var model
    #endif

    var body: some View {
        page
            #if DEBUG
            .task(id: model.yourMusic.index.artists.count) {
                CollectionScreenshotSetup.apply()
                // `-MotifAppearance light`, for light screenshots on a Mac set to dark.
                if UserDefaults.standard.string(forKey: "MotifAppearance") == "light" {
                    NSApp.appearance = NSAppearance(named: .aqua)
                }
                LibraryLaunch.push(in: model)
            }
            #endif
    }

    @ViewBuilder
    private var page: some View {
        switch (source, item) {
        case (.appleMusic, .recentlyAdded): LibraryRecentlyAddedPage()
        case (.appleMusic, .playlists): LibraryListView(section: .playlists)
        case (.appleMusic, .albums): LibraryListView(section: .albums)
        case (.appleMusic, .artists): LibraryListView(section: .artists)
        case (.appleMusic, .songs): LibraryListView(section: .songs)
        case (.yourMusic, .recentlyAdded): LocalRecentlyAddedPage()
        case (.yourMusic, .playlists): YourMusicList.playlists.page
        case (.yourMusic, .albums): YourMusicList.albums.page
        case (.yourMusic, .artists): YourMusicList.artists.page
        case (.yourMusic, .songs): YourMusicList.songs.page
        case (.yourMusic, .downloads): YourMusicList.downloads.page
        case (.yourMusic, .lidarr): LidarrPage()
        default:
            ContentUnavailableView("Not in \(Text(source.title))", systemImage: item.symbol)
        }
    }
}

/// Search from the sidebar, in Apple Music's catalog, your library, or your history, chosen in
/// the toolbar as Music chooses between Apple Music and Library.
struct MacSearchResults: View {
    let query: String
    @Binding var scope: SearchScope
    let search: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch scope {
            case .history:
                SearchResultsList(query: query)
            case .library where model.musicSource == .yourMusic:
                YourMusicSearchResults(query: query, search: search)
            case .library:
                LibrarySearchResults(query: query)
            case .appleMusic:
                MusicSearchResults(query: query, scope: .appleMusic, search: search)
            }
        }
        .navigationTitle("Search")
        // Apple Music's catalog isn't a scope when your own music plays.
        .onAppear { keepScope() }
        .onChange(of: model.musicSource) { keepScope() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Search In", selection: $scope) {
                    ForEach(SearchScope.scopes(for: model.musicSource)) { scope in
                        Text(scope.title(for: model.musicSource)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

private extension MacSearchResults {
    func keepScope() {
        let scopes = SearchScope.scopes(for: model.musicSource)
        if !scopes.contains(scope) { scope = scopes[0] }
    }
}

/// Your Apple Music library, searched on the Mac. MusicKit's own library search goes through
/// the same iTunes library requests that can end the app on the Mac, so this looks through
/// the library the pages have read (``LibraryCache``), in Swift: artists, albums, songs and
/// playlists whose names hold every word typed.
private struct LibrarySearchResults: View {
    let query: String
    @State private var songs = LibraryPager<Song>()
    @State private var albums = LibraryPager<Album>()
    @State private var artists = LibraryPager<Artist>()
    @State private var playlists = LibraryPager<Playlist>()
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed

    var body: some View {
        LibraryAccessGate {
            List {
                if !artists.items.isEmpty {
                    Section("Artists") {
                        ForEach(artists.items.prefix(4)) { artist in
                            NavigationLink(value: PlayRoute.artist(artist)) {
                                HStack(spacing: 10) {
                                    ArtistPicture(cover: artist.artwork.map(CoverArt.artwork), name: artist.name, size: 32)
                                    Text(artist.name).lineLimit(1)
                                }
                            }
                            .contextMenu { LibraryArtistMenu(name: artist.name, artist: artist) }
                        }
                    }
                }
                if !albums.items.isEmpty {
                    Section("Albums") {
                        ForEach(albums.items.prefix(8)) { album in
                            NavigationLink(value: PlayRoute.album(album)) {
                                row(title: album.title, subtitle: album.artistName, cover: album.libraryCover)
                            }
                            .contextMenu { FeedItemMenu(item: FeedItem(album: album)) }
                        }
                    }
                }
                if !shownSongs.isEmpty {
                    Section("Songs") {
                        ForEach(Array(shownSongs.enumerated()), id: \.element.id) { index, song in
                            let identity = HistoryImport.key(title: song.title, artistName: song.artistName)
                            Button {
                                player.play(.songs(shownSongs, startingAt: index), from: .songs(String(localized: "Search")))
                            } label: {
                                TrackRow(
                                    title: song.title,
                                    subtitle: [song.artistName, song.albumTitle].compactMap(\.self).joined(separator: " · "),
                                    cover: song.artwork.map(CoverArt.artwork) ?? .url(nil, seed: song.albumTitle ?? song.title),
                                    plays: feed.facts[identity]?.plays,
                                    isExplicit: song.isExplicit,
                                    isCurrent: player.current?.songIdentity == identity
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu { SongMenu(song: song) }
                        }
                    }
                }
                if !playlists.items.isEmpty {
                    Section("Playlists") {
                        ForEach(playlists.items.prefix(6)) { playlist in
                            NavigationLink(value: PlayRoute.playlist(playlist)) {
                                row(title: playlist.name, subtitle: playlist.curatorName, cover: playlist.libraryCover)
                            }
                            .contextMenu { FeedItemMenu(item: FeedItem(playlist: playlist)) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay { overlay }
            .loads(songs, query: query, order: .title) { LibrarySortKeys(song: $0, plays: 0) }
            .loads(albums, query: query, order: .title) { LibrarySortKeys(album: $0) }
            .loads(artists, query: query, order: .title) { LibrarySortKeys(artist: $0) }
            .loads(playlists, query: query, order: .title) { LibrarySortKeys(playlist: $0) }
        }
    }

    private var shownSongs: [Song] { Array(songs.items.prefix(12)) }

    private var isLoading: Bool {
        [songs.phase, albums.phase, artists.phase, playlists.phase].contains(.loading)
    }

    private var isEmpty: Bool {
        songs.items.isEmpty && albums.items.isEmpty && artists.items.isEmpty && playlists.items.isEmpty
    }

    @ViewBuilder
    private var overlay: some View {
        if isEmpty {
            if isLoading {
                LoadingRows(count: 8)
                    .padding(.horizontal, PlayMetrics.margin)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(.background)
            } else if songs.phase == .failed {
                LibraryLoadFailed { await songs.retry(query: query) }
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(title: String, subtitle: String?, cover: CoverArt) -> some View {
        HStack(spacing: 10) {
            CoverImage(cover: cover, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
    }
}

/// Listen Now: the Play tab's page, for the music Play is on.
struct ListenNowPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.musicSource == .yourMusic {
                YourMusicScreen()
            } else {
                PlayScreen()
            }
        }
        .quickSourceSwitch()
    }
}
