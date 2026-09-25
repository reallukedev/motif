import SwiftUI
import MusicKit
import MotifCore

extension Mood {
    var title: String {
        switch self {
        case .feelGood: String(localized: "Feel Good")
        case .energy: String(localized: "Energy")
        case .workout: String(localized: "Workout")
        case .focus: String(localized: "Focus")
        case .chill: String(localized: "Chill")
        case .love: String(localized: "Love")
        case .drive: String(localized: "Drive")
        case .heartbreak: String(localized: "Heartbreak")
        case .party: String(localized: "Party")
        case .sleep: String(localized: "Sleep")
        }
    }

    /// One line on what the mood is for, under its name.
    var tagline: String {
        switch self {
        case .feelGood: String(localized: "Bright, easy songs to lift the day.")
        case .energy: String(localized: "Loud, fast and full of it.")
        case .workout: String(localized: "Hard-hitting songs to keep you moving.")
        case .focus: String(localized: "Calm, steady music to think to.")
        case .chill: String(localized: "Laid-back songs to slow down to.")
        case .love: String(localized: "For the one you can't stop thinking about.")
        case .drive: String(localized: "Windows down, and the long way home.")
        case .heartbreak: String(localized: "For when it hurts, and for getting over it.")
        case .party: String(localized: "Big songs for a full room.")
        case .sleep: String(localized: "Soft, quiet music to drift off to.")
        }
    }

    var symbol: String {
        switch self {
        case .feelGood: "sun.max.fill"
        case .energy: "bolt.fill"
        case .workout: "figure.run"
        case .focus: "scope"
        case .chill: "leaf.fill"
        case .love: "heart.fill"
        case .drive: "car.fill"
        case .heartbreak: "heart.slash.fill"
        case .party: "party.popper.fill"
        case .sleep: "moon.stars.fill"
        }
    }

    /// The mood's deepest colour, for type and tints over white.
    var color: Color { palette[0] }

    /// Three colours for the mood's field, deep to light, all dark enough for white type.
    var palette: [Color] {
        switch self {
        case .feelGood: [Color(red: 0.78, green: 0.36, blue: 0.02), Color(red: 0.95, green: 0.55, blue: 0.08), Color(red: 0.98, green: 0.72, blue: 0.2)]
        case .energy: [Color(red: 0.72, green: 0.12, blue: 0.08), Color(red: 0.93, green: 0.3, blue: 0.1), Color(red: 1, green: 0.52, blue: 0.16)]
        case .workout: [Color(red: 0.55, green: 0.04, blue: 0.16), Color(red: 0.85, green: 0.1, blue: 0.24), Color(red: 0.98, green: 0.35, blue: 0.2)]
        case .focus: [Color(red: 0.1, green: 0.16, blue: 0.48), Color(red: 0.2, green: 0.34, blue: 0.72), Color(red: 0.3, green: 0.56, blue: 0.82)]
        case .chill: [Color(red: 0.02, green: 0.36, blue: 0.36), Color(red: 0.08, green: 0.55, blue: 0.5), Color(red: 0.36, green: 0.72, blue: 0.56)]
        case .love: [Color(red: 0.62, green: 0.06, blue: 0.3), Color(red: 0.88, green: 0.2, blue: 0.44), Color(red: 0.98, green: 0.45, blue: 0.52)]
        case .drive: [Color(red: 0.04, green: 0.16, blue: 0.28), Color(red: 0.08, green: 0.4, blue: 0.5), Color(red: 0.96, green: 0.56, blue: 0.28)]
        case .heartbreak: [Color(red: 0.26, green: 0.12, blue: 0.46), Color(red: 0.44, green: 0.26, blue: 0.64), Color(red: 0.58, green: 0.46, blue: 0.76)]
        case .party: [Color(red: 0.46, green: 0.06, blue: 0.56), Color(red: 0.8, green: 0.14, blue: 0.62), Color(red: 0.98, green: 0.4, blue: 0.5)]
        case .sleep: [Color(red: 0.04, green: 0.08, blue: 0.26), Color(red: 0.12, green: 0.2, blue: 0.44), Color(red: 0.3, green: 0.3, blue: 0.56)]
        }
    }
}

/// The mood's colours, deep in one corner and light in the other, like light through glass.
struct MoodField: View {
    let mood: Mood

    var body: some View {
        let (deep, mid, light) = (mood.palette[0], mood.palette[1], mood.palette[2])
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.4], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                deep, mid, light,
                deep, mid, mid,
                deep, deep, mid,
            ]
        )
    }
}

// MARK: - On Play

/// Find Your Mood, on Play: every mood in two rows to scroll through.
struct MoodShelf: View {
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 86

    var body: some View {
        let height = min(height, 130)
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: String(localized: "Find Your Mood")) { EmptyView() }
                .padding(.horizontal, PlayMetrics.margin)
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(height), spacing: 10), GridItem(.fixed(height))], spacing: 10) {
                    ForEach(Mood.allCases) { mood in
                        MoodTile(mood: mood, height: height)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, PlayMetrics.margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// A mood on the shelf: its field, its symbol large and faint in the corner, and its name.
struct MoodTile: View {
    let mood: Mood
    let height: CGFloat
    /// Fills its grid cell's width, rather than the shelf's fixed shape.
    var fillsWidth = false

    var body: some View {
        NavigationLink(value: PlayRoute.mood(mood)) {
            ZStack(alignment: .bottomLeading) {
                MoodField(mood: mood)
                Image(systemName: mood.symbol)
                    .font(.system(size: height * 0.72, weight: .bold))
                    .foregroundStyle(.white.opacity(0.2))
                    .rotationEffect(.degrees(-12))
                    .offset(x: height * 0.2, y: height * 0.14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
                Text(mood.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(12)
            }
            .frame(width: fillsWidth ? nil : height * 1.75, height: height)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(mood.title)
    }
}

/// Every mood at once, filling the width, as the Mac shows them on Listen Now and Radio.
struct MoodGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find Your Mood")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(Mood.allCases) { mood in
                    MoodTile(mood: mood, height: 92, fillsWidth: true)
                }
            }
        }
        .padding(.horizontal, PlayMetrics.margin)
    }
}

// MARK: - The mood's page

/// How much of a mood's flow is yours.
enum MoodFlow: String, CaseIterable, Identifiable {
    /// Only songs from your history.
    case yours
    /// Yours and new finds, the new ones for about a quarter.
    case both
    /// Only songs you've never played.
    case new

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .yours: "Your Songs"
        case .both: "Both"
        case .new: "New Music"
        }
    }
}

/// One mood, two ways: go with its flow, a live mix of your songs and new ones picked as it
/// plays, or go looking, through new songs and new artists for it, your own songs that suit
/// it, and Apple Music's playlists and stations.
struct MoodView: View {
    let mood: Mood
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed
    @State private var yours: [MixSong] = []
    @State private var newSongs: [Suggestion] = []
    @State private var newArtists: [Artist] = []
    @State private var stations: [FeedItem] = []
    @State private var playlists: [FeedItem] = []
    @State private var hasLoaded = false
    @State private var flow = MoodFlow.both
    @AppStorage(SuggestionMode.storageKey) private var suggestionMode = SuggestionMode.everything
    @State private var showsAllYours = false
    @State private var showsAllNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                hero

                newToYou
                artistsToDiscover
                yourSongs

                if !playlists.isEmpty {
                    Shelf(title: String(localized: "Playlists"), items: playlists) { FeedTile(item: $0) }
                }
                if !stations.isEmpty {
                    Shelf(title: String(localized: "Stations"), items: stations) { FeedTile(item: $0) }
                }

                if hasLoaded, yours.isEmpty, newSongs.isEmpty, stations.isEmpty, playlists.isEmpty {
                    ContentUnavailableView(
                        "Nothing for \(mood.title) Yet",
                        systemImage: mood.symbol,
                        description: Text("Apple Music couldn't be reached, and none of your songs suit it yet. As Motif learns the genres of what you play, they'll show up here.")
                    )
                }
            }
            .padding(.bottom, 24)
        }
        #if os(macOS)
        .navigationTitle(mood.title)
        // The mood's field runs on under the toolbar, which says nothing the field doesn't.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .toolbarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .task(id: "\(newSongs.count).\(model.yourMusic.availabilityGeneration).\(suggestionMode.rawValue).\(newSongs.unanswered(in: model.yourMusic, source: model.musicSource))") {
            await newSongs.lookUp(in: model.yourMusic, source: model.musicSource, mode: suggestionMode, first: 12)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: mood.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(height: 34, alignment: .bottomLeading)
                    .accessibilityHidden(true)
                Text(mood.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text(mood.tagline)
                    .font(.title3)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Your own music has no new songs from Apple Music to mix in.
                if model.musicSource == .appleMusic {
                    Picker("Play", selection: $flow) {
                        ForEach(MoodFlow.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(mood.palette[1])
                    .environment(\.colorScheme, .dark)
                }

                #if os(macOS)
                Button {
                    play(startingWith: nil)
                } label: {
                    Label("Go with the Flow", systemImage: "play.fill")
                }
                .buttonStyle(.stagePrimary(tint: mood.color))
                .disabled(!canPlay)
                #else
                Button {
                    play(startingWith: nil)
                } label: {
                    Label("Go with the Flow", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(mood.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.pressable)
                .disabled(!canPlay)
                #endif

                Text(flowLine)
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            // A line's worth of controls on the Mac, not the window's width.
            .frame(maxWidth: Self.controlsWidth, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlayMetrics.margin)
        .padding(.top, Self.heroTop)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            MoodField(mood: mood)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: mood.symbol)
                        .font(.system(size: 220, weight: .bold))
                        .foregroundStyle(.white.opacity(0.1))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 60, y: 40)
                        .accessibilityHidden(true)
                }
                .clipped()
                // Into the page at its foot, rather than stopping at an edge.
                .mask {
                    // A fade of fixed length at the foot, below the words, however tall the
                    // field is.
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 44)
                    }
                }
                // Up under the bar and into any pull past the top.
                .padding(.top, -400)
        }
        .animation(.snappy, value: flow)
    }

    #if os(macOS)
    private static let controlsWidth: CGFloat = 400
    private static let heroTop: CGFloat = 28
    #else
    private static let controlsWidth: CGFloat = .infinity
    private static let heroTop: CGFloat = 12
    #endif

    private var canPlay: Bool {
        switch flow {
        case .yours: !yours.isEmpty
        case .new: !newSongs.isEmpty || !stations.isEmpty || !hasLoaded
        case .both: !yours.isEmpty || !newSongs.isEmpty || !stations.isEmpty || !hasLoaded
        }
    }

    private var flowLine: String {
        switch flow {
        case _ where model.musicSource == .yourMusic:
            yours.isEmpty
                ? String(localized: "None of your music suits \(mood.title) yet. Motif goes by each song's genre.")
                : String(localized: "Your songs that suit it, picked one at a time as it plays. Skip as much as you like.")
        case .yours:
            yours.isEmpty
                ? String(localized: "None of your songs suit \(mood.title) yet.")
                : String(localized: "Your songs that suit it, picked one at a time as it plays. Skip as much as you like.")
        case .both:
            String(localized: "Your songs and new ones, picked as it plays. What you skip steers what comes next.")
        case .new:
            String(localized: "Only songs you've never played, picked as it plays. Keep the ones you love with a tap.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var newToYou: some View {
        if !newSongs.isEmpty {
            let shown = Array(newSongs.visible(in: model.yourMusic, source: model.musicSource, mode: suggestionMode).prefix(showsAllNew ? 25 : 6))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "New to You")) {
                    FindMoreLink(route: .songFinder(.mood(mood)))
                }
                if shown.isEmpty, newSongs.unanswered(in: model.yourMusic, source: model.musicSource) > 0 {
                    LoadingRows(count: 3)
                }
                ForEach(shown) { suggestion in
                    SuggestionRow(suggestion: suggestion, showsReason: false) {
                        let all = newSongs.map(\.song)
                        player.play(.songs(all, startingAt: all.firstIndex(of: suggestion.song) ?? 0), from: .songs(mood.title))
                    }
                    .contextMenu { SuggestionMenu(suggestion: suggestion) }
                    if suggestion.id != shown.last?.id { Divider().padding(.leading, 64) }
                }
                if newSongs.count > 6 {
                    showMore(isShowingAll: $showsAllNew)
                }
            }
            .padding(.horizontal, PlayMetrics.margin)
        } else if !hasLoaded {
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "New to You")) { EmptyView() }
                LoadingRows(count: 6)
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
    }

    @ViewBuilder
    private var artistsToDiscover: some View {
        if !newArtists.isEmpty {
            Shelf(title: String(localized: "Artists to Discover"), items: newArtists) { artist in
                NavigationLink(value: PlayRoute.artist(artist)) {
                    VStack(spacing: 8) {
                        CoverImage(cover: artist.artwork.map(CoverArt.artwork) ?? .url(nil, seed: artist.name), size: 110, isCircle: true)
                        Text(artist.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(width: 110)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    @ViewBuilder
    private var yourSongs: some View {
        if !yours.isEmpty {
            let shown = Array(yours.prefix(showsAllYours ? 25 : 5))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Your \(mood.title) Songs")) { EmptyView() }
                ForEach(shown) { song in
                    Button {
                        play(startingWith: song, flow: .yours)
                    } label: {
                        TrackRow(
                            title: song.title,
                            subtitle: song.artistName,
                            cover: .url(song.artworkURL, seed: song.albumTitle ?? song.title),
                            plays: song.plays,
                            isCurrent: player.current?.songIdentity == song.songIdentity
                        )
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.canPlay(songID: song.songID))
                    .contextMenu { HistorySongMenu(song: song) }
                    if song.id != shown.last?.id { Divider().padding(.leading, 60) }
                }
                if yours.count > 5 {
                    showMore(isShowingAll: $showsAllYours)
                }
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
    }

    private func showMore(isShowingAll: Binding<Bool>) -> some View {
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

    // MARK: Playing and loading

    private func play(startingWith first: MixSong?, flow: MoodFlow? = nil) {
        let flow = flow ?? self.flow
        let found = hasLoaded ? MoodCatalog.Found(stations: stations, playlists: playlists, newSongs: newSongs.map(\.song)) : nil
        Task {
            await MoodPlayback.start(mood, model: model, flow: flow, found: found, startingWith: first)
        }
    }

    private func load() async {
        // Once per visit: coming back from an artist or an album shouldn't search again.
        guard !hasLoaded else { return }
        let (history, signals, mood) = (model.library.history, player.signals, mood)
        // Your own music: the songs whose genre suits the mood, and, unless suggestions are
        // off, new songs for it from Apple Music's catalog, each marked for whether you have
        // it. Apple's own playlists and stations play only from Apple Music, so they stay out.
        if model.musicSource == .yourMusic {
            let tracks = model.yourMusic.playableTracks
            let mix = await OffMainActor.run { LiveMix.mood(mood, from: tracks, history: history, signals: signals, seed: 1) }
            let songs: [MixSong] = mix.candidates.map(\.song).sorted { lhs, rhs in
                lhs.plays == rhs.plays ? lhs.title < rhs.title : lhs.plays > rhs.plays
            }
            yours = songs.map(withCover)
            flow = .both
            if suggestionMode != .off {
                let found = await MoodCatalog.find(mood, isDemo: player.isDemo)
                newSongs = fresh(found.newSongs)
            }
            hasLoaded = true
            if suggestionMode != .off {
                newArtists = await MoodCatalog.artists(of: newSongs.map(\.song), leavingOut: feed.heardArtists, isDemo: player.isDemo)
            }
            return
        }
        yours = await OffMainActor.run { MoodMix.songs(for: mood, in: history, signals: signals) }
            .filter { player.canPlay(songID: $0.songID) }
        if yours.isEmpty { flow = .new }

        let found = await MoodCatalog.find(mood, isDemo: player.isDemo)
        stations = found.stations
        playlists = found.playlists
        newSongs = fresh(found.newSongs)
        hasLoaded = true
        newArtists = await MoodCatalog.artists(of: newSongs.map(\.song), leavingOut: feed.heardArtists, isDemo: player.isDemo)
    }

    /// A song of yours with its cover, which a mix doesn't carry.
    private func withCover(_ song: MixSong) -> MixSong {
        let music = model.yourMusic
        let artwork: String? = music.index.track(id: song.songID).flatMap { music.artworkURL($0.artwork)?.absoluteString }
        return MixSong(
            songIdentity: song.songIdentity,
            songID: song.songID,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            artworkURL: artwork,
            plays: song.plays,
            lastHeard: song.lastHeard,
            genre: song.genre
        )
    }

    /// Songs never played, the version the explicit setting allows, no artist twice in a row.
    private func fresh(_ songs: [Song]) -> [Suggestion] {
        var seen = Set<String>()
        let unheard = PlayPreferences.versions(of: songs).filter { song in
            let identity = HistoryImport.key(title: song.title, artistName: song.artistName)
            return feed.facts[identity] == nil && !player.signals.excludes(identity, now: .now) && seen.insert(identity).inserted
        }
        return FreshShuffle.order(
            unheard.map { Suggestion(song: $0, reason: .mood(mood)) },
            artist: { StatsCalculator.folded($0.song.artistName) },
            seed: FreshShuffle.dailySeed(for: .now, salt: "mood.new.\(mood.rawValue)")
        )
    }
}

// MARK: - Apple Music for a mood

/// Apple Music's stations and playlists for a mood, found by searching for it, and the songs
/// on its playlists. Apple's own playlists come first.
enum MoodCatalog {
    struct Found {
        var stations: [FeedItem]
        var playlists: [FeedItem]
        /// The songs on its first few playlists.
        var newSongs: [Song]

        static let empty = Found(stations: [], playlists: [], newSongs: [])
    }

    /// Everything Apple Music has for the mood.
    static func find(_ mood: Mood, isDemo: Bool) async -> Found {
        #if DEBUG
        if isDemo {
            let offset = 1_100 + (Mood.allCases.firstIndex(of: mood) ?? 0) * 40
            return Found(stations: [], playlists: [], newSongs: DemoCatalog.songs(count: 24, offset: offset, artists: nil))
        }
        #endif
        guard !isDemo, MusicAuthorization.currentStatus == .authorized else { return .empty }
        let items = await items(for: mood)
        let playlists = items.playlists.compactMap { item -> Playlist? in
            if case .playlist(let playlist) = item.content { playlist } else { nil }
        }
        let songs = await songs(in: playlists, allowsExplicit: PlayPreferences.allowsExplicit)
        return Found(stations: items.stations, playlists: items.playlists, newSongs: songs)
    }

    @concurrent
    nonisolated static func items(for mood: Mood) async -> (stations: [FeedItem], playlists: [FeedItem]) {
        var request = MusicCatalogSearchRequest(term: mood.searchTerm, types: [MusicKit.Station.self, Playlist.self])
        request.limit = 15
        guard let response = try? await request.response() else { return ([], []) }
        let playlists = response.playlists.sorted { lhs, rhs in
            let (left, right) = (lhs.curatorName?.contains("Apple Music") == true, rhs.curatorName?.contains("Apple Music") == true)
            return left && !right
        }
        return (
            await MainActor.run { response.stations.prefix(4).map { FeedItem(station: $0) } },
            await MainActor.run { playlists.prefix(12).map { FeedItem(playlist: $0) } }
        )
    }

    /// The songs on a mood's first few playlists, as new finds.
    @concurrent
    nonisolated static func songs(in playlists: [Playlist], allowsExplicit: Bool) async -> [Song] {
        await withTaskGroup(of: (Int, [Song]).self) { group in
            for (index, playlist) in playlists.prefix(3).enumerated() {
                group.addTask {
                    guard let tracks = try? await playlist.with([.tracks]).tracks else { return (index, []) }
                    return (index, tracks.prefix(100).compactMap { track in
                        guard case .song(let song) = track else { return nil }
                        return song
                    })
                }
            }
            var byIndex: [Int: [Song]] = [:]
            for await (index, songs) in group { byIndex[index] = songs }
            return byIndex.keys.sorted()
                .flatMap { byIndex[$0] ?? [] }
                .filter { allowsExplicit || $0.contentRating != .explicit }
        }
    }

    /// The artists behind a mood's new songs that you've never played, each once.
    static func artists(of songs: [Song], leavingOut heard: Set<String>, isDemo: Bool) async -> [Artist] {
        #if DEBUG
        if isDemo { return DemoCatalog.artists(count: 8, offset: songs.count % 7) }
        #endif
        guard !isDemo else { return [] }
        var names = Set<String>()
        let wanted = songs.filter { song in
            let key = StatsCalculator.folded(song.artistName)
            return !heard.contains(key) && names.insert(key).inserted
        }
        return await lookUpArtists(of: Array(wanted.prefix(10)))
    }

    @concurrent
    nonisolated private static func lookUpArtists(of songs: [Song]) async -> [Artist] {
        await withTaskGroup(of: (Int, Artist?).self) { group in
            for (index, song) in songs.enumerated() {
                group.addTask {
                    let artist: Artist? = if let known = song.artists?.first { known } else { try? await song.with([.artists]).artists?.first }
                    return (index, artist)
                }
            }
            var byIndex: [Int: Artist] = [:]
            for await (index, artist) in group { byIndex[index] = artist }
            var seen = Set<MusicItemID>()
            return byIndex.keys.sorted().compactMap { byIndex[$0] }.filter { seen.insert($0.id).inserted }
        }
    }
}

/// Starting a mood, from its page, CarPlay or Siri. It plays live, each song picked as the one
/// before starts, from your songs that suit it and new finds from Apple Music's playlists for
/// it. Where there's neither, it plays Apple Music's station for the mood.
@MainActor
enum MoodPlayback {
    /// - Parameters:
    ///   - flow: how much of it is yours.
    ///   - found: what Apple Music has for the mood, where it's already loaded; looked up
    ///     otherwise.
    ///   - first: a song to start with, as when one is tapped on the mood's page.
    static func start(
        _ mood: Mood,
        model: AppModel,
        flow: MoodFlow = .both,
        found: MoodCatalog.Found? = nil,
        startingWith first: MixSong? = nil
    ) async {
        let player = model.player
        let isDemo = player.isDemo
        if model.musicSource == .yourMusic {
            let (tracks, history, signals) = (model.yourMusic.playableTracks, model.library.history, player.signals)
            let mix = await OffMainActor.run {
                LiveMix.mood(mood, from: tracks, history: history, signals: signals, seed: .random(in: 0...UInt64.max))
            }
            guard !mix.isEmpty else {
                player.problem = .failed(String(localized: "None of your music suits \(mood.title) yet. Motif goes by each song's genre."))
                return
            }
            await player.startLive(mix, from: PlayContext(kind: .endless, title: mood.title), startingWith: first)
            return
        }
        let catalog = if let found { found } else { await MoodCatalog.find(mood, isDemo: isDemo) }
        let newFinds = flow == .yours ? [] : catalog.newSongs.map(MixSong.init(catalog:))
        let history = flow == .new ? ListeningHistory([]) : model.library.history
        let signals = player.signals
        let mix = await OffMainActor.run {
            LiveMix.mood(mood, from: history, signals: signals, newFinds: newFinds, seed: .random(in: 0...UInt64.max))
                .playable(isDemo: isDemo)
        }

        let context = PlayContext(kind: .endless, title: mood.title)
        if !mix.isEmpty {
            await player.startLive(mix, from: context, startingWith: first)
        } else if let (request, context) = catalog.stations.first?.stationRequest {
            await player.start(request, from: context)
        } else {
            player.problem = .failed(String(localized: "Nothing to play for \(mood.title) yet."))
        }
    }
}
