import SwiftUI
import MusicKit
import TracksCore

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

    /// The mood's own colour, one no other mood shares, rich enough for white type.
    var base: Color {
        switch self {
        case .feelGood: Color(red: 0.93, green: 0.47, blue: 0.04)
        case .energy: Color(red: 0.92, green: 0.27, blue: 0.1)
        case .workout: Color(red: 0.84, green: 0.1, blue: 0.27)
        case .focus: Color(red: 0.16, green: 0.38, blue: 0.84)
        case .chill: Color(red: 0.05, green: 0.56, blue: 0.5)
        case .love: Color(red: 0.9, green: 0.2, blue: 0.46)
        case .drive: Color(red: 0.03, green: 0.47, blue: 0.72)
        case .heartbreak: Color(red: 0.45, green: 0.28, blue: 0.68)
        case .party: Color(red: 0.8, green: 0.14, blue: 0.62)
        case .sleep: Color(red: 0.15, green: 0.18, blue: 0.44)
        }
    }

    /// The mood's colour deep to light, for what needs a shade of it.
    var palette: [Color] { HueField.shades(of: base) }
}

/// A mood's field: its colour, lit a little from the top as Apple's tiles are.
struct MoodField: View {
    let mood: Mood

    var body: some View {
        HueField(color: mood.base)
    }
}

/// One colour, lit a little from the top as Apple's own tiles are: a mood's field, and
/// Handpicked's, each genre's and each party's.
struct HueField: View {
    let color: Color

    var body: some View {
        Rectangle().fill(color.gradient)
    }

    /// A colour deep to light: darker for type over white, lighter for a highlight.
    static func shades(of color: Color) -> [Color] {
        [color.mix(with: .black, by: 0.3), color, color.mix(with: .white, by: 0.25)]
    }
}

/// The colour behind a page's header, as a mood's, Handpicked's and each genre's have: its
/// field with its symbol large and faint in the corner, up under the bar and into any pull
/// past the top, melting into the page below the header's last button over a long, eased
/// fade, as a collection's header does, rather than stopping at a line.
struct HeroField: View {
    let color: Color
    let symbol: String

    var body: some View {
        HueField(color: color)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 220, weight: .bold))
                    .foregroundStyle(.white.opacity(0.1))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 60, y: 10)
                    .accessibilityHidden(true)
            }
            .clipped()
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        stops: Self.easedStops.map { .init(color: .black.opacity(1 - $0.opacity), location: $0.location) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.fadeReach)
                }
            }
            .padding(.top, -400)
            .accessibilityHidden(true)
    }

    /// Below the header's last button, where the page shows through at last.
    static let fade: CGFloat = 40
    /// How far up the fade reaches: from behind the last button down, clear of the words
    /// above it.
    static let fadeReach: CGFloat = 150

    /// Smoothstep, so the fade has no start or end to see.
    private static let easedStops: [(opacity: Double, location: Double)] = (0...10).map { step in
        let t = Double(step) / 10
        return (opacity: t * t * (3 - 2 * t), location: t)
    }
}

extension View {
    /// The page's name in the bar once its header's big name has scrolled away under it, as
    /// Music's pages do. Put on the scroll view. The Mac's window title says it already.
    func heroTitle(_ title: String) -> some View {
        modifier(HeroTitle(title: title))
    }
}

private struct HeroTitle: ViewModifier {
    let title: String
    @State private var isShown = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Self.threshold
            } action: { _, shown in
                withAnimation(.easeOut(duration: 0.2)) { isShown = shown }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(isShown ? 1 : 0)
                        .accessibilityHidden(!isShown)
                }
            }
        #else
        content
        #endif
    }

    /// About where the big name has gone under the bar.
    private static let threshold: CGFloat = 110
}

// MARK: - On Play

/// Find Your Mood, on Play: Handpicked, then every mood, in a row to scroll through.
struct MoodShelf: View {
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = Self.height

    var body: some View {
        let height = min(height, 130)
        Shelf(title: String(localized: "Find Your Mood"), items: MoodShelfItem.all) { EmptyView() } tile: { item in
            switch item {
            // Your own mood first: a station from songs you choose.
            case .handpicked: HandpickedTile(height: height)
            case .mood(let mood): MoodTile(mood: mood, height: height)
            }
        }
    }

    #if os(macOS)
    static let height: CGFloat = 96
    #else
    static let height: CGFloat = 86
    #endif
}

/// A tile on Find Your Mood.
enum MoodShelfItem: Identifiable {
    case handpicked
    case mood(Mood)

    var id: String {
        switch self {
        case .handpicked: "handpicked"
        case .mood(let mood): mood.rawValue
        }
    }

    static let all: [MoodShelfItem] = [.handpicked] + Mood.allCases.map(MoodShelfItem.mood)
}

/// A mood on the shelf: its field, its symbol large and faint in the corner, and its name.
struct MoodTile: View {
    let mood: Mood
    let height: CGFloat
    /// Fills its grid cell's width, rather than the shelf's fixed shape.
    var fillsWidth = false

    var body: some View {
        // Party opens its own page, for finding a party's playlist.
        NavigationLink(value: mood == .party ? PlayRoute.party : PlayRoute.mood(mood)) {
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
                        description: Text("Apple Music couldn't be reached, and none of your songs suit it yet. As Tracks learns the genres of what you play, they'll show up here.")
                    )
                }
            }
            .padding(.bottom, 24)
        }
        .heroTitle(mood.title)
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
                    .tint(mood.base)
                    .environment(\.colorScheme, .dark)
                }

                // What Play does, above it, clear of the fade below.
                Text(flowLine)
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)

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
            }
            // A line's worth of controls on the Mac, not the window's width.
            .frame(maxWidth: Self.controlsWidth, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlayMetrics.margin)
        .padding(.top, Self.heroTop)
        .padding(.bottom, 24 + HeroField.fade)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            HeroField(color: mood.base, symbol: mood.symbol)
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
                ? String(localized: "None of your music suits \(mood.title) yet. Tracks goes by each song's genre.")
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
                player.problem = .failed(String(localized: "None of your music suits \(mood.title) yet. Tracks goes by each song's genre."))
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
