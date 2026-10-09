import Foundation

/// Every song, artist and album in the history, tallied and folded once, ready to search.
///
/// Searching used to tally the whole history on every keystroke, three times over. With a
/// hundred and fifty thousand plays that was a couple of hundred milliseconds a letter. The
/// tallies only change when the history does, so build one of these per history and each
/// search is a pass over the tallies' prepared text.
public struct SearchIndex: Sendable {
    private struct Entry<Item: Sendable>: Sendable {
        let item: Item
        /// Folded, so a search only has to fold what was typed.
        let text: String
    }

    private let songs: [Entry<SongTally>]
    private let artists: [Entry<ArtistTally>]
    private let albums: [Entry<AlbumTally>]

    public init(history: ListeningHistory) {
        let all = history.captures.indices
        songs = StatsCalculator.tallySongs(all, in: history).map { song in
            let genre = history.songMetadata[song.id]?.genre ?? ""
            return Entry(
                item: song,
                text: StatsCalculator.folded("\(song.title) \(song.artistName) \(song.albumTitle ?? "") \(genre)")
            )
        }
        artists = StatsCalculator.tallyArtists(all, in: history).map { Entry(item: $0, text: $0.id) }
        albums = StatsCalculator.tallyAlbums(all, in: history).map {
            Entry(item: $0, text: StatsCalculator.folded("\($0.title) \($0.artistName)"))
        }
    }

    /// The most played artists of all time, for suggestions before anything is typed.
    public func topArtists(limit: Int) -> [ArtistTally] {
        artists.prefix(limit).map(\.item)
    }

    /// Matches every typed word, ignoring case and accents ("mara sol" finds Mara Solís).
    /// Songs match on their genre too, so "jazz" finds the jazz you've played. Most played
    /// first in each group.
    public func search(_ text: String, limit: Int = 25) -> SearchResults {
        let words = StatsCalculator.folded(text).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return .empty }

        func matches<Item>(_ entry: Entry<Item>) -> Bool {
            words.allSatisfy { entry.text.contains($0) }
        }
        func firstMatches<Item>(_ entries: [Entry<Item>]) -> [Item] {
            var found: [Item] = []
            for entry in entries where matches(entry) {
                found.append(entry.item)
                if found.count == limit { break }
            }
            return found
        }
        return SearchResults(
            songs: firstMatches(songs),
            artists: firstMatches(artists),
            albums: firstMatches(albums)
        )
    }
}
