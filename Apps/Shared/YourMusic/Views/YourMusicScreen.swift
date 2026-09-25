import SwiftUI
import UniformTypeIdentifiers
import MusicKit
import MotifCore

/// Play, when your own music is the source: Motif Radio from everything you own, what's new,
/// your mixes and moods from your files and servers, what each server has to discover, and
/// your whole library a tap away.
struct YourMusicScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(YourMusic.self) private var music
    @Environment(PlayFeed.self) private var feed
    @Environment(PlayerModel.self) private var player
    @Environment(Lidarr.self) private var lidarr
    @AppStorage(PlayPreferences.motifRadioKey) private var isRadioOn = true
    @AppStorage(SuggestionMode.storageKey) private var suggestionMode = SuggestionMode.everything
    @State private var showsSettings = LaunchScene.opensPlaySettings
    @State private var importMode: ImportMode?
    @State private var addsServer = false
    @State private var isSearching = LaunchScene.opensSearch
    @State private var query = ""
    @State private var shelves = Shelves()

    enum ImportMode { case files, folder }

    var body: some View {
        ScrollView {
            // Lazy, so shelves below the fold are made, and ask their servers, as they come.
            LazyVStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                if !music.index.isEmpty {
                    content
                } else if !music.servers.syncing.isEmpty || (!music.hasScanned && music.servers.servers.isEmpty) {
                    // Reading the files, or a server's first sync.
                    VStack(alignment: .leading, spacing: 8) {
                        if !music.servers.syncing.isEmpty {
                            Label("Getting your server's songs…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        LoadingRows(count: 6)
                    }
                    .padding(.horizontal, PlayMetrics.margin)
                } else if !music.servers.onlineServers.isEmpty {
                    // A server that answered with no songs, Octo's often: what it picks for you
                    // leads, to play and add.
                    content
                } else {
                    YourMusicWelcome(
                        hasServers: !music.servers.servers.isEmpty,
                        importFiles: { importMode = .files },
                        importFolder: { importMode = .folder },
                        addServer: { addsServer = true }
                    )
                    .padding(.horizontal, PlayMetrics.margin)
                }
            }
            #if os(macOS)
            .padding(.top, 20)
            #else
            .padding(.top, 4)
            #endif
            .padding(.bottom, 24)
        }
        .overlay {
            if !query.isEmpty {
                YourMusicSearchResults(query: query)
                    .background(Color.pageBackground)
            }
        }
        .overlay(alignment: .top) {
            if let result = music.lastImport {
                ImportBanner(result: result)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: music.lastImport?.added)
        #if os(iOS)
        // The Mac searches your music from the sidebar.
        .searchable(text: $query, isPresented: $isSearching, placement: .pageSearch(alwaysShown: false), prompt: "Your Music")
        // Keeps the large title where it is while the field opens, as Play's own search does.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: isSearching) { _, searching in
            if !searching { query = "" }
        }
        .navigationTitle("Play")
        #else
        .navigationTitle("Listen Now")
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                if NearbyDevices.isOn { DevicesButton() }
                SearchToolbarButton(isPresented: $isSearching)
                #endif
                Menu("Add Music", systemImage: "plus") {
                    Button("Import Songs", systemImage: "music.note") { importMode = .files }
                    Button("Import a Folder", systemImage: "folder") { importMode = .folder }
                    #if os(macOS)
                    Button("Show Music Folder in Finder", systemImage: "folder.badge.gearshape") {
                        LibraryFolders.prepare()
                        NSWorkspace.shared.activateFileViewerSelecting([LibraryFolders.music])
                    }
                    #endif
                    Divider()
                    Button("Connect a Server", systemImage: "server.rack") { addsServer = true }
                }
                #if os(iOS)
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
                #endif
            }
        }
        .fileImporter(
            isPresented: Binding(get: { importMode != nil }, set: { if !$0 { importMode = nil } }),
            allowedContentTypes: importMode == .folder ? [.folder] : [.audio],
            allowsMultipleSelection: importMode != .folder
        ) { result in
            if case .success(let urls) = result {
                Task { await music.importItems(urls) }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showsSettings) { SettingsSheet() }
        #endif
        .sheet(isPresented: $addsServer) { ServerForm() }
        .refreshable {
            await music.scan()
            await music.servers.connectAll()
            music.forgetUnavailable()
        }
        // Sample data's suggestions stand in for a server's; nothing else here asks Apple Music.
        .task(id: player.isDemo) {
            guard player.isDemo, suggestionMode != .off else { return }
            await feed.loadFromYourArtists()
        }
        // The shelves made from your music, worked out when what they're made from changes
        // rather than on every redraw.
        .task(id: ShelvesKey(songs: music.index.tracks.count, played: feed.facts.count, downloads: music.downloads.items.count, mixes: feed.mixes.mixes.count)) {
            shelves = makeShelves()
        }
    }

    /// The crate for your own music: Motif Radio in the middle, starting in front, with this
    /// hour's mix and the rest of the day's either side, each only if enough of its songs are
    /// yours to play.
    private func crateCards(hasRadio: Bool) -> [ForYouCard] {
        var cards: [ForYouCard] = []
        if let lead = feed.mixes.rightNow, isPlayable(lead) { cards.append(.mix(lead)) }
        cards += feed.mixes.otherTimes.filter(isPlayable).map(ForYouCard.mix)
        if hasRadio { cards.insert(.station, at: cards.count / 2) }
        return cards
    }

    /// A mix with at least five of its songs in your music, as the shelf of mixes asks.
    private func isPlayable(_ mix: Mix) -> Bool {
        mix.songs.lazy.filter { music.track(for: HistorySong($0)) != nil }.prefix(5).count >= 5
    }

    /// The shelves made from your music, kept between redraws. See ``makeShelves()``.
    struct Shelves {
        var mixes: [Mix] = []
        var unplayed: [LocalTrack] = []
        var downloaded: [LocalTrack] = []
    }

    private struct ShelvesKey: Equatable {
        let songs: Int
        let played: Int
        let downloads: Int
        let mixes: Int
    }

    private func makeShelves() -> Shelves {
        let seed = FreshShuffle.dailySeed(for: .now, salt: "waiting")
        let unplayed = music.index.tracks.filter { feed.facts[$0.identity] == nil && music.isPlayable($0) }
        let onPhone = music.index.tracks.filter { !$0.isFromServer || music.downloads.isDownloaded($0.id) }
        // Songs on this iPhone: ones you haven't played first, then the ones you've played
        // least lately, a fresh order each day.
        let downloaded = FreshShuffle.order(
            onPhone,
            artist: \.artistKey,
            recentlyHeard: { feed.facts[$0.identity] != nil },
            seed: FreshShuffle.dailySeed(for: .now, salt: "downloads")
        )
        return Shelves(
            mixes: feed.mixes.mixes.filter { mix in
                mix.songs.lazy.filter { music.track(for: HistorySong($0)) != nil }.count >= 5
            },
            unplayed: Array(FreshShuffle.order(unplayed, artist: \.artistKey, seed: seed).prefix(15)),
            downloaded: Array(downloaded.prefix(15))
        )
    }

    @ViewBuilder
    private var content: some View {
        let servers = music.servers.onlineServers
        // Motif Radio plays from your music, and from what your servers find for you.
        let hasRadio = isRadioOn && (!music.index.isEmpty || !servers.isEmpty)
        let suggests = suggestionMode != .off
        let crate = crateCards(hasRadio: hasRadio)
        // The crate leads, as on Apple Music's Play: Motif Radio, this hour's mix, the rest of
        // the day's. With fewer than two records there's nothing to flip through.
        let hasCrate = crate.count > 1
        if hasCrate {
            Crate(cards: crate, leadID: crate.contains { $0.id == "station" } ? "station" : crate.first { if case .mix = $0 { true } else { false } }?.id)
        }
        let radioInSuggestions = hasRadio && !hasCrate
        if player.isDemo, suggests {
            // Sample data has no server: its suggestions stand in, from the sample catalog.
            SuggestedSongsSection(includesRadio: radioInSuggestions)
        } else if suggests, !servers.isEmpty {
            // Songs by artists new to you your server found.
            ForEach(servers) { server in
                ServerForYouSection(server: server, shelf: .suggested, includesRadio: radioInSuggestions)
            }
        } else if radioInSuggestions {
            MotifRadioRow()
                .padding(.horizontal, PlayMetrics.margin)
        }

        if suggests {
            ForEach(servers) { server in
                ServerForYouSection(server: server, shelf: .picks)
            }
        }

        if !shelves.downloaded.isEmpty {
            Shelf(title: String(localized: "From Your Downloads"), items: shelves.downloaded) {
                HStack(spacing: 16) {
                    ShuffleDownloadsButton()
                        .labelStyle(.iconOnly)
                    NavigationLink(String(localized: "Manage"), value: PlayRoute.yourMusic(.downloads))
                }
            } tile: { track in
                LocalTrackTile(track: track, queue: shelves.downloaded, context: .songs(String(localized: "From Your Downloads")))
            }
        }

        let recent = Array(music.index.recentlyAdded.prefix(15))
        if !recent.isEmpty {
            Shelf(title: String(localized: "Recently Added"), items: recent) {
                NavigationLink(String(localized: "See All"), value: PlayRoute.yourMusic(.albums))
            } tile: { album in
                LocalAlbumTile(album: album)
            }
        }

        // The mixes the crate doesn't already hold.
        let shelfMixes = shelves.mixes.filter { mix in !(hasCrate && crate.contains { $0.id == mix.id }) }
        if !shelfMixes.isEmpty {
            Shelf(title: String(localized: "Made from Your Listening"), items: shelfMixes) { mix in
                MixTile(mix: mix)
            }
        }

        MoodShelf()

        if !shelves.unplayed.isEmpty {
            Shelf(title: String(localized: "Waiting to Be Heard"), items: shelves.unplayed) { track in
                LocalTrackTile(track: track, queue: shelves.unplayed, context: .songs(String(localized: "Waiting to Be Heard")))
            }
        }

        ForEach(servers) { server in
            ServerShelves(server: server)
        }

        LibraryList()
            .padding(.horizontal, PlayMetrics.margin)

        VStack(alignment: .leading, spacing: 6) {
            Text("Every song you play here is kept in your history, just like Apple Music's.")
            #if os(macOS)
            Text("You can also put music in Motif's Music folder: choose Show Music Folder in Finder from Add Music.")
            #else
            Text("You can also put music in On My iPhone › Motif › Music in the Files app.")
            #endif
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, PlayMetrics.margin)

        // One endless list at the bottom: what you have and haven't played, and more your
        // servers find for you.
        if player.isDemo, suggests {
            KeepExploringSection()
        } else if !servers.isEmpty {
            ServerExploring()
        }
    }
}

/// A song of yours on a shelf: plays the shelf from it.
struct LocalTrackTile: View {
    let track: LocalTrack
    let queue: [LocalTrack]
    let context: PlayContext
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Button {
            player.play(.local(queue, startingAt: queue.firstIndex(of: track) ?? 0), from: context)
        } label: {
            TileLabel(title: track.title, subtitle: track.artist) { side in
                LocalCover(artwork: track.artwork, seed: track.album ?? track.title, size: side)
            }
        }
        .buttonStyle(.pressable)
        .contextMenu { LocalTrackMenu(track: track, showsStats: true) }
    }
}

/// Songs, Albums, Artists and Downloaded, with how many of each.
private struct LibraryList: View {
    @Environment(YourMusic.self) private var music
    @Environment(Lidarr.self) private var lidarr

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(YourMusicList.allCases) { list in
                    NavigationLink(value: PlayRoute.yourMusic(list)) {
                        HStack(spacing: 14) {
                            Image(systemName: list.symbol)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            Text(list.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(count(list), format: .number)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(RowButtonStyle())
                    if list != YourMusicList.allCases.last || lidarr.isSetUp {
                        Divider().padding(.leading, 58)
                    }
                }
                if lidarr.isSetUp {
                    NavigationLink(value: PlayRoute.lidarr) {
                        HStack(spacing: 14) {
                            Image(systemName: "tray.and.arrow.down")
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                            Text("Lidarr")
                                .foregroundStyle(.primary)
                            Spacer()
                            if !lidarr.queue.isEmpty {
                                Text(String(localized: "\(lidarr.queue.count) downloading"))
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(.rect)
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            .background(Color.cardFill)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
        }
    }

    private func count(_ list: YourMusicList) -> Int {
        switch list {
        case .playlists: music.playlists.all.count
        case .songs: music.index.tracks.count
        case .albums: music.index.albums.count
        case .artists: music.index.artists.count
        case .downloads: music.downloads.items.count
        }
    }
}

/// What to do with an empty library: bring songs in, or connect a server.
private struct YourMusicWelcome: View {
    /// A server's been added, but can't be reached.
    var hasServers = false
    let importFiles: () -> Void
    let importFolder: () -> Void
    let addServer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: -10) {
                ForEach(["waveform", "folder.fill", "server.rack"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.gradient, in: .circle)
                        .overlay { Circle().stroke(Color.cardFill, lineWidth: 3) }
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                Button(action: importFiles) {
                    Label("Import Songs", systemImage: "music.note").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: importFolder) {
                    Label("Import a Folder", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: addServer) {
                    Label("Connect a Server", systemImage: "server.rack").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            Text(folderNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardFill, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var title: LocalizedStringKey {
        hasServers ? "Nothing Here Yet" : "Your Music, Your Way"
    }

    private var folderNote: LocalizedStringKey {
        #if os(macOS)
        "You can also drop music into Motif's Music folder, which Add Music shows in Finder. FLAC, ALAC, MP3, AAC, WAV and AIFF all play."
        #else
        "You can also drop music into On My iPhone › Motif › Music in the Files app. FLAC, ALAC, MP3, AAC, WAV and AIFF all play."
        #endif
    }

    private var message: LocalizedStringKey {
        #if os(macOS)
        hasServers
            ? "Your server can't be reached right now. Try again from Settings, or import songs to this Mac."
            : "Play the FLAC and other files you own, and music from your own server. Every song you play is kept in your history, with Motif Radio, mixes and moods made from all of it."
        #else
        hasServers
            ? "Your server can't be reached right now. Pull down to try again, or import songs to this iPhone."
            : "Play the FLAC and other files you own, and music from your own server. Every song you play is kept in your history, with Motif Radio, mixes and moods made from all of it."
        #endif
    }
}

/// "Added 12 songs", for a moment after an import.
private struct ImportBanner: View {
    let result: FileScanner.ImportResult

    var body: some View {
        Label(message, systemImage: result.added > 0 ? "checkmark.circle.fill" : "info.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
    }

    private var message: String {
        if result.added > 0 {
            return String(AttributedString(localized: "Added ^[\(result.added) song](inflect: true)").characters)
        }
        return result.skipped > 0 ? String(localized: "Already in your music") : String(localized: "No songs found to add")
    }
}

/// Searching your music: songs, albums and artists, from your files and servers, then songs
/// your servers have that aren't in your music yet, asked of them as you type.
struct YourMusicSearchResults: View {
    let query: String
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    @State private var fromServers: [LocalTrack] = []
    /// The search `fromServers` fully answers, so a newer one shows as still being asked.
    @State private var answeredQuery = ""
    /// A full search is taking a while, as Octo's do while it finds songs: said so.
    @State private var isSlow = false
    /// Where the next page of the search starts, on the servers that may have more.
    @State private var nextPage = ServerSearchPage()
    /// How many of `fromServers` are shown: a few at first, more as they're scrolled to.
    @State private var shownCount = Self.revealed

    /// Albums and artists your servers have, or a server like Octo finds, that aren't yours.
    @State private var serverAlbums: [ServerDiscovery.Album] = []
    @State private var serverArtists: [ServerArtist] = []

    /// How many songs from your servers show at a time.
    private static let revealed = 15

    var body: some View {
        let found = music.index.search(query)
        List {
            // Yours first, then your servers': up to five artists and eight albums.
            let artists = Array(found.artists.prefix(5))
            let moreArtists = Array(serverArtists.prefix(5 - artists.count))
            if !artists.isEmpty || !moreArtists.isEmpty {
                Section("Artists") {
                    ForEach(artists) { artist in
                        NavigationLink(value: PlayRoute.localArtist(artist.id)) {
                            artistRow(name: artist.name, artwork: artist.artwork)
                        }
                    }
                    ForEach(moreArtists) { artist in
                        NavigationLink(value: PlayRoute.serverArtist(artist)) {
                            artistRow(name: artist.name, artwork: artist.artwork)
                        }
                    }
                }
            }
            let albums = Array(found.albums.prefix(8))
            let moreAlbums = Array(serverAlbums.prefix(8 - albums.count))
            if !albums.isEmpty || !moreAlbums.isEmpty {
                Section("Albums") {
                    ForEach(albums) { album in
                        NavigationLink(value: PlayRoute.localAlbum(album.id)) {
                            albumRow(title: album.title, artist: album.artist, artwork: album.artwork)
                        }
                    }
                    ForEach(moreAlbums) { album in
                        NavigationLink(value: album.route) {
                            albumRow(title: album.title, artist: album.artist, artwork: album.artwork)
                        }
                    }
                }
            }
            if !found.tracks.isEmpty {
                Section("Songs") {
                    ForEach(found.tracks) { track in
                        Button {
                            let queue = found.tracks.filter(music.isPlayable)
                            player.play(.local(queue, startingAt: queue.firstIndex(of: track) ?? 0), from: .songs(query))
                        } label: {
                            LocalTrackRow(track: track, isCurrent: player.current?.local?.id == track.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(!music.isPlayable(track))
                        .contextMenu { LocalTrackMenu(track: track, showsStats: true) }
                    }
                }
            }
            let isAsking = answeredQuery != query && !music.servers.onlineServers.isEmpty
            if !fromServers.isEmpty || isAsking {
                let title: LocalizedStringKey = music.servers.onlineServers.count > 1 ? "More from Your Servers" : "More from Your Server"
                Section(title) {
                    ForEach(fromServers.prefix(shownCount)) { track in
                        Button {
                            player.play(.local(fromServers, startingAt: fromServers.firstIndex(of: track) ?? 0), from: .songs(query))
                        } label: {
                            LocalTrackRow(track: track, isCurrent: player.current?.local?.id == track.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { LocalTrackMenu(track: track) }
                        .swipeActions(edge: .leading) {
                            if !music.servers.isWaitingToKeep(track) {
                                Button("Add to Your Music", systemImage: "plus") {
                                    Task { player.confirm(await music.keep(track)) }
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                    // Still asking: the places of what's to come are held below what's here.
                    if isAsking {
                        if isSlow {
                            Text("Finding songs you don't have yet. This can take a few seconds.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                                .transition(.opacity)
                        }
                        LoadingRows(count: fromServers.isEmpty ? 3 : 2)
                            .listRowSeparator(.hidden)
                    } else if shownCount < fromServers.count || nextPage.hasMore {
                        // The end, scrolled to: more of what's here, then the next page.
                        LoadingRows(count: 1)
                            .listRowSeparator(.hidden)
                            .task(id: "\(shownCount).\(fromServers.count)") { await showMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if found.tracks.isEmpty, found.albums.isEmpty, found.artists.isEmpty, fromServers.isEmpty, serverAlbums.isEmpty, serverArtists.isEmpty,
               answeredQuery == query || music.servers.onlineServers.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        // Albums and artists, asked for as a pause in typing gives the songs time to be: quick even
        // on Octo, so they come well before the songs it finds.
        .task(id: query) {
            guard !music.servers.onlineServers.isEmpty,
                  query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                serverAlbums = []
                serverArtists = []
                return
            }
            let query = query
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            let found = await music.searchServerAlbumsAndArtists(query)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                serverAlbums = found.albums
                serverArtists = found.artists
            }
        }
        .task(id: query) {
            guard !music.servers.onlineServers.isEmpty else { return }
            let query = query
            isSlow = false
            shownCount = Self.revealed
            nextPage = ServerSearchPage()
            // A short pause so typing doesn't ask on every letter.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // First the songs your servers have, which even Octo answers at once…
            let quick = await music.searchServers(query, isFull: false)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { fromServers = quick.tracks }
            guard query.trimmingCharacters(in: .whitespaces).count >= 3 else {
                nextPage = quick
                answeredQuery = query
                return
            }
            // …then, once typing stops, the songs they can find for you. Octo takes seconds
            // to, so it's asked for the search you meant, not every word on the way to it.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let slow = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { isSlow = true }
            }
            defer { slow.cancel() }
            let found = await music.searchServers(query, isFull: true)
            guard !Task.isCancelled else { return }
            // What's shown stays where it is, and what's new joins below it.
            let shown = Set(quick.tracks.map(\.identity))
            withAnimation(.snappy) {
                fromServers = quick.tracks + found.tracks.filter { !shown.contains($0.identity) }
                nextPage = found
                answeredQuery = query
                isSlow = false
            }
            music.discover.warmCovers(Array(fromServers.prefix(shownCount)))
        }
    }

    private func artistRow(name: String, artwork: LocalTrack.Artwork?) -> some View {
        HStack(spacing: 12) {
            LocalCover(artwork: artwork, seed: name, size: 44, isCircle: true)
            Text(name)
        }
    }

    private func albumRow(title: String, artist: String, artwork: LocalTrack.Artwork?) -> some View {
        HStack(spacing: 12) {
            LocalCover(artwork: artwork, seed: title, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// Shows more of what's here, or, with all of it shown, asks for the next page. A page that
    /// brings nothing new, the library's matches being in your music already, ends the search.
    private func showMore() async {
        if shownCount < fromServers.count {
            withAnimation(.snappy) { shownCount += Self.revealed }
            return
        }
        guard nextPage.hasMore else { return }
        let query = query
        let page = await music.searchServers(query, after: nextPage)
        guard !Task.isCancelled, query == self.query else { return }
        let shown = Set(fromServers.map(\.identity))
        let new = page.tracks.filter { !shown.contains($0.identity) }
        withAnimation(.snappy) {
            fromServers += new
            nextPage = new.isEmpty ? ServerSearchPage() : page
            shownCount += Self.revealed
        }
    }
}
