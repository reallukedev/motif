import SwiftUI
import MotifCore

/// Context menu items for a play in the history.
struct PlayActions: View {
    let capture: Capture
    var onDelete: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Environment(\.playSongs) private var playSongs
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !model.isShowingSampleData, !capture.songID.isEmpty {
            Button("Play", systemImage: "play") {
                if let playSongs {
                    playSongs([PlaybackItem(songID: capture.songID, title: capture.title, artistName: capture.artistName)], title: capture.title)
                } else {
                    Task { await playback.play(capture) }
                }
            }
            // There's no API for taking a song back out of a playlist, so we point at the
            // one app that can.
            Button("Show in Apple Music", systemImage: "arrow.up.forward.app") {
                if let url = URL(string: "https://music.apple.com/song/\(capture.songID)") {
                    openURL(url)
                }
            }
            Divider()
        }
        ShareLink(item: "\(capture.title) by \(capture.artistName)") {
            Label("Share Song", systemImage: "square.and.arrow.up")
        }
        if !model.isShowingSampleData {
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
        }
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
                Text("Removing the whole song also stops Motif recovering it from Recently Played. Scrobbles already sent stay on Last.fm.")
            } else {
                Text("Removing the whole song also stops Motif recovering it from Recently Played.")
            }
        }
    }
}

extension View {
    func deleteConfirmation(for capture: Binding<Capture?>) -> some View {
        modifier(DeleteConfirmation(capture: capture))
    }
}

/// Plays songs from the history in Motif's own player, where there is one.
///
/// The iPhone has one, on the Play tab, and sets this at the root so a song's page plays there
/// and every play is kept. The Mac leaves it unset and hands songs to Music.app.
struct PlaySongsAction {
    let run: @MainActor (_ items: [PlaybackItem], _ title: String) -> Void

    @MainActor
    func callAsFunction(_ items: [PlaybackItem], title: String) {
        run(items, title)
    }
}

extension EnvironmentValues {
    @Entry var playSongs: PlaySongsAction?
}
