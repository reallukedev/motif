import SwiftUI
import MotifCore

/// An artist in your music: the songs of theirs you play most, their newest album, and every
/// album of theirs you have.
struct LocalArtistPage: View {
    let artistID: String
    @Environment(YourMusic.self) private var music
    @Environment(Lidarr.self) private var lidarr
    @Environment(PlayFeed.self) private var feed
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        if let artist = music.index.artist(id: artistID) {
            let top = topSongs(of: artist)
            let playable = artist.tracks.filter(music.isPlayable)
            let context = PlayContext(kind: .artist, title: artist.name)
            ArtistScaffold(
                name: artist.name,
                picture: picture(of: artist),
                play: playable.isEmpty ? nil : { player.play(.local(top.isEmpty ? playable : top.filter(music.isPlayable)), from: context) },
                shuffle: playable.isEmpty ? nil : { player.play(.local(playable), from: context, shuffled: true) },
                showsYourTopSongs: false
            ) {
                if lidarr.isSetUp {
                    if let followed = lidarr.artist(named: artist.name), let id = followed.id {
                        // Everything Lidarr knows of theirs, to get what you're missing.
                        Button("Show in Lidarr", systemImage: "tray.and.arrow.down") {
                            openPlayRoute(.lidarrArtist(id))
                        }
                    } else {
                        AddToLidarrButton(artistName: artist.name)
                    }
                }
            } sections: {
                songs(top.isEmpty ? Array(artist.tracks) : top, areYours: !top.isEmpty, artist: artist.name, context: context)
                if artist.albums.count > 1, let latest = latestAlbum(of: artist) {
                    ArtistLatestRelease(
                        title: latest.title,
                        cover: cover(of: latest),
                        detail: detail(of: latest),
                        route: .localAlbum(latest.id)
                    ) {
                        LocalAlbumMenu(album: latest)
                    }
                }
                Shelf(title: String(localized: "Albums"), items: newestFirst(artist.albums)) { album in
                    LocalAlbumShelfTile(album: album)
                }
            }
        } else {
            ScrollView {
                ArtistPageMessage(
                    title: String(localized: "Artist Not Found"),
                    symbol: "music.microphone",
                    message: String(localized: "Their songs aren't in your music anymore. They may have been removed, or their server is offline.")
                ) {
                    NavigationLink("Show All Artists", value: PlayRoute.yourMusic(.artists))
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Artist")
        }
    }

    /// Their songs: the ones you play most, or all of them in album order before you've
    /// played any.
    private func songs(_ tracks: [LocalTrack], areYours: Bool, artist: String, context: PlayContext) -> some View {
        let visible = Array(tracks.prefix(ArtistSongsSection<EmptyView, EmptyView>.visibleRows))
        let title = areYours ? String(localized: "Your Top Songs") : String(localized: "Songs")
        return ArtistSongsSection(title: title, showsSeeAll: tracks.count > visible.count) {
            ArtistSongListPage(title: title, artist: artist) {
                ForEach(tracks) { track in songRow(track, in: tracks, context: context) }
            }
        } content: {
            ForEach(visible) { track in songRow(track, in: tracks, context: context) }
        }
    }

    private func songRow(_ track: LocalTrack, in tracks: [LocalTrack], context: PlayContext) -> some View {
        Button {
            let queue = tracks.filter(music.isPlayable)
            guard let start = queue.firstIndex(of: track) else { return }
            player.play(.local(queue, startingAt: start), from: context)
        } label: {
            ArtistSongLabel(
                title: track.title,
                subtitle: track.album,
                cover: .url(music.artworkURL(track.artwork)?.absoluteString, seed: track.album ?? track.title),
                plays: feed.facts[track.identity]?.plays,
                isCurrent: player.current?.local?.id == track.id,
                isPlayable: music.isPlayable(track)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { LocalTrackMenu(track: track, showsStats: true) }
    }

    private func picture(of artist: LocalArtist) -> CoverArt? {
        let picture = music.artworkURL(artist.artwork).map { CoverArt.url($0.absoluteString, seed: artist.name) }
        #if DEBUG
        if picture == nil, LibraryLaunch.drawsSamplePictures { return .url("sample", seed: artist.name) }
        #endif
        return picture
    }

    private func cover(of album: LocalAlbum) -> CoverArt {
        .url(music.artworkURL(album.artwork)?.absoluteString, seed: album.title)
    }

    /// "Album · 2024 · 12 songs".
    private func detail(of album: LocalAlbum) -> String {
        let songs = String(AttributedString(localized: "^[\(album.tracks.count) song](inflect: true)").characters)
        return [album.year.map(String.init), songs].compactMap(\.self).joined(separator: " · ")
    }

    /// The newest album that has a year; none when no album says when it came out.
    private func latestAlbum(of artist: LocalArtist) -> LocalAlbum? {
        artist.albums.filter { $0.year != nil }.max { ($0.year ?? 0, $0.addedAt) < ($1.year ?? 0, $1.addedAt) }
    }

    private func newestFirst(_ albums: [LocalAlbum]) -> [LocalAlbum] {
        albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    /// The artist's songs you've played most; none if you haven't played any.
    private func topSongs(of artist: LocalArtist) -> [LocalTrack] {
        artist.tracks
            .map { ($0, feed.facts[$0.identity]?.plays ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

/// An album of yours on an artist's shelf: the library's hover tile on the Mac.
struct LocalAlbumShelfTile: View {
    let album: LocalAlbum

    var body: some View {
        #if os(macOS)
        LocalAlbumGridTile(album: album, side: LibraryCoverTile<EmptyView, EmptyView>.shelfSide)
        #else
        LocalAlbumTile(album: album)
        #endif
    }
}

/// An album of yours in a grid of covers, with Play under the pointer on the Mac.
struct LocalAlbumGridTile: View {
    let album: LocalAlbum
    var subtitle: String?
    /// A fixed side for a shelf; nil fills the grid's column.
    var side: CGFloat?
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let playable = album.tracks.filter(music.isPlayable)
        LibraryCoverTile(
            title: album.title,
            subtitle: subtitle ?? album.artist,
            route: .localAlbum(album.id),
            play: playable.isEmpty ? nil : { player.play(.local(playable), from: PlayContext(kind: .album, title: album.title)) },
            side: side
        ) { side in
            LocalCover(artwork: album.artwork, seed: album.title, size: side)
                .aspectRatio(1, contentMode: .fit)
        } menu: {
            LocalAlbumMenu(album: album)
        }
    }
}

/// Every song in your music, to search and sort: a table on the Mac, a list on iPhone.
struct LocalSongsPage: View {
    var body: some View {
        #if os(macOS)
        LibraryYourSongsTablePage()
        #else
        LocalSongsList()
        #endif
    }
}

#if os(iOS)
private struct LocalSongsList: View {
    @Environment(YourMusic.self) private var music
    @Environment(PlayFeed.self) private var feed
    @Environment(PlayerModel.self) private var player
    @AppStorage("yourMusicSongOrder") private var order = LibraryOrder.title
    @State private var query = ""
    @State private var deleting: LocalTrack?

    private static let orders: [LibraryOrder] = [.title, .natural(.artist), .natural(.album), .natural(.added), .natural(.plays)]

    var body: some View {
        let songs = sorted(LibrarySort.filtered(music.index.tracks, matching: query) { LibrarySortKeys(title: $0.title, artist: $0.artist, album: $0.album ?? "") })
        let context = PlayContext.songs(String(localized: "Your Songs"))
        // One list from the first frame, with the state as its row until there are songs, so
        // the filter field stays tucked under the title (see `libraryStateRow()`).
        List {
            if music.index.isEmpty {
                Group {
                    if music.hasScanned || !music.servers.servers.isEmpty {
                        LibraryEmptyYourMusic(title: String(localized: "No Songs Yet"))
                    } else {
                        LoadingRows(count: 10)
                            .padding(.horizontal, PlayMetrics.margin)
                    }
                }
                .libraryStateRow()
            } else if songs.isEmpty {
                LibraryNoMatches(query: query)
                    .libraryStateRow()
            } else {
                if query.isEmpty {
                    LibraryPlayButtons {
                        player.play(.local(songs.filter(music.isPlayable)), from: context)
                    } shuffle: {
                        player.play(.local(songs.filter(music.isPlayable)), from: context, shuffled: true)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: PlayMetrics.margin, bottom: 12, trailing: PlayMetrics.margin))
                }
                ForEach(songs) { track in
                    Button {
                        let queue = songs.filter(music.isPlayable)
                        player.play(.local(queue, startingAt: queue.firstIndex(of: track) ?? 0), from: context)
                    } label: {
                        LocalTrackRow(track: track, isCurrent: player.current?.local?.id == track.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(!music.isPlayable(track))
                    .libraryRowInsets()
                    .contextMenu { LocalTrackMenu(track: track, showsStats: true, onDelete: { deleting = $0 }) }
                    .swipeActions(edge: .leading) {
                        if music.isPlayable(track) {
                            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                player.enqueue(.local([track]), next: true, title: track.title)
                            }
                            .tint(.indigo)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if music.isPlayable(track) {
                            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                                player.enqueue(.local([track]), next: false, title: track.title)
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .pageSearch(alwaysShown: false), prompt: "Filter Songs")
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .libraryAction) {
                LibrarySortMenu(selection: $order, options: Self.orders) { $0.menuTitle }
            }
        }
        .confirmationDialog(
            deleteTitle(deleting?.title ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Song", role: .destructive) { if let deleting { music.deleteFile(deleting) } }
        }
    }

    private func sorted(_ tracks: [LocalTrack]) -> [LocalTrack] {
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = tracks.map { LibrarySongRow(track: $0, plays: feed.facts[$0.identity]?.plays ?? 0, isPlayable: true, artworkURL: nil) }
        return order.sorted(rows).compactMap { byID[$0.id] }
    }
}
#endif

extension LibrarySortKeys {
    /// An album of yours, sorted as Apple Music's are.
    init(localAlbum album: LocalAlbum) {
        self.init(
            title: album.title,
            artist: album.artist,
            added: album.addedAt == .distantPast ? nil : album.addedAt,
            released: album.year.flatMap { DateComponents(calendar: .current, year: $0).date }
        )
    }
}

/// Every album in your music, as a grid, filtered as you type and in the order chosen.
struct LocalAlbumsPage: View {
    @Environment(YourMusic.self) private var music
    @AppStorage("yourMusicAlbumOrder") private var order = LibraryOrder.natural(.added)
    @State private var query = ""

    private static let orders: [LibraryOrder] = [.natural(.added), .title, .natural(.artist), .natural(.year)]

    var body: some View {
        let albums = LibrarySort.sorted(
            LibrarySort.filtered(music.index.albums, matching: query) { LibrarySortKeys(localAlbum: $0) },
            by: order
        ) { LibrarySortKeys(localAlbum: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                #if os(macOS)
                LibraryPageHeader(
                    title: String(localized: "Albums"),
                    subtitle: music.index.isEmpty ? nil : String(AttributedString(localized: "^[\(music.index.albums.count) album](inflect: true)").characters)
                )
                #endif
                if music.index.isEmpty {
                    if music.hasScanned || !music.servers.servers.isEmpty {
                        LibraryEmptyYourMusic(title: String(localized: "No Albums Yet"))
                    } else {
                        LibraryGridPlaceholder()
                    }
                } else if albums.isEmpty {
                    LibraryNoMatches(query: query)
                } else {
                    LibraryGrid {
                        ForEach(albums) { album in
                            LocalAlbumGridTile(album: album, subtitle: subtitle(of: album))
                        }
                    }
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, PlayMetrics.sectionSpacing)
        }
        .searchable(text: $query, placement: .pageSearch(alwaysShown: false), prompt: "Filter Albums")
        .libraryToolbar()
        .navigationTitle("Albums")
        #if os(macOS)
        .toolbar(removing: .title)
        #else
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .libraryAction) {
                LibrarySortMenu(selection: $order, options: Self.orders) { $0.menuTitle }
            }
        }
    }

    private var topPadding: CGFloat {
        #if os(macOS)
        0
        #else
        8
        #endif
    }

    /// The artist, or the year too when the albums are in order of it.
    private func subtitle(of album: LocalAlbum) -> String {
        if order.field == .year, let year = album.year { return "\(album.artist) · \(String(year))" }
        return album.artist
    }
}

/// Every artist in your music, with their pictures and your plays: Music's Artists view on the
/// Mac, a list with an A to Z index on iPhone.
struct LocalArtistsPage: View {
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute
    #if DEBUG
    @Environment(AppModel.self) private var model
    #endif
    @State private var query = ""
    @State private var plays: [String: Int] = [:]
    #if os(macOS)
    @State private var selection: LocalArtist.ID?
    #endif

    var body: some View {
        let artists = LibrarySort.sorted(
            LibrarySort.filtered(music.index.artists, matching: query) { LibrarySortKeys(title: $0.name) },
            by: .title
        ) { LibrarySortKeys(title: $0.name) }
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                LibraryPageHeader(
                    title: String(localized: "Artists"),
                    subtitle: music.index.isEmpty ? nil : String(AttributedString(localized: "^[\(music.index.artists.count) artist](inflect: true)").characters)
                )
                if music.index.isEmpty || artists.isEmpty {
                    state
                } else {
                    list(artists)
                }
            }
            #else
            // One list from the first frame, with the state as its row until there are
            // artists, so the filter field stays tucked under the title (see `libraryStateRow()`).
            List {
                if music.index.isEmpty || artists.isEmpty {
                    state.libraryStateRow()
                } else {
                    list(artists)
                }
            }
            .listStyle(.plain)
            .listSectionIndexVisibility(.visible)
            #endif
        }
        .artistPlays(into: $plays)
        #if DEBUG
        .task(id: music.index.artists.count) { LibraryLaunch.push(in: model) }
        #endif
        .searchable(text: $query, placement: .pageSearch(alwaysShown: false), prompt: "Filter Artists")
        .libraryToolbar()
        .navigationTitle("Artists")
        #if os(macOS)
        .toolbar(removing: .title)
        #else
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    /// Loading, an empty library, or nothing matching the filter.
    @ViewBuilder
    private var state: some View {
        if !music.index.isEmpty {
            LibraryNoMatches(query: query)
                .frame(maxHeight: .infinity, alignment: .top)
        } else if music.hasScanned || !music.servers.servers.isEmpty {
            LibraryEmptyYourMusic(title: String(localized: "No Artists Yet"))
        } else {
            #if os(macOS)
            LibraryArtistSplitPlaceholder()
            #else
            LibraryArtistRowsPlaceholder()
            #endif
        }
    }

    @ViewBuilder
    private func list(_ artists: [LocalArtist]) -> some View {
        #if os(macOS)
        LibraryArtistSplit(
            artists: artists,
            selection: $selection,
            name: \.name,
            picture: picture(of:),
            open: { openPlayRoute(.localArtist($0.id)) }
        ) { artist in
            let playable = artist.tracks.filter(music.isPlayable)
            LibraryArtistDetail(
                name: artist.name,
                picture: picture(of: artist),
                facts: facts(of: artist),
                shuffle: playable.isEmpty ? nil : {
                    player.play(.local(playable), from: PlayContext(kind: .artist, title: artist.name), shuffled: true)
                },
                open: { openPlayRoute(.localArtist(artist.id)) }
            ) {
                ForEach(artist.albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }) { album in
                    LocalAlbumGridTile(album: album, subtitle: album.year.map(String.init) ?? album.artist)
                }
            }
        } menu: { artist in
            LibraryArtistMenu(name: artist.name)
        }
        #else
        LibraryArtistIndexSections(artists: artists, name: \.name) { artist in
            NavigationLink(value: PlayRoute.localArtist(artist.id)) {
                LibraryArtistRow(
                    name: artist.name,
                    picture: picture(of: artist),
                    detail: String(AttributedString(localized: "^[\(artist.albums.count) album](inflect: true)").characters),
                    plays: plays[StatsCalculator.folded(artist.name)]
                )
            }
            .contextMenu { LibraryArtistMenu(name: artist.name) }
        }
        #endif
    }

    private func picture(of artist: LocalArtist) -> CoverArt? {
        music.artworkURL(artist.artwork).map { .url($0.absoluteString, seed: artist.name) }
    }

    /// "3 albums · 212 plays".
    private func facts(of artist: LocalArtist) -> String {
        var parts = [String(AttributedString(localized: "^[\(artist.albums.count) album](inflect: true)").characters)]
        if let count = plays[StatsCalculator.folded(artist.name)], count > 0 { parts.append(PlayCountText.short(count)) }
        return parts.joined(separator: " · ")
    }
}

/// The albums added to your music most lately, newest first, as a grid.
struct LocalRecentlyAddedPage: View {
    @Environment(YourMusic.self) private var music
    @State private var query = ""

    var body: some View {
        let albums = Array(LibrarySort.filtered(music.index.recentlyAdded, matching: query) { LibrarySortKeys(localAlbum: $0) }.prefix(LibraryRecentlyAdded.limit))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                #if os(macOS)
                LibraryPageHeader(title: String(localized: "Recently Added"), subtitle: nil)
                #endif
                if music.index.isEmpty {
                    if music.hasScanned || !music.servers.servers.isEmpty {
                        LibraryEmptyYourMusic(title: String(localized: "Nothing Added Yet"))
                    } else {
                        LibraryGridPlaceholder()
                    }
                } else if albums.isEmpty {
                    LibraryNoMatches(query: query)
                } else {
                    LibraryGrid {
                        ForEach(albums) { album in
                            LocalAlbumGridTile(album: album)
                        }
                    }
                }
            }
            .padding(.bottom, PlayMetrics.sectionSpacing)
        }
        .searchable(text: $query, placement: .pageSearch(alwaysShown: false), prompt: "Filter Recently Added")
        .libraryToolbar()
        .navigationTitle("Recently Added")
        #if os(macOS)
        .toolbar(removing: .title)
        #endif
    }
}

/// "Delete “Wildflowers” from This iPhone?", or from This Mac.
private func deleteTitle(_ title: String) -> String {
    #if os(macOS)
    String(localized: "Delete \u{201C}\(title)\u{201D} from This Mac?")
    #else
    String(localized: "Delete \u{201C}\(title)\u{201D} from This iPhone?")
    #endif
}
