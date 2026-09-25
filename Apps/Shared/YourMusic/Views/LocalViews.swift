import SwiftUI
import MotifCore

/// The lists of everything in your music, each a page of its own.
enum YourMusicList: String, Hashable, CaseIterable, Identifiable {
    case playlists, songs, albums, artists, downloads

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .playlists: "Playlists"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .downloads: "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.microphone"
        case .downloads: "arrow.down.circle"
        }
    }

    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .playlists: PlaylistsPage()
        case .songs: LocalSongsPage()
        case .albums: LocalAlbumsPage()
        case .artists: LocalArtistsPage()
        case .downloads: DownloadsPage()
        }
    }
}

/// A cover from your music: a saved picture, the server's, or a generated one.
struct LocalCover: View {
    let artwork: LocalTrack.Artwork?
    let seed: String
    var size: CGFloat?
    var isCircle = false
    @Environment(YourMusic.self) private var music

    var body: some View {
        ArtworkView(
            url: music.artworkURL(artwork)?.absoluteString,
            seed: seed,
            size: size,
            isCircle: isCircle,
            maximumCornerRadius: CoverImage.maximumRadius
        )
    }
}

/// How a song is encoded, as Music marks Lossless: "Hi-Res Lossless", "Lossless", or the
/// codec and bit rate of anything else.
struct FormatBadge: View {
    let format: AudioFormat
    /// On Now Playing's coloured field rather than the page.
    var onDark = false
    var showsDetail = false

    var body: some View {
        HStack(spacing: 4) {
            if format.isLossless {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.bold))
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(onDark ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        .background(onDark ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
        .accessibilityLabel(Text(spoken))
    }

    private var label: String {
        if format.isHiRes {
            return showsDetail ? "Hi-Res Lossless · \(format.detail ?? "")" : String(localized: "Hi-Res Lossless")
        }
        if format.isLossless {
            if showsDetail, let detail = format.detail { return "\(format.codec) · \(detail)" }
            return String(localized: "Lossless")
        }
        return [format.codec, format.detail].compactMap(\.self).joined(separator: " · ")
    }

    private var spoken: String {
        [label, format.isLossless ? format.detail : nil].compactMap(\.self).joined(separator: ", ")
    }
}

/// An album of yours on a shelf or in a grid.
struct LocalAlbumTile: View {
    let album: LocalAlbum
    var side: CGFloat?

    var body: some View {
        NavigationLink(value: PlayRoute.localAlbum(album.id)) {
            TileLabel(title: album.title, subtitle: album.artist) { tileSide in
                LocalCover(artwork: album.artwork, seed: album.title, size: side ?? tileSide)
            }
            .frame(width: side)
        }
        .buttonStyle(.pressable)
        .contextMenu { LocalAlbumMenu(album: album) }
    }
}

/// A song of yours in a list: cover or number, title, artist, whether it's here to play
/// offline, and your plays.
struct LocalTrackRow: View {
    let track: LocalTrack
    var number: Int?
    var showsCover = true
    var showsArtist = true
    var isCurrent = false

    @Environment(YourMusic.self) private var music
    @Environment(PlayFeed.self) private var feed
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var coverSide: CGFloat = 48

    var body: some View {
        let isPlayable = music.isPlayable(track)
        let plays = feed.facts[track.identity]?.plays ?? 0
        HStack(spacing: 12) {
            if showsCover {
                LocalCover(artwork: track.artwork, seed: track.album ?? track.title, size: min(coverSide, 72))
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: CoverImage.radius(for: min(coverSide, 72)), style: .continuous)
                                .fill(.black.opacity(0.4))
                            playingGlyph.foregroundStyle(.white)
                        }
                    }
            } else if let number {
                Group {
                    if isCurrent {
                        playingGlyph.foregroundStyle(.tint)
                    } else {
                        Text(number, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if showsArtist {
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            DownloadStateIcon(track: track)
            if plays > 0 {
                Text(PlayCountText.short(plays))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(PlayCountText.spoken(plays))
            }
        }
        .frame(minHeight: 44)
        .opacity(isPlayable ? 1 : 0.4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isPlayable ? "" : String(localized: "Not downloaded, and its server can't be reached"))
    }

    private var playingGlyph: some View {
        Image(systemName: "waveform")
            .font(.subheadline.weight(.semibold))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
            .accessibilityLabel("Now Playing")
    }
}

/// A server song's download, while it's under way: a ring turning while the song's being got
/// (by its server, for a song found for you, or queued to come down), then filling as it comes
/// down. Nothing once it's here: a downloaded song just plays. Follows the song into your music
/// once its server has kept it, so a row found before then shows the download too.
struct DownloadStateIcon: View {
    let track: LocalTrack
    @Environment(YourMusic.self) private var music

    var body: some View {
        let copy = music.resolved(track)
        Group {
            if !copy.isFromServer {
                EmptyView()
            } else if music.downloads.isWaitingForWiFi(copy.id, onCellular: music.network.isExpensive) {
                // Queued, and starts by itself back on Wi-Fi.
                Image(systemName: "wifi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Waiting for Wi-Fi")
            } else if let progress = music.downloads.progress[copy.id] {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.04, progress))
                        .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
                .animation(.linear(duration: 0.2), value: progress)
                .accessibilityLabel("Downloading")
                .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            } else if music.downloads.isDownloaded(copy.id) {
                EmptyView()
            } else if music.downloads.isDownloading(copy.id) || music.servers.isWaitingToKeep(copy) {
                TurningRing()
                    .accessibilityLabel(music.servers.isWaitingToKeep(copy) ? "Getting from Your Server" : "Waiting to Download")
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
        .animation(.snappy, value: stateKey(copy))
    }

    /// Changes between states animate; progress within one doesn't restart the transition.
    private func stateKey(_ track: LocalTrack) -> Int {
        if music.downloads.isWaitingForWiFi(track.id, onCellular: music.network.isExpensive) { return 4 }
        if music.downloads.progress[track.id] != nil { return 1 }
        if music.downloads.isDownloaded(track.id) { return 2 }
        if music.downloads.isDownloading(track.id) || music.servers.isWaitingToKeep(track) { return 3 }
        return 0
    }
}

/// Asks a song's server to keep it, for a song found on a server that doesn't have it yet;
/// once asked, says it's waiting.
struct AddToYourMusicButton: View {
    let track: LocalTrack
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if music.servers.isWaitingToKeep(track) {
            Label("Waiting for Your Server", systemImage: "clock")
        } else {
            Button("Add to Your Music", systemImage: "plus.circle") {
                Task { player.confirm(await music.keep(track)) }
            }
        }
    }
}

/// Everything that can be done with one of your songs.
struct LocalTrackMenu: View {
    let track: LocalTrack
    /// Where Go to Album and Go to Artist go; the stack the menu is in, unless given.
    var onNavigate: ((PlayRoute) -> Void)?
    var showsStats = false
    /// Asks before deleting a file, where the page can ask.
    var onDelete: ((LocalTrack) -> Void)?

    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        if music.isPlayable(track) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.local([track]), next: true, title: track.title)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.local([track]), next: false, title: track.title)
            }
            Divider()
        }
        if track.isFromServer, !music.isInYourMusic(track) {
            // Found on a server that doesn't have it yet: ask it to keep the song, then it
            // joins your music like any other, to download and find on its album.
            AddToYourMusicButton(track: track)
        } else {
            if music.isRadioOnly(track) {
                #if os(macOS)
                Button("Keep on This Mac", systemImage: "pin") { music.keep(HistorySong(track)) }
                #else
                Button("Keep on iPhone", systemImage: "pin") { music.keep(HistorySong(track)) }
                #endif
            }
            if track.isFromServer {
                if music.downloads.isDownloaded(track.id) {
                    Button("Remove Download", systemImage: "trash") { music.downloads.remove([track.id]) }
                } else if music.downloads.isDownloading(track.id) {
                    Button("Stop Downloading", systemImage: "xmark.circle") { music.downloads.cancel([track.id]) }
                } else {
                    Button("Download", systemImage: "arrow.down.circle") { music.downloads.download([track]) }
                }
            }
            Button("Go to Album", systemImage: "square.stack") { go(.localAlbum(track.albumKey)) }
            Button("Go to Artist", systemImage: "music.microphone") { go(.localArtist(track.artistKey)) }
        }
        Button("Add to Playlist…", systemImage: "text.badge.plus") {
            music.playlists.picking = PlaylistPick(tracks: [track])
        }
        if showsStats {
            Button("Your Stats", systemImage: "chart.bar.xaxis") { go(.stats(.song(track.identity))) }
            Divider()
            SuggestLessButton(songIdentity: track.identity)
        }
        if let onDelete, !track.isFromServer {
            Divider()
            #if os(macOS)
            Button("Delete from This Mac", systemImage: "trash", role: .destructive) { onDelete(track) }
            #else
            Button("Delete from iPhone", systemImage: "trash", role: .destructive) { onDelete(track) }
            #endif
        }
    }

    private func go(_ route: PlayRoute) {
        if let onNavigate { onNavigate(route) } else { openPlayRoute(route) }
    }
}

/// What can be done with an album of yours from a long press.
struct LocalAlbumMenu: View {
    let album: LocalAlbum
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let playable = album.tracks.filter(music.isPlayable)
        if !playable.isEmpty {
            Button("Play", systemImage: "play") { player.play(.local(playable), from: PlayContext(kind: .album, title: album.title)) }
            Button("Shuffle", systemImage: "shuffle") { player.play(.local(playable), from: PlayContext(kind: .album, title: album.title), shuffled: true) }
            Divider()
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(.local(playable), next: true, title: album.title) }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { player.enqueue(.local(playable), next: false, title: album.title) }
        }
        let server = album.tracks.filter(\.isFromServer)
        if !server.isEmpty {
            Divider()
            if server.allSatisfy({ music.downloads.isDownloaded($0.id) }) {
                Button("Remove Download", systemImage: "trash") { music.downloads.remove(Set(server.map(\.id))) }
            } else {
                Button("Download", systemImage: "arrow.down.circle") { music.downloads.download(server) }
            }
        }
        Divider()
        Button("Add to Playlist…", systemImage: "text.badge.plus") {
            music.playlists.picking = PlaylistPick(tracks: album.tracks)
        }
    }
}

/// "12 songs, 48 minutes · 1.2 GB".
enum LocalFormat {
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
