import Foundation

/// Artist pictures from Apple Music, by ``CaptureStat/artistIdentity``.
///
/// Kept in a file rather than the store. The pictures are derived, each device can look them
/// up again, and a new synced field would need the CloudKit schema deployed again. Not in the
/// App Group's defaults either, where they used to be: one entry for every artist ever played
/// grew without end there, and every widget and the menu bar load those defaults whole to
/// read a setting.
public struct ArtistArtworkCache: Sendable {
    /// Where the pictures used to be kept, read once to move them.
    public static let legacyDefaultsKey = "TracksArtistArtwork"

    private let url: URL?
    /// The suite name, not the `UserDefaults`, which isn't `Sendable`.
    private let legacySuiteName: String?

    /// Application Support by default. Nil keeps nothing, for previews and tests.
    public init(url: URL? = Self.defaultURL, legacySuiteName: String? = AppGroup.identifier) {
        self.url = url
        self.legacySuiteName = legacySuiteName
    }

    public static var defaultURL: URL? {
        URL.applicationSupportDirectory.appending(path: "ArtistArtwork.json")
    }

    /// Every lookup so far. An empty string means Apple Music had no picture, so the artist
    /// isn't asked about again.
    private var stored: [String: String] {
        guard let url else { return [:] }
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        return movedFromDefaults()
    }

    /// The lookups kept in the App Group's defaults before, written to the file and taken out
    /// of the defaults.
    private func movedFromDefaults() -> [String: String] {
        let defaults = legacySuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard let legacy = defaults.dictionary(forKey: Self.legacyDefaultsKey) as? [String: String] else { return [:] }
        if save(legacy) { defaults.removeObject(forKey: Self.legacyDefaultsKey) }
        return legacy
    }

    @discardableResult
    private func save(_ lookups: [String: String]) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(lookups) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
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
        save(updated)
    }

    /// Forgets the artists Apple Music had no picture for, so they're asked about again.
    ///
    /// A lookup that ran before the catalog knew the artist, or before their song had a
    /// catalog id, is remembered as "no picture" for good. Repairing artwork undoes that.
    ///
    /// - Returns: how many artists will be asked about again.
    @discardableResult
    public func forgetMissing() -> Int {
        let all = stored
        let kept = all.filter { !$0.value.isEmpty }
        let forgotten = all.count - kept.count
        guard forgotten > 0 else { return 0 }
        save(kept)
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
