import Foundation

/// Artist pictures from Apple Music, by ``CaptureStat/artistIdentity``.
///
/// Kept in the App Group's defaults rather than the store. The pictures are derived, each
/// device can look them up again, and a new synced field would need the CloudKit schema
/// deployed again.
public struct ArtistArtworkCache: Sendable {
    public static let defaultsKey = "MotifArtistArtwork"

    /// The suite name, not the `UserDefaults`, which isn't `Sendable`.
    private let suiteName: String?

    /// Falls back to standard defaults without an App Group (previews, tests).
    public init(suiteName: String? = AppGroup.identifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Every lookup so far. An empty string means Apple Music had no picture, so the artist
    /// isn't asked about again.
    private var stored: [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// Artists already looked up, with or without a picture.
    public var lookedUp: Set<String> { Set(stored.keys) }

    /// The pictures that were found.
    public var urls: [String: String] { stored.filter { !$0.value.isEmpty } }

    /// Saves one round of lookups. `found` is keyed by artist identity; every artist in
    /// `asked` missing from it is remembered as having no picture.
    public func record(found: [String: String], asked: some Sequence<String>) {
        var updated = stored
        for identity in asked { updated[identity] = found[identity] ?? "" }
        defaults.set(updated, forKey: Self.defaultsKey)
    }

    /// Forgets the artists Apple Music had no picture for, so they're asked about again.
    ///
    /// A lookup that ran before the catalog knew the artist, or before their song had a
    /// catalog id, is remembered as "no picture" for good. Repairing artwork undoes that.
    ///
    /// - Returns: how many artists will be asked about again.
    @discardableResult
    public func forgetMissing() -> Int {
        let kept = urls
        let forgotten = stored.count - kept.count
        guard forgotten > 0 else { return 0 }
        defaults.set(kept, forKey: Self.defaultsKey)
        return forgotten
    }
}

/// Which artists to look up a picture for.
///
/// The picture belongs to the catalog artist, and a catalog song leads there, so an artist
/// is looked up through one of their songs.
public enum ArtistArtworkLookup {
    public struct Request: Sendable, Equatable {
        public let artistIdentity: String
        /// As credited on the song, to pick the right artist when a song has several.
        public let artistName: String
        /// A catalog id when there is one. Otherwise a library id or nothing, and the song
        /// is found by searching for its title.
        public let songID: String
        public let title: String
        public let albumTitle: String?

        public init(
            artistIdentity: String,
            artistName: String,
            songID: String,
            title: String,
            albumTitle: String? = nil
        ) {
            self.artistIdentity = artistIdentity
            self.artistName = artistName
            self.songID = songID
            self.title = title
            self.albumTitle = albumTitle
        }

        /// Whether the catalog can be asked for this song directly, without a search.
        public var hasCatalogID: Bool { MusicItemIdentity.isCatalogID(songID) }
    }

    /// One song per artist not yet in `lookedUp`, most played artists first.
    public static func pending(
        in history: ListeningHistory,
        lookedUp: Set<String>,
        limit: Int
    ) -> [Request] {
        var plays: [String: Int] = [:]
        var requests: [String: Request] = [:]
        for capture in history.captures
        where !capture.artistIdentity.isEmpty && !lookedUp.contains(capture.artistIdentity) {
            plays[capture.artistIdentity, default: 0] += 1
            // History is oldest first, so the most recent song wins, but a catalog id beats
            // one that needs a search. Songs imported from Recently Played carry library ids
            // ("i.…"), which the catalog won't take.
            let request = Request(
                artistIdentity: capture.artistIdentity,
                artistName: capture.artistName,
                songID: capture.songID,
                title: capture.title,
                albumTitle: capture.albumTitle
            )
            if request.hasCatalogID || requests[capture.artistIdentity]?.hasCatalogID != true {
                requests[capture.artistIdentity] = request
            }
        }
        return requests.values
            .sorted {
                (plays[$0.artistIdentity] ?? 0, $1.artistIdentity)
                    > (plays[$1.artistIdentity] ?? 0, $0.artistIdentity)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Which of a song's artists is the one credited, since "Boom (ft. JID)" by Token lists
    /// Token and JID. An exact match first, then whoever is named first in a joint credit
    /// like "Rome Streetz & Conductor Williams", otherwise the first.
    public static func creditedArtist(named credited: String, among names: [String]) -> Int? {
        guard !names.isEmpty else { return nil }
        let target = StatsCalculator.folded(credited)
        let folded = names.map(StatsCalculator.folded)
        if let exact = folded.firstIndex(of: target) { return exact }
        let named = folded.indices.compactMap { index in
            folded[index].isEmpty ? nil : target.range(of: folded[index]).map { (index, $0.lowerBound) }
        }
        return named.min { $0.1 < $1.1 }?.0 ?? 0
    }
}
