import SwiftUI
import MusicKit
import MotifCore

/// An Apple Music playlist, yours or Apple's: its cover on a field of its colour, your history
/// with it, and its songs. Long ones load as you scroll.
struct PlaylistPage: View {
    let playlist: Playlist
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed
    @State private var loaded: Playlist?
    @State private var tracks: [Track] = []
    @State private var nextBatch: MusicItemCollection<Track>?
    @State private var isLoadingMore = false
    @State private var loadFailed = false
    @AppStorage(PlayPreferences.allowsExplicitKey) private var allowsExplicit = true

    var body: some View {
        let playlist = loaded ?? playlist
        let context = PlayContext(kind: .playlist, title: playlist.name)
        #if os(iOS)
        List {
            Section {
                header(playlist, context: context)
            }

            Section {
                if tracks.isEmpty, loaded == nil, !loadFailed {
                    LoadingRows()
                        .listRowSeparator(.hidden)
                } else if loaded != nil, tracks.isEmpty {
                    CollectionMessage(text: String(localized: "This playlist is empty."), systemImage: "music.note.list")
                }
                ForEach(shownTracks, id: \.index) { index, track in
                    Button {
                        playTrack(at: index, context: context)
                    } label: {
                        TrackRow(
                            title: track.title,
                            subtitle: track.artistName,
                            cover: track.artwork.map(CoverArt.artwork) ?? .url(nil, seed: track.albumTitle ?? track.title),
                            isExplicit: track.contentRating == .explicit,
                            isCurrent: isCurrent(track)
                        )
                    }
                    .buttonStyle(.plain)
                    .trackMenu { songMenu(track) }
                    .collectionRowInsets(hasCover: true)
                }
                // Loads the next page as the end of the list comes into view. A row of its own,
                // since with explicit songs off the last rows loaded may all be hidden.
                if nextBatch != nil {
                    LoadingRow()
                        .listRowSeparator(.hidden)
                        // A new identity per page, so it asks again if it's still in view after one.
                        .id(tracks.count)
                        .onAppear { Task { await loadMore() } }
                }
            } footer: {
                CollectionFooter(lines: footerLines)
            }

            if loadFailed {
                Section {
                    CollectionMessage(text: String(localized: "Couldn't load this playlist's songs. Check your connection and try again.")) {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .collectionPage(title: playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") { moreItems(playlist) }
            }
        }
        .task { await load() }
        #else
        CollectionMacLayout(hasNote: note(playlist) != nil) {
            header(playlist, context: context)
        } content: {
            macTracks(playlist, context: context)
        }
        .navigationTitle(playlist.name)
        .task { await load() }
        #endif
    }

    private func header(_ playlist: Playlist, context: PlayContext) -> some View {
        let isComplete = loaded != nil && nextBatch == nil
        return CollectionHeader(
            kind: .playlist,
            title: playlist.name,
            subtitle: playlist.curatorName,
            facts: isComplete ? CollectionFacts.line([CollectionFacts.length(count: tracks.count, seconds: tracks.compactMap(\.duration).reduce(0, +))]) : nil,
            // Only once every song has loaded: "9 of 100" would be wrong for a playlist of 300.
            note: note(playlist),
            tintCover: cover(playlist),
            canPlay: !(loaded != nil && tracks.isEmpty),
            play: { player.play(.playlist(playlist), from: context) },
            shuffle: { shuffle(playlist, context: context) }
        ) {
            moreItems(playlist)
        } cover: { side in
            CoverImage(cover: cover(playlist), size: side)
        }
    }

    private func cover(_ playlist: Playlist) -> CoverArt {
        playlist.artwork.map(CoverArt.artwork) ?? .url(nil, seed: playlist.name)
    }

    private func note(_ playlist: Playlist) -> String? {
        playlist.shortDescription ?? playlist.standardDescription.map { String($0.prefix(280)) }
    }

    @ViewBuilder
    private func moreItems(_ playlist: Playlist) -> some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.enqueue(.playlist(playlist), next: true, title: playlist.name)
        }
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
            player.enqueue(.playlist(playlist), next: false, title: playlist.name)
        }
        Divider()
        Button("Add to Library", systemImage: "plus") { player.addToLibrary(playlist) }
        if let url = playlist.url {
            Divider()
            ShareLink(item: url) { Label("Share Playlist", systemImage: "square.and.arrow.up") }
        }
    }

    @ViewBuilder
    private func songMenu(_ track: Track) -> some View {
        if case .song(let song) = track { SongMenu(song: song) }
    }

    #if os(macOS)
    @ViewBuilder
    private func macTracks(_ playlist: Playlist, context: PlayContext) -> some View {
        if tracks.isEmpty, loaded == nil, !loadFailed {
            LoadingRows(count: 8)
                .padding(.horizontal, PlayMetrics.margin)
                .padding(.top, 12)
        } else if loadFailed {
            CollectionMessage(text: String(localized: "Couldn't load this playlist's songs. Check your connection and try again.")) {
                Button("Try Again") { Task { await load() } }
            }
        } else if tracks.isEmpty {
            CollectionMessage(text: String(localized: "This playlist is empty."), systemImage: "music.note.list")
        } else {
            VStack(spacing: 0) {
                CollectionTable(
                    tracks: shownTracks.map { index, track in
                        CollectionTrack(
                            id: String(index),
                            position: index + 1,
                            number: index + 1,
                            title: track.title,
                            artist: track.artistName,
                            album: track.albumTitle ?? "",
                            plays: plays(of: track) ?? 0,
                            duration: track.duration ?? 0,
                            isExplicit: track.contentRating == .explicit,
                            isCurrent: isCurrent(track),
                            artwork: track.artwork.map(CoverArt.artwork)
                        )
                    },
                    play: { id in Int(id).map { playTrack(at: $0, context: context) } },
                    enqueue: { ids, next in
                        let songs = ids.compactMap(Int.init).compactMap { index -> Song? in
                            guard tracks.indices.contains(index), case .song(let song) = tracks[index] else { return nil }
                            return song
                        }
                        guard !songs.isEmpty else { return }
                        player.enqueue(.songs(songs), next: next, title: playlist.name)
                    },
                    onReachEnd: { Task { await loadMore() } }
                ) { row in
                    if let index = Int(row.id), tracks.indices.contains(index) {
                        songMenu(tracks[index])
                    }
                }
                if let hiddenNote {
                    Text(hiddenNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PlayMetrics.margin)
                        .padding(.vertical, 8)
                }
            }
        }
    }
    #endif

    private var history: CollectionHistory? {
        CollectionHistory.summary(
            songIdentities: tracks.map { HistoryImport.key(title: $0.title, artistName: $0.artistName) },
            facts: feed.facts
        )
    }

    #if os(macOS)
    /// Your plays, for the Mac table's Plays column.
    private func plays(of track: Track) -> Int? {
        feed.facts[HistoryImport.key(title: track.title, artistName: track.artistName)]?.plays
    }
    #endif

    private func isCurrent(_ track: Track) -> Bool {
        player.current?.songIdentity == HistoryImport.key(title: track.title, artistName: track.artistName)
    }

    /// "12 songs, 48 minutes" once they've all loaded, and any songs hidden.
    private var footerLines: [String] {
        var lines: [String] = []
        if loaded != nil, nextBatch == nil, !tracks.isEmpty {
            lines.append(TrackListFooter.summary(count: tracks.count, seconds: tracks.compactMap(\.duration).reduce(0, +)))
        }
        if let hiddenNote { lines.append(hiddenNote) }
        return lines
    }

    /// Every track with its place in the full list, less the explicit ones when they're off.
    /// Played by their place, so the queue lines up with the list either way.
    private var shownTracks: [(index: Int, track: Track)] {
        tracks.enumerated()
            .filter { allowsExplicit || $0.element.contentRating != .explicit }
            .map { (index: $0.offset, track: $0.element) }
    }

    /// "2 explicit songs hidden", when the setting hides some.
    private var hiddenNote: String? {
        let hidden = tracks.count - shownTracks.count
        guard hidden > 0 else { return nil }
        return String(AttributedString(localized: "^[\(hidden) explicit song](inflect: true) hidden. Turn on Explicit Songs in Settings to see them.").characters)
    }

    private func load() async {
        loadFailed = false
        if tracks.isEmpty, let known = playlist.tracks { tracks = Array(known) }
        do {
            let detailed = try await playlist.with([.tracks])
            loaded = detailed
            let first = detailed.tracks
            tracks = Array(first ?? [])
            nextBatch = first?.hasNextBatch == true ? first : nil
        } catch {
            loadFailed = tracks.isEmpty
        }
    }

    private func loadMore() async {
        guard let batch = nextBatch, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let more = try? await batch.nextBatch() else {
            nextBatch = nil
            return
        }
        tracks += more
        nextBatch = more.hasNextBatch ? more : nil
    }

    private var songs: [Song] {
        Self.songs(in: tracks).songs
    }

    /// The playable songs, and where each track landed among them. By position, since a
    /// playlist can hold one song twice.
    static func songs(in tracks: [Track]) -> (songs: [Song], positions: [Int: Int]) {
        var songs: [Song] = []
        var positions: [Int: Int] = [:]
        for (index, track) in tracks.enumerated() {
            guard case .song(let song) = track else { continue }
            positions[index] = songs.count
            songs.append(song)
        }
        return (songs, positions)
    }

    private func playTrack(at index: Int, context: PlayContext) {
        let (songs, positions) = Self.songs(in: tracks)
        guard let start = positions[index] else { return }
        let pending = nextBatch
        Task {
            await player.start(.songs(songs, startingAt: start), from: context)
            // Songs further down that haven't loaded yet join the queue as they arrive, so
            // playback doesn't stop at the end of the first page. Once playing has started, so
            // the check that the person hasn't moved on means something.
            guard let pending, player.context == context else { return }
            await queueRest(from: pending, context: context)
        }
    }

    private func queueRest(from batch: MusicItemCollection<Track>, context: PlayContext) async {
        var batch: MusicItemCollection<Track>? = batch
        var added = 0
        while let current = batch, added < 2_000, let more = try? await current.nextBatch() {
            // Stop if the person has moved on to something else.
            guard player.context == context else { return }
            let songs = Self.songs(in: Array(more)).songs
            if !songs.isEmpty { player.append(.songs(songs)) }
            added += songs.count
            batch = more.hasNextBatch ? more : nil
        }
    }

    /// Motif's own shuffle when every song is loaded: no artist twice in a row. Apple's
    /// shuffle otherwise, which can reach songs not loaded yet.
    private func shuffle(_ playlist: Playlist, context: PlayContext) {
        if loaded != nil, nextBatch == nil, !songs.isEmpty {
            player.play(.songs(songs), from: context, shuffled: true)
        } else {
            player.play(.playlist(playlist), from: context, shuffled: true)
        }
    }
}
