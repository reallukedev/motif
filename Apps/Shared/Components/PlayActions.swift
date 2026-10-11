import SwiftUI
import TracksCore

/// Context menu items for a play in the history: the song's own menu, with Show in Music and
/// Delete.
struct PlayActions: View {
    let capture: Capture
    var onDelete: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.openURL) private var openURL
    @Environment(\.openPlayRoute) private var openPlayRoute
    private var playback = CapturePlayback()

    init(capture: Capture, onDelete: @escaping () -> Void) {
        self.capture = capture
        self.onDelete = onDelete
    }

    var body: some View {
        SongMenuItems(actions)
    }

    private var actions: SongActions {
        let song = MixSong(capture)
        var actions = SongActions.history(song, player: player, go: openPlayRoute.ifPushes)
        let canPlay = playback.canPlay([capture])
        actions.play = canPlay ? { playback.play([capture]) } : nil
        actions.playNext = canPlay && playback.canQueue ? { playback.enqueue([capture], next: true) } : nil
        actions.playLast = canPlay && playback.canQueue ? { playback.enqueue([capture], next: false) } : nil
        if model.isShowingSampleData {
            actions.share = nil
        } else {
            if !capture.songID.isEmpty {
                // There's no API for taking a song back out of a playlist, so we point at the
                // one app that can.
                actions.reveal.append(SongMenuButton(title: "Show in Music", systemImage: "arrow.up.forward.app") {
                    if let url = URL(string: "https://music.apple.com/song/\(capture.songID)") { openURL(url) }
                })
            }
            actions.trailing.append(SongMenuButton(title: "Delete…", systemImage: "trash", role: .destructive, action: onDelete))
        }
        return actions
    }
}

/// Plays plays from the history where the app plays songs: in Tracks’ own player, or handed
/// to Music when Settings sends them there.
struct CapturePlayback: DynamicProperty {
    @Environment(\.playSongs) private var playSongs
    @Environment(PlaybackController.self) private var playback
    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var model

    /// Whether any of them can play: a song the catalog never identified can't.
    func canPlay(_ captures: [Capture]) -> Bool {
        !model.isShowingSampleData && captures.contains { !$0.songID.isEmpty }
    }

    func play(_ captures: [Capture]) {
        let items = captures.filter { !$0.songID.isEmpty }.map {
            PlaybackItem(songID: $0.songID, title: $0.title, artistName: $0.artistName)
        }
        guard let first = items.first else { return }
        if let playSongs {
            playSongs(items, title: items.count == 1 ? first.title : String(localized: "History"))
        } else if items.count == 1, let capture = captures.first(where: { !$0.songID.isEmpty }) {
            Task { await playback.play(capture) }
        } else {
            Task { await playback.play(items) }
        }
    }

    /// Play Next and Play Last, which only Tracks’ player has.
    var canQueue: Bool { playSongs != nil }

    func enqueue(_ captures: [Capture], next: Bool) {
        let songs = captures.filter { !$0.songID.isEmpty }.map {
            HistorySong(songID: $0.songID, title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle, artworkURL: $0.artworkURL)
        }
        guard let first = songs.first else { return }
        let title = songs.count == 1 ? first.title : String(AttributedString(localized: "^[\(songs.count) song](inflect: true)").characters)
        player.enqueue(.history(songs), next: next, title: title)
    }
}

extension MixSong {
    /// A play in the history, as a song.
    init(_ capture: Capture) {
        self.init(
            songIdentity: HistoryImport.key(title: capture.title, artistName: capture.artistName),
            songID: capture.songID,
            title: capture.title,
            artistName: capture.artistName,
            albumTitle: capture.albumTitle,
            artworkURL: capture.artworkURL,
            plays: 0,
            lastHeard: capture.capturedAt,
            genre: nil
        )
    }
}

/// Asks whether to delete one play or the whole song, then does it.
struct DeleteConfirmation: ViewModifier {
    @Binding var capture: Capture?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(capture?.title ?? "")?",
            isPresented: Binding(
                get: { capture != nil },
                set: { if !$0 { capture = nil } }
            ),
            titleVisibility: .visible,
            presenting: capture
        ) { capture in
            Button("Delete This Play", role: .destructive) {
                try? model.store?.deletePlay(capture)
            }
            Button("Remove Song from History", role: .destructive) {
                // Taken out of the row before the task, which may outlive it.
                let (title, artistName) = (capture.title, capture.artistName)
                Task { _ = try? await model.store?.forgetSong(title: title, artistName: artistName) }
            }
        } message: { capture in
            if capture.scrobbledAt != nil {
                Text("Removing the whole song also stops Tracks recovering it from Recently Played. Scrobbles already sent stay on Last.fm.")
            } else {
                Text("Removing the whole song also stops Tracks recovering it from Recently Played.")
            }
        }
    }
}

extension View {
    func deleteConfirmation(for capture: Binding<Capture?>) -> some View {
        modifier(DeleteConfirmation(capture: capture))
    }
}

/// Plays songs from the history in Tracks’ own player, where there is one.
///
/// The iPhone has one, on the Play tab, and sets this at the root so a song's page plays there
/// and every play is kept. The Mac leaves it unset and hands songs to Music.app.
struct PlaySongsAction: Equatable {
    let run: @MainActor (_ items: [PlaybackItem], _ title: String) -> Void

    /// Every one plays in the same player. Whether there's one at all is the Optional around it,
    /// so a root view redrawing on each play doesn't redraw every page that reads it.
    static func == (lhs: Self, rhs: Self) -> Bool { true }

    @MainActor
    func callAsFunction(_ items: [PlaybackItem], title: String) {
        run(items, title)
    }
}

extension EnvironmentValues {
    @Entry var playSongs: PlaySongsAction?
}
