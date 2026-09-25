import SwiftUI
import MusicKit
import MotifCore

/// Pushes a page onto the stack the view is in. Each stack that shows Apple Music content
/// sets one, so a context menu's Go to Album lands in the right place.
struct OpenPlayRouteAction: Equatable {
    /// Which stack, so two actions compare equal when they push onto the same one and views
    /// reading this aren't invalidated on every update.
    let stack: String
    let push: @MainActor (PlayRoute) -> Void

    @MainActor
    func callAsFunction(_ route: PlayRoute) {
        push(route)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stack == rhs.stack
    }
}

extension EnvironmentValues {
    @Entry var openPlayRoute = OpenPlayRouteAction(stack: "none") { _ in }
}

/// A song in a list: cover or track number, title, artist, and how often you've played it.
struct TrackRow: View {
    let title: String
    let subtitle: String?
    var cover: CoverArt?
    var number: Int?
    /// Your plays, from Motif's history. Shown when there are any.
    var plays: Int?
    var isExplicit = false
    var isCurrent = false
    /// A song of yours, for its download coming down.
    var localTrack: LocalTrack?
    /// Dimmed when it can't play: not downloaded and its server out of reach.
    var isPlayable = true

    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var coverSide: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        // At the largest sizes a title wraps rather than losing most of itself.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if isExplicit {
                        ExplicitBadge()
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // Separators start at the title, as in Music, not under the cover or number.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 8)
            if let localTrack {
                DownloadStateIcon(track: localTrack)
            }
            if let plays, plays > 0 {
                Text(PlayCountText.short(plays))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(PlayCountText.spoken(plays))
            }
        }
        .frame(minHeight: 44)
        .opacity(isPlayable ? 1 : 0.45)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var leading: some View {
        if let cover {
            CoverImage(cover: cover, size: min(coverSide, 72))
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
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: numberWidth)
        }
    }

    private var playingGlyph: some View {
        Image(systemName: "waveform")
            .font(.subheadline.weight(.semibold))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
            .accessibilityLabel("Now Playing")
    }
}

/// Music's "E" for explicit songs.
struct ExplicitBadge: View {
    var body: some View {
        Text(verbatim: "E")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.pageBackground)
            .frame(width: 14, height: 14)
            .background(.secondary, in: .rect(cornerRadius: 3, style: .continuous))
            .accessibilityLabel("Explicit")
    }
}

/// How a play count reads beside a song.
enum PlayCountText {
    /// "12 plays", short enough for the trailing edge of a row.
    static func short(_ plays: Int) -> String {
        String(AttributedString(localized: "^[\(plays) play](inflect: true)").characters)
    }

    static func spoken(_ plays: Int) -> String {
        String(AttributedString(localized: "You've played this ^[\(plays) time](inflect: true)").characters)
    }
}

extension Song {
    var isExplicit: Bool { contentRating == .explicit }
}

/// Everything that can be done with an Apple Music song, for its context menu.
struct SongMenu: View {
    let song: Song
    /// Hides Go to Album on the album's own page.
    var showsAlbum = true
    var showsArtist = true
    /// Off where the menu has its own way to say no, as suggestions do.
    var showsSuggestLess = true

    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.enqueue(.songs([song]), next: true, title: song.title)
        }
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
            player.enqueue(.songs([song]), next: false, title: song.title)
        }
        Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
            player.playStation(from: song)
        }
        Divider()
        Button("Add to Library", systemImage: "plus") {
            player.addToLibrary(song)
        }
        FavoriteMenuItem(song: song)
        if showsAlbum {
            Button("Go to Album", systemImage: "square.stack") {
                Task { if let album = await SongLinks.album(of: song) { openPlayRoute(.album(album)) } }
            }
        }
        if showsArtist {
            Button("Go to Artist", systemImage: "music.microphone") {
                Task { if let artist = await SongLinks.artist(of: song) { openPlayRoute(.artist(artist)) } }
            }
        }
        if let url = song.url {
            ShareLink(item: url) {
                Label("Share Song", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        if showsSuggestLess {
            SuggestLessButton(songIdentity: HistoryImport.key(title: song.title, artistName: song.artistName))
        }
    }
}

/// "Suggest Less", which keeps a song out of Motif's mixes. Undone from the same place.
struct SuggestLessButton: View {
    let songIdentity: String
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if player.isSuggestingLess(songIdentity) {
            Button("Suggest Again", systemImage: "hand.thumbsup") {
                player.setSuggestLess(songIdentity, false)
            }
        } else {
            Button("Suggest Less", systemImage: "hand.thumbsdown") {
                player.setSuggestLess(songIdentity, true)
            }
        }
    }
}

/// A history song's menu: the same actions, for a song known by id and name.
struct HistorySongMenu: View {
    let song: MixSong
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        if player.canPlay(songID: song.songID) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.history([HistorySong(song)]), next: true, title: song.title)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.history([HistorySong(song)]), next: false, title: song.title)
            }
            Divider()
        }
        Button("Your Stats", systemImage: "chart.bar.xaxis") {
            openPlayRoute(.stats(.song(song.songIdentity)))
        }
        Divider()
        SuggestLessButton(songIdentity: song.songIdentity)
    }
}

/// The album and artist a song belongs to, looked up when asked for.
enum SongLinks {
    static func album(of song: Song) async -> Album? {
        if let album = song.albums?.first { return album }
        return try? await song.with([.albums]).albums?.first
    }

    static func artist(of song: Song) async -> Artist? {
        if let artist = song.artists?.first { return artist }
        return try? await song.with([.artists]).artists?.first
    }
}
