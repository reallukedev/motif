import SwiftUI
import MotifCore

/// A mix on the shelf: its covers, its name and why.
struct MixTile: View {
    let mix: Mix
    @Environment(PlayerModel.self) private var player

    var body: some View {
        NavigationLink(value: PlayRoute.mix(mix.id)) {
            TileLabel(title: mix.kind.title, subtitle: mix.kind.tileLine) { side in
                MixCover(mix: mix, size: side)
            }
        }
        .buttonStyle(.pressable)
        .contextMenu {
            let songs = player.songs(in: mix)
            let context = PlayContext(kind: .mix, title: mix.kind.title)
            Button("Play", systemImage: "play") { player.play(.history(songs), from: context) }
            Button("Shuffle", systemImage: "shuffle") { player.play(.history(songs), from: context, shuffled: true) }
            Divider()
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.history(songs), next: true, title: mix.kind.title)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.history(songs), next: false, title: mix.kind.title)
            }
        }
    }
}

/// A station, album or playlist on a shelf. Stations start playing; the rest open.
struct FeedTile: View {
    let item: FeedItem
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Group {
            if let (request, context) = item.stationRequest {
                Button {
                    player.play(request, from: context)
                } label: {
                    label
                }
                .accessibilityHint("Plays the station")
            } else if let route {
                NavigationLink(value: route) { label }
            }
        }
        .buttonStyle(.pressable)
        .contextMenu { FeedItemMenu(item: item) }
    }

    private var label: some View {
        TileLabel(title: item.title, subtitle: item.subtitle) { side in
            CoverImage(cover: item.cover, size: side)
                .overlay(alignment: .topLeading) {
                    if item.isLive {
                        LiveBadge().padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isPlayingThis {
                        NowPlayingBadge().padding(8)
                    }
                }
        }
    }

    private var isPlayingThis: Bool {
        guard item.isStation, let context = player.context, context.isStation else { return false }
        return context.title == item.title && player.hasQueue
    }

    private var route: PlayRoute? {
        switch item.content {
        case .album(let album): .album(album)
        case .playlist(let playlist): .playlist(playlist)
        case .station, .demoStation: nil
        }
    }
}

/// Everything that can be done with a station, album or playlist, for its context menu.
struct FeedItemMenu: View {
    let item: FeedItem
    @Environment(PlayerModel.self) private var player

    var body: some View {
        switch item.content {
        case .station, .demoStation:
            if let (request, context) = item.stationRequest {
                Button("Play Station", systemImage: "play") { player.play(request, from: context) }
            }
        case .album(let album):
            let context = PlayContext(kind: .album, title: album.title)
            Button("Play", systemImage: "play") { player.play(.album(album), from: context) }
            Button("Shuffle", systemImage: "shuffle") { player.play(.album(album), from: context, shuffled: true) }
            Divider()
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.album(album), next: true, title: album.title)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.album(album), next: false, title: album.title)
            }
        case .playlist(let playlist):
            let context = PlayContext(kind: .playlist, title: playlist.name)
            Button("Play", systemImage: "play") { player.play(.playlist(playlist), from: context) }
            Button("Shuffle", systemImage: "shuffle") { player.play(.playlist(playlist), from: context, shuffled: true) }
            Divider()
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.playlist(playlist), next: true, title: playlist.name)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.playlist(playlist), next: false, title: playlist.name)
            }
        }
    }
}

/// Bars that move while this is what's playing, as on Music's covers.
struct NowPlayingBadge: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
            .frame(width: 26, height: 26)
            .background(.black.opacity(0.45), in: .circle)
            .accessibilityLabel("Now Playing")
    }
}
