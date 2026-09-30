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
///
/// Each pick leans a little toward the genre of the song before it, so one song flows into the
/// next, and an artist heard a few songs ago is less likely to come round again so soon.
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
        /// Why it would come up, for the player to say. Nil when nothing stands out.
        public let reason: Reason?

        public init(
            song: MixSong,
            weight: Double,
            isNew: Bool = false,
            isResting: Bool = false,
            genre: String? = nil,
            releaseYear: Int? = nil,
            reason: Reason? = nil
        ) {
            self.song = song
            self.weight = weight
            self.isNew = isNew
            self.isResting = isResting
            self.genre = genre ?? song.genre
            self.releaseYear = releaseYear
            self.reason = reason ?? (isNew ? .newFind : nil)
        }

        /// The same song at another weight.
        func weighted(_ weight: Double) -> Candidate {
            Candidate(song: song, weight: weight, isNew: isNew, isResting: isResting, genre: genre, releaseYear: releaseYear, reason: reason)
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

    /// Why a song came up, as far as one thing stands out. Only what the mix really weighed:
    /// a reason is never made up for a song that came up by chance.
    public enum Reason: Sendable, Equatable {
        /// A song from outside your history.
        case newFind
        /// A song from outside your history, by an artist you play.
        case newFromYourArtist
        /// A song from outside your history, by an artist like this one of yours.
        case newFindLike(String)
        /// One you've played on drives, while the radio plays for the road.
        case onTheRoad
        /// One you play near this hour far more than you play it at others.
        case aroundNow
        /// In a genre the radio is tuned to lean into, as the tuning spells it.
        case leaningInto(String)
        /// Brought back after months unheard: last played then.
        case oldFavorite(lastHeard: Date)
        /// Among the songs you play most.
        case mostPlayed
        /// After a run of skips, the genre of the song let play: what the mix homed in on.
        case moreOf(String)
        /// The artist of a song loved or asked for more of this listen.
        case moreLike(String)
    }

    /// How a song went, told by when it gave way.
    public enum Listen: Sendable, Equatable {
        /// Left in its first moments. See ``ListeningSignals/isSkip(playedFor:duration:)``.
        case skipped
        /// Heard for a while, then left well before the end: it didn't land, though it wasn't
        /// turned away at once.
        case movedOn
        /// Played through, or near enough.
        case finished

        /// Past the skip window, a song counts as let play once three fifths of it have played
        /// or it's within its last 45 seconds. A song whose length isn't known yet counts as
        /// let play, as it never counts as a skip.
        public init(playedFor: TimeInterval, duration: TimeInterval?) {
            if ListeningSignals.isSkip(playedFor: playedFor, duration: duration) {
                self = .skipped
                return
            }
            guard let duration, duration > 0 else {
                self = .finished
                return
            }
            let nearEnd = duration - playedFor <= Self.nearEnd
            self = nearEnd || playedFor >= duration * Self.letPlay ? .finished : .movedOn
        }

        static let letPlay = 0.6
        static let nearEnd: TimeInterval = 45
    }

    /// How long a song rests after being heard before it can come up again.
    public static let restPeriod: TimeInterval = 6 * 60 * 60

    public let candidates: [Candidate]
    /// The share of picks that are new finds, while there are both kinds left.
    public private(set) var newShare: Double
    /// The share it started with, as tuned, for telling what skips and keeps have taught it.
    private let startingShare: Double
    /// The moment Motif Radio was made for: its hour and whether you were driving. Anytime for
    /// a mix that doesn't follow either.
    public let moment: RadioMoment

    /// Artists blocked while the mix plays, whose songs it no longer picks. The mix was made
    /// without the ones blocked before.
    public var blocked = BlockedArtists()

    /// Songs picked this listen, in order.
    public private(set) var picks: [String] = []
    /// What the mix last changed course for. See ``Steering``.
    public private(set) var steering: Steering?
    private var picked: Set<String> = []
    /// Why each song drawn this listen came up, as it was when drawn: nil for one drawn with
    /// nothing standing out, which keeps it from taking on a reason it wasn't drawn for.
    private var pickReasons: [String: Reason?] = [:]
    /// How much likelier each artist has become this listen: under 1 once skipped.
    private var artistBias: [String: Double] = [:]
    /// The same for each genre family. Unlike an artist's, it eases back toward even as the
    /// listen goes on, so one bad run doesn't close a genre for good.
    private var genreBias: [String: Double] = [:]
    /// How each song this listen went, newest last, for noticing runs of skips.
    private var outcomes: [Outcome] = []
    /// What the next few picks stay clear of, after a run of skips.
    private var avoiding: Avoidance?
    /// The genre of the song loved or asked for more like, whose songs come up more for a
    /// while and say they're more like its artist while they do.
    private var lovedGenre: String?
    private let byIdentity: [String: Int]
    /// See ``artistMemory(artists:)``.
    private let remembersArtists: Int
    private var random: SeededGenerator

    /// Artists who can't come straight back.
    private static let artistGap = 2
    /// Picks over which an artist heard lately stays less likely, halving for each time, in a
    /// mix of many artists. See ``artistMemory(artists:)``.
    static let artistMemory = 8

    /// Picks over which an artist heard lately stays less likely, for a mix of this many
    /// artists: fewer the fewer there are, so a mix of a handful isn't made to go round them in
    /// turn, which would undo what skipping one of them says.
    static func artistMemory(artists: Int) -> Int {
        min(artistMemory, artists / 4)
    }
    /// How much likelier a song is in the genre of the song before it.
    static let flow = 1.4
    /// How much likelier a genre must still be, after a song in it was let play at the end of
    /// a run of skips, for its songs to say they came up for that.
    static let homingIn = 1.3
    private static let newShareRange = 0.05...0.6

    /// Where skips and keeps can take the share of new finds: ``newShareRange``, widened to
    /// take in the share it started with, so a share tuned below the floor, as Familiar is on
    /// the road, is never raised by a skip.
    private var shareRange: ClosedRange<Double> {
        min(Self.newShareRange.lowerBound, startingShare)...max(Self.newShareRange.upperBound, startingShare)
    }
    /// Skips in a row that count as a run.
    static let runLength = 2
    /// Picks that stay clear of what a run of skips shared.
    static let avoidFor = 5

    private struct Outcome: Sendable {
        let skipped: Bool
        /// Moved on from rather than skipped: in a run, it takes a real skip beside it, or more
        /// of them, to count.
        var movedOn = false
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
        self.remembersArtists = Self.artistMemory(artists: Set(unique.map(\.song.artistKey)).count)
        self.newShare = newShare
        self.startingShare = newShare
        self.moment = moment
        self.random = SeededGenerator(seed: seed)
    }

    public var isEmpty: Bool { candidates.isEmpty }

    public func hasPicked(_ identity: String) -> Bool { picked.contains(identity) }

    /// Whether the song is one of the mix's own, so what's said about it can steer: not the
    /// songs Autoplay follows on from, say.
    public func knows(_ identity: String) -> Bool { byIdentity[identity] != nil }

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

        let open = candidates.filter { !picked.contains($0.song.songIdentity) && allows($0.song) && include($0.song) }
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
        // As it is now, even when nothing stands out: a song come round again doesn't keep
        // what it was picked for before.
        pickReasons.updateValue(reason(choosing: choice), forKey: choice.song.songIdentity)
        note(picked: choice.song.songIdentity)
        easeBack()
        return choice.song
    }

    /// Whether the song is by no one blocked.
    private func allows(_ song: MixSong) -> Bool {
        !blocked.blocks(songBy: song.artistName)
    }

    /// The song a listen opens on: one of yours that passes `include`, drawn as the rest are
    /// but leaning harder toward the strongest, since the first song is the one most often
    /// skipped when it doesn't land. A new find, or a song resting, only when nothing else
    /// passes.
    public mutating func opener(where include: (MixSong) -> Bool) -> MixSong? {
        let yours = candidates.filter { !$0.isNew && !$0.isResting && !picked.contains($0.song.songIdentity) && allows($0.song) && include($0.song) }
        guard let choice = draw(from: yours, emphasis: 2) else { return next(playable: include) }
        // As it is now, even when nothing stands out: a song come round again doesn't keep
        // what it was picked for before.
        pickReasons.updateValue(reason(choosing: choice), forKey: choice.song.songIdentity)
        note(picked: choice.song.songIdentity)
        easeBack()
        return choice.song
    }

    /// The next song of those that pass `include`, going round them again once they've all
    /// been picked, as ``next()`` goes round every song: for a player that can only play some
    /// of them right now, like your own music with its server out of reach.
    /// - Returns: nil only when none passes at all.
    public mutating func next(playable include: (MixSong) -> Bool) -> MixSong? {
        if let song = next(where: include) { return song }
        let passing = Set(candidates.filter { allows($0.song) && include($0.song) }.map(\.song.songIdentity))
        guard !passing.isEmpty else { return nil }
        // Every one that passes has been picked: those begin again, keeping the latest few of
        // them out, as a new round of every song does.
        let keep = Set(picks.filter(passing.contains).suffix(min(20, passing.count / 2)))
        picks.removeAll { passing.contains($0) && !keep.contains($0) }
        picked = picked.filter { !passing.contains($0) || keep.contains($0) }
        return next(where: include)
    }

    /// Takes back a pick that never played, so it can come up again this round: one that made
    /// way for a pick that follows what was just asked for.
    public mutating func release(_ identity: String) {
        guard picked.remove(identity) != nil else { return }
        picks.removeAll { $0 == identity }
        pickReasons[identity] = nil
    }

    /// Counts a song as picked without drawing it: the one a listen starts with.
    public mutating func note(picked identity: String) {
        guard picked.insert(identity).inserted else { return }
        picks.append(identity)
    }

    /// How a song went: skipped, moved on from, or let play.
    public mutating func note(_ listen: Listen, of identity: String) {
        switch listen {
        case .skipped: noteSkipped(identity)
        case .movedOn: noteMovedOn(identity)
        case .finished: noteFinished(identity)
        }
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
        if candidate.isNew { newShare = (newShare * 0.7).clamped(to: shareRange) }
        record(candidate, skipped: true)
        steerAfterSkips()
    }

    /// The song was heard for a while and then left. Counts toward a run of skips, since it
    /// didn't land, but weighs less than a skip against its artist, and never counts as the
    /// song a search after a run of skips was looking for.
    public mutating func noteMovedOn(_ identity: String) {
        guard let index = byIdentity[identity] else { return }
        let candidate = candidates[index]
        let artist = candidate.song.artistKey
        artistBias[artist] = max(0.02, (artistBias[artist] ?? 1) * 0.7)
        if let genre = candidate.genreKey {
            genreBias[genre] = max(0.1, (genreBias[genre] ?? 1) * 0.9)
        }
        if candidate.isNew { newShare = (newShare * 0.9).clamped(to: shareRange) }
        record(candidate, skipped: true, movedOn: true)
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
        if candidate.isNew { newShare = (newShare * 1.2 + 0.02).clamped(to: shareRange) }
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
        lovedGenre = candidate.genreKey
        avoiding = nil
        steering = .towardArtist(candidate.song.artistName)
    }

    /// Why a song came up, as it was when drawn, or for one it didn't draw, like the song a
    /// listen starts with, what it stands for. Nil when nothing stands out.
    public func reason(for identity: String) -> Reason? {
        if let drawn = pickReasons[identity] { return drawn }
        return byIdentity[identity].flatMap { candidates[$0].reason }
    }

    /// Why the choice comes up now: what the listen is steering toward, where it's that, or
    /// what the candidate itself stands for.
    private func reason(choosing choice: Candidate) -> Reason? {
        switch steering {
        // Only while letting one play still counts for much: the boost eases back as the
        // listen goes on, and the reason with it.
        case .towardGenre(let genre) where choice.genreKey != nil && choice.genreKey == Self.genreKey(genre)
            && (choice.genreKey.flatMap { genreBias[$0] } ?? 1) >= Self.homingIn:
            return .moreOf(genre)
        // The artist's own songs, and while the love still counts for much, their genre's.
        case .towardArtist(let artist) where choice.song.artistKey == Self.artistKey(of: artist, in: candidates)
            || (lovedGenre != nil && choice.genreKey == lovedGenre && (lovedGenre.flatMap { genreBias[$0] } ?? 1) >= Self.homingIn):
            return .moreLike(artist)
        default:
            return choice.reason
        }
    }

    /// The key of the artist named, as the candidates have it.
    private static func artistKey(of name: String, in candidates: [Candidate]) -> String? {
        candidates.first { $0.song.artistName == name }?.song.artistKey
    }

    /// Whether the mix is looking for something after a run of skips.
    private var isSearching: Bool {
        switch steering {
        case .awayFromGenre, .awayFromDecade, .fewerNewFinds, .moreNewFinds, .tryingSomethingElse: avoiding != nil
        case .towardGenre, .towardArtist, nil: false
        }
    }

    private mutating func record(_ candidate: Candidate, skipped: Bool, movedOn: Bool = false) {
        outcomes.append(Outcome(skipped: skipped, movedOn: movedOn, genre: candidate.genreKey, decade: candidate.decade, isNew: candidate.isNew))
        if outcomes.count > 12 { outcomes.removeFirst(outcomes.count - 12) }
    }

    /// Looks at the skips in a row just now for what they share, and turns away from it: a
    /// genre first, since that's what people hear; then a decade; then new or known. Skips
    /// that share nothing try genres the run didn't have.
    private mutating func steerAfterSkips() {
        let run = Array(outcomes.reversed().prefix { $0.skipped })
        guard run.count >= Self.runLength else { return }
        // Songs only moved on from, heard a minute or two each, make a run only once there are
        // a few of them: plenty of people let the radio go on like that.
        guard run.prefix(Self.runLength).contains(where: { !$0.movedOn }) || run.count > Self.runLength else { return }
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
            newShare = (newShare * 0.5).clamped(to: shareRange)
            steering = .fewerNewFinds
        } else if latest.allSatisfy({ !$0.isNew }), run.count >= 3, candidates.contains(where: \.isNew) {
            newShare = (newShare * 1.6 + 0.05).clamped(to: shareRange)
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

    /// - Parameter emphasis: a power the weights are raised to: 1 as they are, 2 to lean
    ///   harder toward the strongest.
    private mutating func draw(from choices: [Candidate], emphasis: Double = 1) -> Candidate? {
        // Artists heard lately, each time halving their chance, so one with many songs doesn't
        // come round every few picks.
        var lately: [String: Int] = [:]
        for identity in picks.suffix(remembersArtists) {
            guard let index = byIdentity[identity] else { continue }
            lately[candidates[index].song.artistKey, default: 0] += 1
        }
        // The song before: the next leans toward its genre, so one flows into the next.
        let before = picks.last.flatMap { byIdentity[$0] }.flatMap { candidates[$0].genreKey }
        let weights = choices.map { candidate in
            candidate.weight
                * (artistBias[candidate.song.artistKey] ?? 1)
                * (candidate.genreKey.flatMap { genreBias[$0] } ?? 1)
                * pow(0.5, Double(lately[candidate.song.artistKey] ?? 0))
                * (before != nil && candidate.genreKey == before ? Self.flow : 1)
        }
        .map { emphasis == 1 ? $0 : pow($0, emphasis) }
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
    ///   - newFindReasons: why each new find was suggested, by its identity, where that says
    ///     more than it being new.
    ///   - moment: the hour to follow and whether you're driving. See ``RadioMomentFit``.
    ///   - drives: the drives noticed, for the songs you play on the road.
    public static func motifRadio(
        from history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        newFinds: [MixSong] = [],
        newFindReasons: [String: Reason] = [:],
        tuning: RadioTuning = .standard,
        moment: RadioMoment = .anytime,
        drives: DriveLog = DriveLog(),
        now: Date = .now,
        calendar: Calendar = .current,
        seed: UInt64
    ) -> LiveMix {
        let songs = MixBuilder.aggregate(history, signals: signals, now: now, calendar: calendar)
        let fit = RadioMomentFit(moment: moment, songs: songs, drives: drives)
        let mostPlayed = mostPlayedThreshold(songs.map(\.dates.count))
        let rested = now.addingTimeInterval(-restPeriod)
        let yours = songs.map { aggregate in
            let metadata = history.songMetadata[aggregate.identity]
            let genre = metadata?.genre
            return Candidate(
                song: aggregate.song,
                weight: weight(plays: aggregate.dates.count, lastHeard: aggregate.lastHeard, now: now)
                    * freshness(lastHeard: aggregate.lastHeard, now: now)
                    * tuning.factor(genre: genre, lastHeard: aggregate.lastHeard, now: now)
                    * fit.factor(for: aggregate, genre: genre, recentSkips: signals.recentSkips(of: aggregate.identity, now: now)),
                isResting: aggregate.lastHeard >= rested,
                genre: genre,
                releaseYear: metadata?.releaseYear,
                reason: reason(for: aggregate, genre: genre, fit: fit, tuning: tuning, mostPlayed: mostPlayed, now: now)
            )
        }
        let yourArtists = Set(songs.map(\.song.artistKey))
        let new = new(newFinds, besides: yours, signals: signals, now: now).map { candidate in
            Candidate(
                song: candidate.song,
                weight: tuning.factor(genre: candidate.song.genre, lastHeard: nil, now: now) * fit.factor(newFindGenre: candidate.song.genre),
                isNew: true,
                reason: newFindReasons[candidate.song.songIdentity]
                    ?? (yourArtists.contains(candidate.song.artistKey) ? .newFromYourArtist : .newFind)
            )
        }
        return LiveMix(
            candidates: balancedByArtist(yours) + balancedByArtist(new),
            newShare: fit.newShare(tuning.discovery.newShare), moment: moment, seed: seed
        )
    }

    /// Each artist's songs made rarer by how many there are, so an artist with fifty songs in
    /// your history comes up more than one with a single song, but not fifty times as often.
    static func balancedByArtist(_ candidates: [Candidate]) -> [Candidate] {
        var songs: [String: Int] = [:]
        for candidate in candidates { songs[candidate.song.artistKey, default: 0] += 1 }
        return candidates.map { candidate in
            let count = songs[candidate.song.artistKey] ?? 1
            return count > 1 ? candidate.weighted(candidate.weight / Double(count).squareRoot()) : candidate
        }
    }

    /// The plays it takes to be among the songs you play most: the top twentieth, and at least
    /// ten plays, so a small history doesn't call a song played twice a favorite.
    static func mostPlayedThreshold(_ plays: [Int]) -> Int {
        let sorted = plays.sorted(by: >)
        guard !sorted.isEmpty else { return .max }
        return max(10, sorted[min(sorted.count - 1, sorted.count / 20)])
    }

    /// The one thing that stands out about why a song of yours would come up, strongest first:
    /// the road, the hour, the genres it's tuned to, an old favorite brought back, and then
    /// simply being among your most played.
    static func reason(
        for song: MixBuilder.Aggregate,
        genre: String?,
        fit: RadioMomentFit,
        tuning: RadioTuning,
        mostPlayed: Int,
        now: Date
    ) -> Reason? {
        if let reason = fit.reason(for: song) { return reason }
        if let genre, let leaning = tuning.leaning(genre) { return .leaningInto(leaning) }
        if tuning.isBringingBack(lastHeard: song.lastHeard, now: now) { return .oldFavorite(lastHeard: song.lastHeard) }
        return song.dates.count >= mostPlayed ? .mostPlayed : nil
    }

    /// Carries a listen over to a newly tuned mix: what's been picked, and what's been skipped,
    /// so retuning mid-listen doesn't start again from the top. How far skips and keeps have
    /// moved the share of new finds carries over too, on top of the new tuning's share.
    public mutating func continueListen(from earlier: LiveMix) {
        for identity in earlier.picks { note(picked: identity) }
        pickReasons.merge(earlier.pickReasons) { _, earlier in earlier }
        if earlier.startingShare > 0, earlier.newShare != earlier.startingShare {
            newShare = (newShare * earlier.newShare / earlier.startingShare).clamped(to: shareRange)
        }
        for (artist, bias) in earlier.artistBias { artistBias[artist] = bias }
        genreBias = earlier.genreBias
        lovedGenre = earlier.lovedGenre
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

    /// How much a song heard lately gives way to others, so the radio doesn't play the same
    /// songs every day: about half as likely the day after it's heard, back to full over a few
    /// days. The songs heard in the last few hours rest besides. See ``restPeriod``.
    static func freshness(lastHeard: Date, now: Date) -> Double {
        let hours = max(0, now.timeIntervalSince(lastHeard)) / 3_600
        return 1 - 0.55 * exp(-hours / 36)
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
