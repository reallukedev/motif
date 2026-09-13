import SwiftUI
import MotifCore

/// Context menu items for a play in the history.
struct PlayActions: View {
    let capture: Capture
    var onDelete: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !model.isShowingSampleData, !capture.songID.isEmpty {
            Button("Play", systemImage: "play") {
                Task { await playback.play(capture) }
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
            item: $capture,
            titleVisibility: .visible
        ) { capture in
            Button("Delete This Play", role: .destructive) {
                try? model.activeStore?.deletePlay(capture)
            }
            Button("Remove Song from History", role: .destructive) {
                _ = try? model.activeStore?.forgetSong(title: capture.title, artistName: capture.artistName)
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
