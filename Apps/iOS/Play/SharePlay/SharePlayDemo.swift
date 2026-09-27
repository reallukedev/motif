#if DEBUG
import Foundation
import MusicKit
import MotifCore

/// Pretend SharePlay sessions over sample data, since the simulator can't run real ones.
/// `-MotifSharePlayDemo` names the scene:
///
///     host              hosting, with two people joined and one of their songs in Up Next
///     guest             joined someone's, with what they're playing
///     guest.joining     still waiting to hear from the host
///     guest.ended       the host ended it
///     guest.station     the host is playing a station
///     guest.yourmusic   the host is playing its own music
///     guest.noaccess    this iPhone hasn't allowed Apple Music
///     guest.offline     searching fails
///
/// `-MotifSharePlaySearch "sun"` types a search on the guest page, and marks one result added
/// and another not.
@MainActor
final class SharePlayDemo {
    let scene: String
    /// Every sample song, to search.
    private var songs: [SharePlaySong] = []

    init(scene: String) {
        self.scene = scene
    }

    var isOffline: Bool { scene == "guest.offline" }
    var deniesAccess: Bool { scene == "guest.noaccess" }

    func start(in controller: SharePlayController, model: AppModel) {
        Task {
            // The sample mixes are built a moment after launch.
            for _ in 0..<80 where model.playFeed.mixes.mixes.isEmpty || (scene == "host" && model.player.upNext.count < 2) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            songs = Self.songs(in: model)
            if scene == "host" {
                var ledger = SharePlayLedger()
                if model.player.upNext.count > 1 { ledger.record(model.player.upNext[1].songIdentity) }
                controller.pretend(role: .host, guestCount: 2, ledger: ledger)
                return
            }
            controller.pretend(role: .guest)
            guard scene != "guest.joining" else { return }
            let snapshot = snapshot()
            controller.pretendGuest { $0.receive(snapshot) }
            if let term = LaunchScene.sharePlaySearch {
                let found = search(term)
                controller.pretendGuest { guest in
                    if found.count > 0, let request = guest.add(found[0], placement: .last, at: .now) {
                        guest.receive(SharePlayAddReply(requestID: request.id, outcome: .added(.last)))
                    }
                    if found.count > 2, let request = guest.add(found[2], placement: .last, at: .now) {
                        guest.receive(SharePlayAddReply(requestID: request.id, outcome: .refused(.notFound)))
                    }
                }
            }
            if scene == "guest.ended" {
                controller.pretendGuest { $0.end() }
            }
        }
    }

    /// The host's side, played out: in after a moment, like the real thing.
    func answer(_ request: SharePlayAddRequest, in controller: SharePlayController) {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            controller.pretendGuest { $0.receive(SharePlayAddReply(requestID: request.id, outcome: .added(request.placement))) }
        }
    }

    /// Sample songs whose title or artist starts a word with what was typed.
    func search(_ term: String) -> [SharePlaySong] {
        let folded = StatsCalculator.folded(term.trimmingCharacters(in: .whitespaces))
        guard !folded.isEmpty else { return [] }
        return songs.filter { song in
            "\(song.title) \(song.artistName)".split(separator: " ").contains { StatsCalculator.folded(String($0)).hasPrefix(folded) }
        }
        .prefix(20)
        .map(\.self)
    }

    private func snapshot() -> SharePlaySnapshot {
        let tracks = songs.dropFirst(3).prefix(9).enumerated().map { index, song in
            SharePlayTrack(id: "demo-\(index)", title: song.title, artistName: song.artistName, artworkURL: song.artworkURL, isFromSharePlay: index == 1)
        }
        let now = songs.first.map { SharePlayTrack(id: "demo-now", title: $0.title, artistName: $0.artistName, artworkURL: $0.artworkURL) }
        return SharePlaySnapshot(
            nowPlaying: now,
            isPlaying: true,
            upNext: scene == "guest.station" ? [] : tracks,
            upNextCount: scene == "guest.station" ? 0 : 23,
            source: scene == "guest.yourmusic" ? .yourMusic : .appleMusic,
            isStation: scene == "guest.station"
        )
    }

    private static func songs(in model: AppModel) -> [SharePlaySong] {
        var seen = Set<String>()
        return model.playFeed.mixes.all.flatMap(\.songs).compactMap { song in
            let item = SharePlaySong(catalogID: song.songID.isEmpty ? song.songIdentity : song.songID, title: song.title, artistName: song.artistName, albumTitle: song.albumTitle, artworkURL: song.artworkURL)
            return seen.insert(item.identity).inserted ? item : nil
        }
    }
}
#endif
