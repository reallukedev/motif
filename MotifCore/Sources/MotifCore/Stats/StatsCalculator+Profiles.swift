import Foundation

public struct ArtistProfile: Sendable, Equatable {
    public let artist: ArtistTally
    public let songs: [SongTally]
    public let albums: [AlbumTally]
    public let timeline: [TimeBucket]
    public let timelineUnit: Calendar.Component
    public let hourly: [HourCount]
    public let allTimeRank: Int
    /// Share of all plays, 0...1.
    public let share: Double
    /// The genre their songs are played in most, once looked up.
    public var genre: String? = nil
    /// The earliest and latest release years among their songs that were played.
    public var releaseYears: ClosedRange<Int>? = nil
}

public struct SongProfile: Sendable, Equatable {
    public let song: SongTally
    public let artistID: String
    public let timeline: [TimeBucket]
    public let timelineUnit: Calendar.Component
    public let sources: [SourceCount]
    public let stations: [NamedCount]
    /// Newest first.
    public let plays: [Date]
    public let allTimeRank: Int
    /// Genre and release year, once looked up.
    public var metadata: SongMetadata? = nil
}

public struct AlbumProfile: Sendable, Equatable {
    public let album: AlbumTally
    /// The album's artist, so the page can link to them.
    public let artistID: String
    /// Its songs, most played first.
    public let songs: [SongTally]
    public let timeline: [TimeBucket]
    public let timelineUnit: Calendar.Component
    /// Where it sits among every album played, 1-based.
    public let allTimeRank: Int
    /// Share of all plays, 0...1.
    public let share: Double
    public let firstHeard: Date
    public let lastHeard: Date
    /// The genre its songs are played in most, once looked up.
    public var genre: String? = nil
    /// The release year its songs agree on, once looked up.
    public var releaseYear: Int? = nil
}

public struct SearchResults: Sendable, Equatable {
    public let songs: [SongTally]
    public let artists: [ArtistTally]
    public let albums: [AlbumTally]

    public var isEmpty: Bool { songs.isEmpty && artists.isEmpty && albums.isEmpty }

    public static let empty = SearchResults(songs: [], artists: [], albums: [])
}

extension StatsCalculator {

    public static func artistProfile(
        id: String,
        history: ListeningHistory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> ArtistProfile? {
        let members = history.captures.indices.filter { history.captures[$0].artistIdentity == id }
        guard let artist = tallyArtists(members, in: history).first else { return nil }
        let everyone = tallyArtists(history.captures.indices, in: history)
        let ranks = competitionRanks(everyone.map(\.count))
        let position = everyone.firstIndex { $0.id == id }.map { ranks[$0] } ?? everyone.count

        let (unit, span) = profileSpan(first: artist.firstHeard, calendar: calendar, now: now)
        return ArtistProfile(
            artist: artist,
            songs: tallySongs(members, in: history),
            albums: tallyAlbums(members, in: history),
            timeline: timeline(members, in: history, unit: unit, span: span, calendar: calendar),
            timelineUnit: unit,
            hourly: hourly(for: members.map { history.captures[$0] }, calendar: calendar),
            allTimeRank: position,
            share: history.captures.isEmpty ? 0 : Double(artist.count) / Double(history.captures.count),
            genre: mainGenre(of: members, in: history),
            releaseYears: releaseYears(of: members, in: history)
        )
    }

    /// - Parameter id: an ``CaptureStat/albumIdentity``, which is the album title and the
    ///   folded artist name. Albums are identified by name because Motif never sees an album
    ///   id: a capture carries the song's.
    public static func albumProfile(
        id: String,
        history: ListeningHistory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> AlbumProfile? {
        let members = history.captures.indices.filter { history.captures[$0].albumIdentity == id }
        guard let album = tallyAlbums(members, in: history).first else { return nil }
        let everything = tallyAlbums(history.captures.indices, in: history)
        let ranks = competitionRanks(everything.map(\.count))
        let position = everything.firstIndex { $0.id == id }.map { ranks[$0] } ?? everything.count
        let captures = members.map { history.captures[$0] }

        let firstHeard = captures[0].capturedAt
        let (unit, span) = profileSpan(first: firstHeard, calendar: calendar, now: now)
        let songs = tallySongs(members, in: history)
        return AlbumProfile(
            album: album,
            artistID: captures[captures.count - 1].artistIdentity,
            songs: songs,
            timeline: timeline(members, in: history, unit: unit, span: span, calendar: calendar),
            timelineUnit: unit,
            allTimeRank: position,
            share: history.captures.isEmpty ? 0 : Double(album.count) / Double(history.captures.count),
            firstHeard: firstHeard,
            lastHeard: captures[captures.count - 1].capturedAt,
            genre: mainGenre(of: members, in: history),
            // One year for a record, not a range: its songs came out together, and the odd
            // re-release date among them shouldn't turn it into "1994–2011".
            releaseYear: releaseYears(of: members, in: history)?.lowerBound
        )
    }

    public static func songProfile(
        id: String,
        history: ListeningHistory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> SongProfile? {
        let members = history.captures.indices.filter { history.captures[$0].songIdentity == id }
        guard let song = tallySongs(members, in: history).first else { return nil }
        let everything = tallySongs(history.captures.indices, in: history)
        let ranks = competitionRanks(everything.map(\.count))
        let position = everything.firstIndex { $0.id == id }.map { ranks[$0] } ?? everything.count
        let captures = members.map { history.captures[$0] }

        let (unit, span) = profileSpan(first: song.firstHeard, calendar: calendar, now: now)
        return SongProfile(
            song: song,
            artistID: captures.last?.artistIdentity ?? "",
            timeline: timeline(members, in: history, unit: unit, span: span, calendar: calendar),
            timelineUnit: unit,
            sources: sources(for: captures),
            stations: rank(captures.compactMap(\.stationName), limit: 5),
            plays: captures.map(\.capturedAt).reversed(),
            allTimeRank: position,
            metadata: history.songMetadata[id].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Weekly bars for anything first heard in the last three months, monthly after that,
    /// capped at two years.
    static func profileSpan(
        first: Date,
        calendar: Calendar,
        now: Date
    ) -> (Calendar.Component, DateInterval) {
        let days = calendar.dateComponents([.day], from: first, to: now).day ?? 0
        if days <= 91 {
            // Show at least eight weeks so a brand-new song isn't a single bar.
            let floor = calendar.date(byAdding: .weekOfYear, value: -7, to: now) ?? first
            return (.weekOfYear, DateInterval(start: min(first, floor), end: max(now, first)))
        }
        let twoYears = calendar.date(byAdding: .month, value: -23, to: now) ?? first
        return (.month, DateInterval(start: max(first, twoYears), end: max(now, first)))
    }

    /// Matches every typed word, ignoring case and accents ("mara sol" finds Mara Solís).
    /// Songs match on their genre too, so "jazz" finds the jazz you've played.
    ///
    /// Tallies the whole history for each call. For search as you type, build a
    /// ``SearchIndex`` once and search that.
    public static func search(
        _ text: String,
        in history: ListeningHistory,
        limit: Int = 25
    ) -> SearchResults {
        SearchIndex(history: history).search(text, limit: limit)
    }
}
