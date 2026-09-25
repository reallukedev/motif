import SwiftUI
import MotifCore

/// Plays songs from a chart where the app plays songs: in Motif's own player, or handed to
/// Apple Music when Settings sends them there.
struct ChartPlayback: DynamicProperty {
    @Environment(\.playSongs) private var playSongs
    @Environment(PlaybackController.self) private var playback
    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var model

    /// The songs that can be played: Motif's player knows sample songs by name, Apple Music
    /// needs a song the catalog identified.
    func playable(_ songs: [MixSong]) -> [MixSong] {
        if playSongs != nil {
            return songs.filter { player.canPlay(songID: $0.songID) }
        }
        return model.isShowingSampleData ? [] : songs.filter { !$0.songID.isEmpty }
    }

    func play(_ songs: [MixSong], shuffled: Bool = false, title: String) {
        let items = playable(songs).map {
            PlaybackItem(songID: $0.songID, title: $0.title, artistName: $0.artistName)
        }
        guard !items.isEmpty else { return }
        let ordered = shuffled ? items.shuffled() : items
        if let playSongs {
            playSongs(ordered, title: title)
        } else {
            Task { await playback.play(ordered) }
        }
    }

    /// Play Next and Play Last, which only Motif's player has.
    var canQueue: Bool { playSongs != nil }

    func enqueue(_ song: MixSong, next: Bool) {
        player.enqueue(.history([HistorySong(song)]), next: next, title: song.title)
    }
}

/// A chart entry's menu: play a song, queue it, or open its stats where the row itself doesn't.
struct ChartEntryMenu: View {
    let entry: ChartEntry
    /// Your Stats, on the Mac, where a click only selects the row.
    var openStats: (() -> Void)?
    private var playback = ChartPlayback()

    var body: some View {
        if let song = entry.song, !playback.playable([song]).isEmpty {
            Button("Play", systemImage: "play") {
                playback.play([song], title: song.title)
            }
            if playback.canQueue {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    playback.enqueue(song, next: true)
                }
                Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                    playback.enqueue(song, next: false)
                }
            }
            if openStats != nil { Divider() }
        }
        if let openStats {
            Button("Your Stats", systemImage: "chart.bar.xaxis", action: openStats)
        }
    }
}
