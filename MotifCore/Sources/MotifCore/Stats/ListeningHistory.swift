import Foundation

/// All captures, sorted once, with the per-row facts that need the full history to work out
/// (first hearings and listening estimates). Build one when the store changes and pass it to
/// every calculation instead of re-sorting each time.
public struct ListeningHistory: Sendable {
    /// Oldest first.
    public let captures: [CaptureStat]
    public let seconds: [TimeInterval]
    /// Artist pictures by artist identity, from ``ArtistArtworkCache``.
    public let artistArtwork: [String: String]
    /// Genres and release years by song identity, from ``SongMetadataCache``. Songs not
    /// looked up yet are missing.
    public let songMetadata: [String: SongMetadata]
    let isFirstHearing: [Bool]
    let isFirstArtistHearing: [Bool]

    public init(
        _ captures: [CaptureStat],
        artistArtwork: [String: String] = [:],
        songMetadata: [String: SongMetadata] = [:]
    ) {
        self.artistArtwork = artistArtwork
        self.songMetadata = songMetadata
        let ordered = captures.sorted {
            ($0.capturedAt, $0.songIdentity) < ($1.capturedAt, $1.songIdentity)
        }
        self.captures = ordered
        self.seconds = ListeningEstimate.seconds(for: ordered)

        var songs = Set<String>()
        var artists = Set<String>()
        var firstSong = [Bool](repeating: false, count: ordered.count)
        var firstArtist = [Bool](repeating: false, count: ordered.count)
        for (index, capture) in ordered.enumerated() {
            firstSong[index] = songs.insert(capture.songIdentity).inserted
            if !capture.artistIdentity.isEmpty {
                firstArtist[index] = artists.insert(capture.artistIdentity).inserted
            }
        }
        self.isFirstHearing = firstSong
        self.isFirstArtistHearing = firstArtist
    }

    public var isEmpty: Bool { captures.isEmpty }

    public var first: CaptureStat? { captures.first }

    /// The same captures with new lookups attached. Skips the sort and the estimates.
    public func with(artistArtwork: [String: String], songMetadata: [String: SongMetadata]) -> ListeningHistory {
        ListeningHistory(copying: self, artistArtwork: artistArtwork, songMetadata: songMetadata)
    }

    private init(copying other: ListeningHistory, artistArtwork: [String: String], songMetadata: [String: SongMetadata]) {
        captures = other.captures
        seconds = other.seconds
        isFirstHearing = other.isFirstHearing
        isFirstArtistHearing = other.isFirstArtistHearing
        self.artistArtwork = artistArtwork
        self.songMetadata = songMetadata
    }

    /// The genre and release year of the capture at `index`, if they're known.
    func metadata(at index: Int) -> SongMetadata? {
        songMetadata[captures[index].songIdentity]
    }

    /// Indices of captures in `interval`, treated as half-open so a song at midnight belongs
    /// to one day only. `nil` means everything.
    public func indices(in interval: DateInterval?) -> Range<Int> {
        guard let interval else { return captures.indices }
        let lower = firstIndex { $0.capturedAt >= interval.start }
        let upper = firstIndex { $0.capturedAt >= interval.end }
        return lower..<max(lower, upper)
    }

    /// Binary search for the first capture matching a predicate that flips once.
    private func firstIndex(where predicate: (CaptureStat) -> Bool) -> Int {
        var low = 0
        var high = captures.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(captures[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
