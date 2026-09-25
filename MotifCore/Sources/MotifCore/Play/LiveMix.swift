import Foundation

/// A mix that picks each song as the one before it starts, as Apple Music's stations do, so
/// what you skip and what you let play steer what comes next. Motif Radio and the moods play
/// this way, and never run out.
///
/// Songs you know and new finds are drawn from separately, the new ones for a share of the
/// picks. Skipping an artist makes them rarer for the rest of the listen, and letting one play
/// makes them a little likelier; skipping new finds makes them rarer, and keeping them makes
/// them more common. No song comes up twice until every other one has, and an artist doesn't
/// follow themselves when anyone else could.
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

        public init(song: MixSong, weight: Double, isNew: Bool = false, isResting: Bool = false) {
            self.song = song
            self.weight = weight
            self.isNew = isNew
            self.isResting = isResting
        }
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
    private var picked: Set<String> = []
    /// How much likelier each artist has become this listen: under 1 once skipped.
    private var artistBias: [String: Double] = [:]
    private let byIdentity: [String: Int]
    private var random: SeededGenerator

    /// Artists who can't come straight back.
    private static let artistGap = 2
    private static let newShareRange = 0.05...0.6

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
        let choices = spaced.isEmpty ? fresh : spaced

        guard let choice = draw(from: choices) else { return nil }
        note(picked: choice.song.songIdentity)
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
        if candidate.isNew { newShare = (newShare * 0.7).clamped(to: Self.newShareRange) }
    }

    /// The song played through, or near enough.
    public mutating func noteFinished(_ identity: String) {
        guard let index = byIdentity[identity] else { return }
        let candidate = candidates[index]
        let artist = candidate.song.artistKey
        artistBias[artist] = min(3, (artistBias[artist] ?? 1) * 1.25)
        if candidate.isNew { newShare = (newShare * 1.2 + 0.02).clamped(to: Self.newShareRange) }
    }

    /// Everything has been picked: begin again, keeping the latest picks out so the end of one
    /// round doesn't meet the start of the next.
    private mutating func startOver() {
        let keep = Array(picks.suffix(min(20, candidates.count / 2)))
        picks = keep
        picked = Set(keep)
    }

    private mutating func draw(from choices: [Candidate]) -> Candidate? {
        let weights = choices.map { $0.weight * (artistBias[$0.song.artistKey] ?? 1) }
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
            let genre = history.songMetadata[aggregate.identity]?.genre
            return Candidate(
                song: aggregate.song,
                weight: weight(plays: aggregate.dates.count, lastHeard: aggregate.lastHeard, now: now)
                    * tuning.factor(genre: genre, lastHeard: aggregate.lastHeard, now: now)
                    * fit.factor(for: aggregate, genre: genre, recentSkips: signals.recentSkips(of: aggregate.identity, now: now)),
                isResting: aggregate.lastHeard >= rested
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
            Candidate(song: song, weight: score, isResting: song.lastHeard >= rested)
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
