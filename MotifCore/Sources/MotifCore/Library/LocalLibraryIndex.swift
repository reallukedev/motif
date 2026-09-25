import Foundation

/// An album of your own music: its songs in disc and track order.
public struct LocalAlbum: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String
    public let tracks: [LocalTrack]

    public init(id: String, title: String, artist: String, tracks: [LocalTrack]) {
        self.id = id
        self.title = title
        self.artist = artist
        self.tracks = tracks
    }

    public var year: Int? { tracks.compactMap(\.year).max() }
    public var genre: String? { tracks.lazy.compactMap(\.genre).first }
    public var artwork: LocalTrack.Artwork? { tracks.lazy.compactMap(\.artwork).first }
    public var addedAt: Date { tracks.map(\.addedAt).max() ?? .distantPast }
    public var duration: TimeInterval { tracks.compactMap(\.duration).reduce(0, +) }

    /// The best format on the album, for its badge: hi-res if any song is.
    public var format: AudioFormat? {
        let formats = tracks.compactMap(\.format)
        return formats.first(where: \.isHiRes) ?? formats.first(where: \.isLossless) ?? formats.first
    }

    /// The songs, first disc first, each disc in track order, untagged ones by title.
    static func ordered(_ tracks: [LocalTrack]) -> [LocalTrack] {
        tracks.sorted { lhs, rhs in
            let (leftDisc, rightDisc) = (lhs.discNumber ?? 1, rhs.discNumber ?? 1)
            if leftDisc != rightDisc { return leftDisc < rightDisc }
            switch (lhs.trackNumber, rhs.trackNumber) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// An artist in your own music, with their albums newest first.
public struct LocalArtist: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let albums: [LocalAlbum]

    public var tracks: [LocalTrack] { albums.flatMap(\.tracks) }
    public var artwork: LocalTrack.Artwork? { albums.lazy.compactMap(\.artwork).first }
}

/// Your own music, arranged: every song, grouped into albums and artists, searchable, and
/// matched to the history by song.
public struct LocalLibraryIndex: Sendable {
    public let tracks: [LocalTrack]
    public let albums: [LocalAlbum]
    public let artists: [LocalArtist]
    private let byID: [String: LocalTrack]
    private let byIdentity: [String: [LocalTrack]]

    public static let empty = LocalLibraryIndex(tracks: [])

    public init(tracks: [LocalTrack]) {
        // One song per id: a file and a download of the same server song stay apart, but
        // the same file indexed twice doesn't.
        var seen = Set<String>()
        let unique = tracks.filter { seen.insert($0.id).inserted }
        self.tracks = unique.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.byID = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        self.byIdentity = Dictionary(grouping: unique, by: \.identity)

        let albums = Dictionary(grouping: unique, by: \.albumKey).map { key, tracks in
            let ordered = LocalAlbum.ordered(tracks)
            let first = ordered[0]
            return LocalAlbum(id: key, title: first.album ?? first.title, artist: first.albumArtistName, tracks: ordered)
        }
        self.albums = albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        self.artists = Dictionary(grouping: albums, by: { StatsCalculator.folded($0.artist) })
            .map { key, albums in
                LocalArtist(
                    id: key,
                    name: albums[0].artist,
                    albums: albums.sorted { ($0.year ?? 0, $0.title) > ($1.year ?? 0, $1.title) }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var isEmpty: Bool { tracks.isEmpty }

    public func track(id: String) -> LocalTrack? { byID[id] }

    public func album(id: String) -> LocalAlbum? { albums.first { $0.id == id } }

    public func artist(id: String) -> LocalArtist? { artists.first { $0.id == id } }

    /// The song in your own music a history song stands for: by its id when it was played from
    /// here, otherwise by title and artist, a file before a server's copy.
    public func track(forSongID songID: String, identity: String) -> LocalTrack? {
        if let exact = byID[songID] { return exact }
        let matches = byIdentity[identity] ?? []
        return matches.first { !$0.isFromServer } ?? matches.first
    }

    /// Every copy of a song, by its ``LocalTrack/identity``: a file, a server's, a download.
    public func tracks(withIdentity identity: String) -> [LocalTrack] {
        byIdentity[identity] ?? []
    }

    /// Songs from elsewhere, a server's search say, that aren't in this library by id or by
    /// title and artist. Each song once, in the order given.
    public func notIncluded(_ tracks: [LocalTrack]) -> [LocalTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            byID[track.id] == nil && byIdentity[track.identity] == nil && seen.insert(track.identity).inserted
        }
    }

    /// Albums added most recently first.
    public var recentlyAdded: [LocalAlbum] {
        albums.sorted { $0.addedAt > $1.addedAt }
    }

    /// Songs, albums and artists whose names hold every word searched for, ignoring case and
    /// accents.
    public func search(_ query: String, limit: Int = 50) -> (tracks: [LocalTrack], albums: [LocalAlbum], artists: [LocalArtist]) {
        let words = StatsCalculator.folded(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ([], [], []) }
        func matches(_ fields: [String?]) -> Bool {
            let haystack = StatsCalculator.folded(fields.compactMap(\.self).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
        return (
            Array(tracks.filter { matches([$0.title, $0.artist, $0.album]) }.prefix(limit)),
            Array(albums.filter { matches([$0.title, $0.artist]) }.prefix(limit)),
            Array(artists.filter { matches([$0.name]) }.prefix(limit))
        )
    }
}
