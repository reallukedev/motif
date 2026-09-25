import SwiftUI
import MusicKit
import UniformTypeIdentifiers
import MotifCore

/// Songs being dragged: from a list or a table onto Up Next, the player, or a playlist.
///
/// Each song carries every way Motif has of finding it again, because where it came from
/// decides how it plays: a song of your own by its id in your music, an Apple Music library
/// song by its library id, anything else by its catalog id and name, as the history knows it.
nonisolated struct SongDrag: Codable, Hashable, Sendable, Transferable {
    struct Song: Codable, Hashable, Sendable {
        var songID: String = ""
        let title: String
        let artistName: String
        var albumTitle: String?
        /// An Apple Music library id, "i." and the like.
        var libraryID: String?
        /// ``MotifCore/LocalTrack/id``, for a song in your own music.
        var localID: String?
    }

    let songs: [Song]

    init(songs: [Song]) {
        self.songs = songs
    }

    init(_ songs: [HistorySong]) {
        self.songs = songs.map { Song(songID: $0.songID, title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle) }
    }

    init(_ tracks: [LocalTrack]) {
        self.songs = tracks.map { Song(title: $0.title, artistName: $0.artist, albumTitle: $0.album, localID: $0.id) }
    }

    /// "Wildflowers" for one song, "3 Songs" for more, for where it lands.
    var title: String {
        if songs.count == 1, let song = songs.first { return song.title }
        return String(AttributedString(localized: "^[\(songs.count) Song](inflect: true)").characters)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .motifSongs)
        // Anywhere else, the songs as text, a line each.
        ProxyRepresentation { drag in
            drag.songs.map { "\($0.title), \($0.artistName)" }.joined(separator: "\n")
        }
    }
}

extension SongDrag {
    /// What to hand the player for these songs: your own when every one is, Apple Music's
    /// library songs when they came from there, and the history's way otherwise.
    @MainActor
    func request(in music: YourMusic) async -> PlayRequest? {
        let local = songs.compactMap { $0.localID.flatMap(music.index.track(id:)) }
        if !local.isEmpty, local.count == songs.count {
            return .local(local)
        }
        let libraryIDs = songs.compactMap(\.libraryID).map { MusicItemID($0) }
        if !libraryIDs.isEmpty {
            var request = MusicLibraryRequest<MusicKit.Song>()
            request.filter(matching: \.id, memberOf: libraryIDs)
            guard let found = try? await request.response().items, !found.isEmpty else { return nil }
            // In the order they were dragged.
            let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return .songs(libraryIDs.compactMap { byID[$0] })
        }
        return .history(songs.map { HistorySong(songID: $0.songID, title: $0.title, artistName: $0.artistName, albumTitle: $0.albumTitle) })
    }
}

extension UTType {
    /// Songs dragged within Motif. Declared in both apps' Info.plist.
    nonisolated static let motifSongs = UTType(exportedAs: "com.luke.motif.songs")
}
