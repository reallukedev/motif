import Foundation

/// A mix that picks each song as the one before it starts, as Apple Music's stations do, so
/// what you skip and what you let play steer what comes next. Motif Radio, the moods and
/// Autoplay play this way, and never run out.
///
/// Songs you know and new finds are drawn from separately, the new ones for a share of the
/// picks. Skipping an artist makes them rarer for the rest of the listen, and letting one play
/// makes them a little likelier; skipping new finds makes them rarer, and keeping them makes
/// them more common. No song comes up twice until every other one has, and an artist doesn't
/// follow themselves when anyone else could.
///
/// It also listens for runs of skips. Two skips in a row that share a genre or a decade, or
/// that are both new finds, steer away from what they share for the next few picks. A run of
/// skips with nothing in common tries other genres, and the first song let play after that is
/// what the mix homes in on. See ``steering``.
public struct LiveMix: Sendable {
    public struct Candidate: Sendable, Equatable {
        public let song: MixSong
        /// How likely it is against the others of its kind: your songs against your songs, new
        /// finds against new finds.
        public let weight: Double
        /// A song from Apple Music that isn't in the history.
        public let isNew: Bool
        /// Heard in the last few hours. Comes up only once the rested songs have all been picked.
        public let isResting: Bool
        /// Its genre as Apple Music names it, for noticing skips that share one. The song's own
        /// where the candidate doesn't say.
        public let genre: String?
        /// The year it came out, for noticing skips that share a decade.
        public let releaseYear: Int?

        public init(
            song: MixSong,
            weight: Double,
            isNew: Bool = false,
            isResting: Bool = false,
            genre: String? = nil,
            releaseYear: Int? = nil
        ) {
            self.song = song
            self.weight = weight
            self.isNew = isNew
            self.isResting = isResting
            self.genre = genre ?? song.genre
            self.releaseYear = releaseYear
        }

        /// The genre folded to its family: "Hip-Hop/Rap" and "Hip-Hop" are one.
        var genreKey: String? { genre.flatMap(LiveMix.genreKey) }

        var decade: Int? { releaseYear.map { $0 / 10 * 10 } }
    }

    /// What the mix is doing about what it's heard, for the player to say. Nil until it has
    /// something to say.
    public enum Steering: Sendable, Equatable {
        /// Two or more skips in a row in this genre: it plays others for a while.
        case awayFromGenre(String)
        /// Two or more skips in a row from this decade, as a year like 1980.
        case awayFromDecade(Int)
        /// Two or more new finds skipped in a row: more songs you know for a while.
        case fewerNewFinds
        /// Two or more of your songs skipped in a row: more new finds for a while.
        case moreNewFinds
        /// Skips with nothing in common: trying genres it hasn't played lately.
        case tryingSomethingElse
        /// A song let play, or loved, after a run of skips: more like it.
        case towardGenre(String)
        case towardArtist(String)
    }

    /// How long a song rests after being heard before it can come up again.
    public static let restPeriod: TimeInterval = 6 * 60 * 60

    public let candidates: [Candidate]
    /// The share of picks that are new finds, while there are both kinds left.
    public private(set) var newShare: Double
    /// The moment Motif Radio was made for: its hour and whether you were driving. Anytime for
    /// a mix that doesn't follow either.
    public let moment: RadioMoment

    /// Songs picked this listen, in order.
    public private(set) var picks: [String] = []
    /// What the mix last changed course for. See ``Steering``.
    public private(set) var steering: Steering?
    private var picked: Set<String> = []
    /// How much likelier each artist has become this listen: under 1 once skipped.
    private var artistBias: [String: Double] = [:]
    /// The same for each genre family. Unlike an artist's, it eases back toward even as the
    /// listen goes on, so one bad run doesn't close a genre for good.
    private var genreBias: [String: Double] = [:]
    /// How each song this listen went, newest last, for noticing runs of skips.
    private var outcomes: [Outcome] = []
    /// What the next few picks stay clear of, after a run of skips.
    private var avoiding: Avoidance?
    private let byIdentity: [String: Int]
    private var random: SeededGenerator

    /// Artists who can't come straight back.
    private static let artistGap = 2
    private static let newShareRange = 0.05...0.6
    /// Skips in a row that count as a run.
    static let runLength = 2
    /// Picks that stay clear of what a run of skips shared.
    static let avoidFor = 5

    private struct Outcome: Sendable {
        let skipped: Bool
        let genre: String?
        let decade: Int?
        let isNew: Bool
    }

    private struct Avoidance: Sendable {
        var genres: Set<String> = []
        var decades: Set<Int> = []
        var picksLeft: Int
    }

    public init(candidates: [Candidate], newShare: Double = 0.2, moment: RadioMoment = .anytime, seed: UInt64) {
        // In a fixed order, so a seed always draws the same songs from the same candidates.
        var seen = Set<String>()
        let unique = candidates
            .filter { $0.weight > 0 && seen.insert($0.song.songIdentity).inserted }
            .sorted { $0.song.songIdentity < $1.song.songIdentity }
        self.candidates = unique
        self.byIdentity = Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($1.song.songIdentity, $0) })
        self.newShare = newShare
        self.moment = moment
        self.random = SeededGenerator(seed: seed)
    }

    public var isEmpty: Bool { candidates.isEmpty }

    public func hasPicked(_ identity: String) -> Bool { picked.contains(identity) }

    /// The next song. Nil only when there are no candidates at all.
    public mutating func next() -> MixSong? {
        next(where: { _ in true })
    }

    /// The next song of those that pass `include`, picked as ``next()`` picks: for a player
    /// that wants one it can play at once, say, or a new find to get ready.
    /// - Parameter newFinds: true for a new find only, false for one of yours only, nil for
    ///   either, as the mix's share of new finds decides.
    /// - Returns: nil when none that passes is left to pick.
    public mutating func next(newFinds: Bool? = nil, where include: (MixSong) -> Bool) -> MixSong? {
        guard !candidates.isEmpty else { return nil }
        if picked.count >= candidates.count { startOver() }

        let open = candidates.filter { !picked.contains($0.song.songIdentity) && include($0.song) }
        let yours = newFinds == true ? [] : open.filter { !$0.isNew }
        let new = newFinds == false ? [] : open.filter(\.isNew)
        let pool: [Candidate]
        if yours.isEmpty || new.isEmpty {
            pool = yours.isEmpty ? new : yours
        } else {
            pool = Double.random(in: 0..<1, using: &random) < newShare ? new : yours
        }
        guard !pool.isEmpty else { return nil }

        let rested = pool.filter { !$0.isResting }
        let fresh = rested.isEmpty ? pool : rested
        let recent = Set(picks.suffix(Self.artistGap).compactMap { byIdentity[$0].map { candidates[$0].song.artistKey } })
        let spaced = fresh.filter { !recent.contains($0.song.artistKey) }
        let choices = clear(of: avoiding, spaced.isEmpty ? fresh : spaced)

        guard let choice = draw(from: choices) else { return nil }
        note(picked: choice.song.songIdentity)
        easeBack()
        return choice.song
    }

    /// Counts a song as picked without drawing it: the one a listen starts with.
    public mutating func note(picked identity: String) {
        guard picked.insert(identity).inserted else { return }
        picks.append(identity)
    }

    /// The song gave way early.
    public mutating func noteSkipped(_ identity: String) {
        guard let index = byIdentity[identity] else { return }
        let candidate = candidates[index]
        let artist = candidate.song.artistKey
        artistBias[artist] = max(0.02, (artistBias[artist] ?? 1) * 0.35)
        if let genre = candidate.genreKey {
            genreBias[genre] = max(0.1, (genreBias[genre] ?? 1) * 0.7)
        }
        if candidate.isNew { newShare = (newShare * 0.7).clamped(to: Self.newShareRange) }
        record(candidate, skipped: true)
        steerAfterSkips()
    }

    /// The song played through, or near enough.
    public mutating func noteFinished(_ identity: String) {
        guard let index = byIdentity[identity] else { return }
        let candidate = candidates[index]
        let artist = candidate.song.artistKey
        artistBias[artist] = min(3, (artistBias[artist] ?? 1) * 1.25)
        let wasSearching = isSearching
        if let genre = candidate.genreKey {
            // After a run of skips, the song that finally plays through is the one to follow.
            genreBias[genre] = min(4, (genreBias[genre] ?? 1) * (wasSearching ? 2 : 1.15))
        }
        if candidate.isNew { newShare = (newShare * 1.2 + 0.02).clamped(to: Self.newShareRange) }
        record(candidate, skipped: false)
        if wasSearching {
            avoiding = nil
            steering = candidate.genre.map(Steering.towardGenre) ?? .towardArtist(candidate.song.artistName)
        }
    }

    /// Loved while it played: the strongest thing anyone can say about a song.
    public mutating func noteLoved(_ identity: String) {
        guard let index = byIdentity[identity] else { return }
        let candidate = candidates[index]
        let artist = candidate.song.artistKey
        artistBias[artist] = min(4, (artistBias[artist] ?? 1) * 2)
        if let genre = candidate.genreKey {
            genreBias[genre] = min(4, (genreBias[genre] ?? 1) * 1.6)
        }
        avoiding = nil
        steering = .towardArtist(candidate.song.artistName)
    }

    /// Whether the mix is looking for something after a run of skips.
    private var isSearching: Bool {
        switch steering {
        case .awayFromGenre, .awayFromDecade, .fewerNewFinds, .moreNewFinds, .tryingSomethingElse: avoiding != nil
        case .towardGenre, .towardArtist, nil: false
        }
    }

    private mutating func record(_ candidate: Candidate, skipped: Bool) {
        outcomes.append(Outcome(skipped: skipped, genre: candidate.genreKey, decade: candidate.decade, isNew: candidate.isNew))
        if outcomes.count > 12 { outcomes.removeFirst(outcomes.count - 12) }
    }

    /// Looks at the skips in a row just now for what they share, and turns away from it: a
    /// genre first, since that's what people hear; then a decade; then new or known. Skips
    /// that share nothing try genres the run didn't have.
    private mutating func steerAfterSkips() {
        let run = Array(outcomes.reversed().prefix { $0.skipped })
        guard run.count >= Self.runLength else { return }
        let latest = Array(run.prefix(Self.runLength))
        var avoid = Avoidance(picksLeft: Self.avoidFor)
        if let genre = latest[0].genre, latest.allSatisfy({ $0.genre == genre }) {
            genreBias[genre] = min(genreBias[genre] ?? 1, 0.15)
            avoid.genres = [genre]
            steering = .awayFromGenre(displayName(ofGenre: genre))
        } else if let decade = latest[0].decade, latest.allSatisfy({ $0.decade == decade }) {
            avoid.decades = [decade]
            steering = .awayFromDecade(decade)
        } else if latest.allSatisfy(\.isNew) {
            newShare = (newShare * 0.5).clamped(to: Self.newShareRange)
            steering = .fewerNewFinds
        } else if latest.allSatisfy({ !$0.isNew }), run.count >= 3, candidates.contains(where: \.isNew) {
            newShare = (newShare * 1.6 + 0.05).clamped(to: Self.newShareRange)
            steering = .moreNewFinds
        } else if run.count >= 3 {
            avoid.genres = Set(run.compactMap(\.genre))
            steering = .tryingSomethingElse
        } else {
            return
        }
        avoiding = avoid
    }

    /// The choices that stay clear of what a run of skips shared, while any do.
    private func clear(of avoidance: Avoidance?, _ choices: [Candidate]) -> [Candidate] {
        guard let avoidance else { return choices }
        let clear = choices.filter { candidate in
            !(candidate.genreKey.map(avoidance.genres.contains) ?? false)
                && !(candidate.decade.map(avoidance.decades.contains) ?? false)
        }
        return clear.isEmpty ? choices : clear
    }

    /// After each pick, genres drift a tenth of the way back to even, and what's being avoided
    /// comes one pick closer to coming back.
    private mutating func easeBack() {
        for (genre, bias) in genreBias { genreBias[genre] = 1 + (bias - 1) * 0.9 }
        guard var avoid = avoiding else { return }
        avoid.picksLeft -= 1
        avoiding = avoid.picksLeft > 0 ? avoid : nil
    }

    /// The genre as the candidates spell it, for the player to say.
    private func displayName(ofGenre key: String) -> String {
        candidates.lazy.compactMap { candidate in candidate.genreKey == key ? candidate.genre : nil }.first ?? key
    }

    /// "Hip-Hop/Rap", "Hip-Hop" and "hip hop" as one family, "hip-hop".
    static func genreKey(_ genre: String) -> String? {
        let family = genre.split(separator: "/").first.map(String.init) ?? genre
        let folded = StatsCalculator.folded(family).replacingOccurrences(of: " ", with: "-")
        return folded.isEmpty || folded == "music" ? nil : folded
    }

    /// Everything has been picked: begin again, keeping the latest picks out so the end of one
    /// round doesn't meet the start of the next.
    private mutating func startOver() {
        let keep = Array(picks.suffix(min(20, candidates.count / 2)))
        picks = keep
        picked = Set(keep)
    }

    private mutating func draw(from choices: [Candidate]) -> Candidate? {
        let weights = choices.map { candidate in
            candidate.weight
                * (artistBias[candidate.song.artistKey] ?? 1)
                * (candidate.genreKey.flatMap { genreBias[$0] } ?? 1)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return choices.first }
        var target = Double.random(in: 0..<total, using: &random)
        for (choice, weight) in zip(choices, weights) {
            target -= weight
            if target < 0 { return choice }
        }
        return choices.last
    }
}

// MARK: - Motif Radio and the moods

extension LiveMix {
    /// Motif Radio: everything in the history, the more played and the more recent the
    /// likelier, with new finds for the share its tuning sets. Songs heard in the last few
    /// hours rest; skipped and suggested-less songs stay out.
    /// - Parameters:
    ///   - moment: the hour to follow and whether you're driving. See ``RadioMomentFit``.
    ///   - drives: the drives noticed, for the songs you play on the road.
    public static func motifRadio(
        from history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        newFinds: [MixSong] = [],
        tuning: RadioTuning = .standard,
        moment: RadioMoment = .anytime,
        drives: DriveLog = DriveLog(),
        now: Date = .now,
        calendar: Calendar = .current,
        seed: UInt64
    ) -> LiveMix {
        let songs = MixBuilder.aggregate(history, signals: signals, now: now, calendar: calendar)
        let fit = RadioMomentFit(moment: moment, songs: songs, drives: drives)
        let rested = now.addingTimeInterval(-restPeriod)
        let yours = songs.map { aggregate in
            let metadata = history.songMetadata[aggregate.identity]
            let genre = metadata?.genre
            return Candidate(
                song: aggregate.song,
                weight: weight(plays: aggregate.dates.count, lastHeard: aggregate.lastHeard, now: now)
                    * tuning.factor(genre: genre, lastHeard: aggregate.lastHeard, now: now)
                    * fit.factor(for: aggregate, genre: genre, recentSkips: signals.recentSkips(of: aggregate.identity, now: now)),
                isResting: aggregate.lastHeard >= rested,
                genre: genre,
                releaseYear: metadata?.releaseYear
            )
        }
        let new = new(newFinds, besides: yours, signals: signals, now: now).map { candidate in
            Candidate(
                song: candidate.song,
                weight: tuning.factor(genre: candidate.song.genre, lastHeard: nil, now: now) * fit.factor(newFindGenre: candidate.song.genre),
                isNew: true
            )
        }
        return LiveMix(candidates: yours + new, newShare: fit.newShare(tuning.discovery.newShare), moment: moment, seed: seed)
    }

    /// Carries a listen over to a newly tuned mix: what's been picked, and what's been skipped,
    /// so retuning mid-listen doesn't start again from the top.
    public mutating func continueListen(from earlier: LiveMix) {
        for identity in earlier.picks { note(picked: identity) }
        for (artist, bias) in earlier.artistBias { artistBias[artist] = bias }
        genreBias = earlier.genreBias
        outcomes = earlier.outcomes
        avoiding = earlier.avoiding
        steering = earlier.steering
    }

    /// A mood: your songs in genres that suit it, and new finds from Apple Music's playlists
    /// for it. The fewer songs of yours suit it, the more new finds it plays.
    public static func mood(
        _ mood: Mood,
        from history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        newFinds: [MixSong] = [],
        now: Date = .now,
        seed: UInt64
    ) -> LiveMix {
        let rested = now.addingTimeInterval(-restPeriod)
        let yours = MoodMix.scored(for: mood, in: history, signals: signals, now: now).map { song, score in
            let metadata = history.songMetadata[song.songIdentity]
            return Candidate(song: song, weight: score, isResting: song.lastHeard >= rested, genre: metadata?.genre, releaseYear: metadata?.releaseYear)
        }
        let share = switch yours.count {
        case 0: 1.0
        case ..<MoodMix.fewSongs: 0.5
        default: 0.25
        }
        return LiveMix(candidates: yours + new(newFinds, besides: yours, signals: signals, now: now), newShare: share, seed: seed)
    }

    /// New finds as candidates, leaving out any already in the history or suggested less.
    private static func new(_ songs: [MixSong], besides yours: [Candidate], signals: ListeningSignals, now: Date) -> [Candidate] {
        let known = Set(yours.map(\.song.songIdentity))
        return songs
            .filter { !known.contains($0.songIdentity) && !signals.excludes($0.songIdentity, now: now) }
            .map { Candidate(song: $0, weight: 1, isNew: true) }
    }

    /// Plays count on a log scale, so a song played 200 times isn't 200 times as likely as one
    /// played once; recency counts for up to two thirds more.
    static func weight(plays: Int, lastHeard: Date, now: Date) -> Double {
        let halfLife: TimeInterval = 120 * 24 * 60 * 60
        let recency = pow(0.5, max(0, now.timeIntervalSince(lastHeard)) / halfLife)
        return log2(1 + Double(plays)) * (0.6 + 0.4 * recency)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
