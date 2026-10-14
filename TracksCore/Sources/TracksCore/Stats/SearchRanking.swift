import Foundation

/// What a search's Top Result is: the one card above the rest, as Music shows it.
public enum SearchTopKind: Sendable, Equatable {
    case artist, album, song
}

public enum SearchRanking {
    /// The best match for what was typed, given the first artist, album and song each search
    /// found, or nil when there's nothing to show.
    ///
    /// A name typed in full wins outright, an artist's before an album's, so "tides" finds the
    /// album Tides rather than the artist Tidesman. Then an artist whose name was being typed
    /// ("mara so" for Mara Solis, or "mara solis live" for them too), or a later word of their
    /// name ("sol"). Otherwise the first song.
    public static func topKind(for query: String, artist: String?, album: String?, hasSong: Bool) -> SearchTopKind? {
        let term = StatsCalculator.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !term.isEmpty else { return nil }
        let artistName = artist.map(StatsCalculator.folded).flatMap { $0.isEmpty ? nil : $0 }
        let albumTitle = album.map(StatsCalculator.folded).flatMap { $0.isEmpty ? nil : $0 }
        if let artistName, artistName == term { return .artist }
        if let albumTitle, albumTitle == term { return .album }
        if let artistName, artistName.hasPrefix(term) || term.hasPrefix(artistName + " ") { return .artist }
        // A later word of their name, from three letters: "sol" for Mara Solis.
        if let artistName, term.count >= 3,
           artistName.split(separator: " ").dropFirst().contains(where: { $0.hasPrefix(term) }) {
            return .artist
        }
        return hasSong ? .song : nil
    }
}

/// What was searched for lately, kept as lines in one stored string, newest first.
public enum RecentSearches {
    /// How many are kept.
    public static let limit = 8

    public static func list(_ storage: String) -> [String] {
        storage.split(separator: "\n").map(String.init)
    }

    /// The storage with a search added at the front, each search once whatever its case.
    public static func adding(_ query: String, to storage: String) -> String {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !term.isEmpty else { return storage }
        let kept = [term] + list(storage).filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        return kept.prefix(limit).joined(separator: "\n")
    }

    /// The storage without one search.
    public static func removing(_ query: String, from storage: String) -> String {
        list(storage).filter { $0 != query }.joined(separator: "\n")
    }
}
