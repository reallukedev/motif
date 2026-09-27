import SwiftUI
import MusicKit
import MotifCore

/// A genre's page, as Apple Music's are, with your own listening beside it: its station at the
/// top, then what's most played in it on Apple Music, and what you play of it. With your own
/// music, what you have of it.
struct GenreView: View {
    let genre: MusicGenre
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed
    @Environment(YourMusic.self) private var music
    @State private var charts = GenreCatalog.Found.empty
    @State private var profile: GenreProfile?
    @State private var local: LocalGenres.Group?
    @State private var localAlbums: [LocalAlbum] = []
    @State private var hasLoaded = false
    @State private var isStarting = false
    @State private var showsAllCharts = false
    @State private var showsAllYours = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                hero
                if model.musicSource == .yourMusic {
                    localSongs
                    localAlbumsShelf
                } else {
                    topSongs
                    yourSongs
                    yourArtists
                    if !charts.albums.isEmpty {
                        Shelf(title: String(localized: "Top Albums"), items: charts.albums) { FeedTile(item: $0) }
                    }
                    if !charts.playlists.isEmpty {
                        Shelf(title: String(localized: "Playlists"), items: charts.playlists) { FeedTile(item: $0) }
                    }
                }
                if hasLoaded, isEmpty {
                    ContentUnavailableView(
                        "Nothing in \(genre.title) Yet",
                        systemImage: genre.symbol,
                        description: Text(model.musicSource == .yourMusic
                            ? "None of your music is tagged \(genre.title). Motif goes by each song's genre."
                            : "Apple Music couldn't be reached, and you haven't played any \(genre.title) yet.")
                    )
                }
            }
            .padding(.bottom, 24)
        }
        .heroTitle(genre.title)
        #if os(macOS)
        .navigationTitle(genre.title)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .toolbarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var isEmpty: Bool {
        if model.musicSource == .yourMusic { return local?.tracks.isEmpty ?? true }
        return charts.songs.isEmpty && charts.albums.isEmpty && charts.playlists.isEmpty && (profile?.songs.isEmpty ?? true)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: genre.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(height: 34, alignment: .bottomLeading)
                    .accessibilityHidden(true)
                Text(genre.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text(tagline)
                    .font(.title3)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 14) {
                // What Play does, above it, clear of the fade below.
                Text(model.musicSource == .yourMusic
                     ? String(localized: "Your \(genre.title) songs, picked as it plays. Skip as much as you like.")
                     : String(localized: "Your \(genre.title) songs and new ones from its charts, picked as it plays."))
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                playButton
            }
            .frame(maxWidth: Self.controlsWidth, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlayMetrics.margin)
        .padding(.top, Self.heroTop)
        .padding(.bottom, 24 + HeroField.fade)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            HeroField(color: genre.color, symbol: genre.symbol)
        }
    }

    private var tagline: String {
        model.musicSource == .yourMusic
            ? String(localized: "The \(genre.title) in your music.")
            : String(localized: "What you play most, and what everyone's playing.")
    }

    /// The station's on, playing or paused.
    private var isOn: Bool {
        player.hasQueue && player.context == genre.context
    }

    private var playTitle: LocalizedStringKey {
        if isStarting { return "Starting…" }
        guard isOn else { return "Play Station" }
        return player.isPlaying ? "Pause" : "Resume"
    }

    private var canPlay: Bool {
        if model.musicSource == .yourMusic { return !(local?.tracks.isEmpty ?? true) }
        return !hasLoaded || !charts.songs.isEmpty || !(profile?.songs.isEmpty ?? true)
    }

    @ViewBuilder
    private var playButton: some View {
        let label = Label(playTitle, systemImage: isOn && player.isPlaying ? "pause.fill" : "play.fill")
            .contentTransition(.symbolEffect(.replace))
        #if os(macOS)
        Button(action: playOrPause) { label }
            .buttonStyle(.stagePrimary(tint: genre.color))
            .disabled(!canPlay || isStarting)
        #else
        Button(action: playOrPause) {
            label
                .font(.headline)
                .foregroundStyle(HueField.shades(of: genre.color)[0])
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white, in: .capsule)
        }
        .buttonStyle(.pressable)
        .opacity(canPlay ? 1 : 0.5)
        .disabled(!canPlay || isStarting)
        #endif
    }

    private func playOrPause() {
        if isOn {
            player.togglePlayPause()
            return
        }
        isStarting = true
        Task {
            await GenrePlayback.start(genre, model: model, charts: hasLoaded ? charts.songs : nil)
            isStarting = false
        }
    }

    #if os(macOS)
    private static let controlsWidth: CGFloat = 400
    private static let heroTop: CGFloat = 28
    #else
    private static let controlsWidth: CGFloat = .infinity
    private static let heroTop: CGFloat = 12
    #endif

    // MARK: Apple Music

    @ViewBuilder
    private var topSongs: some View {
        if !charts.songs.isEmpty {
            let shown = Array(charts.songs.prefix(showsAllCharts ? 25 : 6))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Top Songs")) { EmptyView() }
                ForEach(shown) { song in
                    SuggestionRow(suggestion: Suggestion(song: song, reason: .popular), showsReason: false) {
                        let all = charts.songs
                        player.play(.songs(all, startingAt: all.firstIndex(of: song) ?? 0), from: .songs(String(localized: "Top \(genre.title)")))
                    }
                    .contextMenu { SongMenu(song: song) }
                    if song.id != shown.last?.id { Divider().padding(.leading, 64) }
                }
                if charts.songs.count > 6 { showMore($showsAllCharts) }
            }
            .padding(.horizontal, PlayMetrics.margin)
        } else if !hasLoaded {
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Top Songs")) { EmptyView() }
                LoadingRows(count: 6)
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
    }

    @ViewBuilder
    private var yourSongs: some View {
        let songs = (profile?.songs ?? []).filter { player.canPlay(songID: $0.songID) }
        if !songs.isEmpty {
            let shown = Array(songs.prefix(showsAllYours ? 25 : 5))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Your \(genre.title) Songs")) { EmptyView() }
                ForEach(shown) { song in
                    Button {
                        let queue = Array(songs.prefix(25)).map(HistorySong.init)
                        player.play(.history(queue, startingAt: songs.firstIndex(of: song) ?? 0), from: .songs(String(localized: "Your \(genre.title) Songs")))
                    } label: {
                        TrackRow(
                            title: song.title,
                            subtitle: song.artistName,
                            cover: .url(song.artworkURL, seed: song.albumTitle ?? song.title),
                            plays: song.plays,
                            isCurrent: player.current?.songIdentity == song.songIdentity
                        )
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { HistorySongMenu(song: song) }
                    if song.id != shown.last?.id { Divider().padding(.leading, 60) }
                }
                if songs.count > 5 { showMore($showsAllYours) }
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
    }

    @ViewBuilder
    private var yourArtists: some View {
        if let artists = profile?.artists, !artists.isEmpty {
            Shelf(title: String(localized: "Your \(genre.title) Artists"), items: artists) { artist in
                FavoriteArtistTile(artist: artist)
            }
        }
    }

    // MARK: Your own music

    @ViewBuilder
    private var localSongs: some View {
        if let tracks = local?.tracks, !tracks.isEmpty {
            let shown = Array(tracks.prefix(showsAllYours ? 50 : 8))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Songs")) {
                    Button("Shuffle", systemImage: "shuffle") {
                        player.play(.local(tracks), from: .songs(genre.title), shuffled: true)
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                }
                ForEach(shown) { track in
                    Button {
                        player.play(.local(tracks, startingAt: tracks.firstIndex(of: track) ?? 0), from: .songs(genre.title))
                    } label: {
                        LocalTrackRow(track: track, isCurrent: player.current?.local?.id == track.id)
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { LocalTrackMenu(track: track) }
                    if track.id != shown.last?.id { Divider().padding(.leading, 60) }
                }
                if tracks.count > 8 { showMore($showsAllYours) }
            }
            .padding(.horizontal, PlayMetrics.margin)
        } else if !hasLoaded {
            LoadingRows(count: 6)
                .padding(.horizontal, PlayMetrics.margin)
        }
    }

    @ViewBuilder
    private var localAlbumsShelf: some View {
        if !localAlbums.isEmpty {
            Shelf(title: String(localized: "Albums"), items: localAlbums) { album in
                LocalAlbumTile(album: album)
            }
        }
    }

    /// Albums of yours with a song in the genre, the most played song's first.
    private static func albums(of tracks: [LocalTrack], in music: YourMusic) -> [LocalAlbum] {
        var albumOf: [String: LocalAlbum] = [:]
        for album in music.index.albums {
            for track in album.tracks { albumOf[track.id] = album }
        }
        var seen = Set<String>()
        return Array(tracks.compactMap { albumOf[$0.id] }.filter { seen.insert($0.id).inserted }.prefix(20))
    }

    private func showMore(_ isShowingAll: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { isShowingAll.wrappedValue.toggle() }
        } label: {
            Text(isShowingAll.wrappedValue ? "Show Less" : "Show More")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    // MARK: Loading

    private func load() async {
        guard !hasLoaded else { return }
        let history = model.library.history
        if model.musicSource == .yourMusic {
            local = LocalGenres.group(music.playableTracks, history: history, facts: feed.facts).first { $0.genre == genre }
            localAlbums = Self.albums(of: local?.tracks ?? [], in: music)
            hasLoaded = true
            return
        }
        let (signals, genre) = (player.signals, genre)
        profile = await OffMainActor.run { MusicGenre.profiles(in: history, signals: signals).first { $0.genre == genre } }
        charts = await GenreCatalog.load(genre, isDemo: player.isDemo)
        hasLoaded = true
    }
}
