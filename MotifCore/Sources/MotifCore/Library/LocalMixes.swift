import Foundation

extension LiveMix {
    /// Motif Radio from your own music: the songs you play most, the likelier, and the ones
    /// you've never played as its new finds. Tuned, and fitted to the moment, as the Apple
    /// Music radio is.
    public static func motifRadio(
        from tracks: [LocalTrack],
        history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        tuning: RadioTuning = .standard,
        moment: RadioMoment = .anytime,
        drives: DriveLog = DriveLog(),
        now: Date = .now,
        calendar: Calendar = .current,
        seed: UInt64
    ) -> LiveMix {
        let played = MixBuilder.aggregate(history, signals: signals, now: now, calendar: calendar)
        let fit = RadioMomentFit(moment: moment, songs: played, drives: drives)
        return local(
            tracks, played: played, metadata: history.songMetadata, signals: signals, now: now, seed: seed,
            newShare: fit.newShare(tuning.discovery.newShare), moment: moment
        ) { track, aggregate in
            let genre = track.genre ?? history.songMetadata[track.identity]?.genre
            let tuned = tuning.factor(genre: genre, lastHeard: aggregate?.lastHeard, now: now)
            guard let aggregate else { return tuned * fit.factor(newFindGenre: genre) }
            return tuned * fit.factor(for: aggregate, genre: genre, recentSkips: signals.recentSkips(of: track.identity, now: now))
        }
    }

    /// A mood from your own music: the songs whose genre suits it, played ones by how much,
    /// the rest as new finds.
    /// - Parameter finds: songs found for the mood elsewhere, like ones that suit it, taken as
    ///   they are: a server's often have no genre to go by.
    public static func mood(
        _ mood: Mood,
        from tracks: [LocalTrack],
        finds: [LocalTrack] = [],
        history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        now: Date = .now,
        seed: UInt64
    ) -> LiveMix {
        let suited = tracks.filter { track in
            (track.genre ?? history.songMetadata[track.identity]?.genre).map { mood.suits(genre: $0) } ?? false
        }
        let played = MixBuilder.aggregate(history, signals: signals, now: now, calendar: .current)
        return local(
            suited + finds, played: played, metadata: history.songMetadata, signals: signals, now: now, seed: seed,
            newShare: finds.isEmpty ? 0.3 : 0.4
        ) { _, _ in 1 }
    }

    /// Autoplay from your own music: your songs like the last few played, the ones you've
    /// never played as its new finds. See ``autoplay(after:from:signals:newFinds:now:calendar:seed:)``.
    public static func autoplay(
        after seeds: [AutoplaySeed],
        from tracks: [LocalTrack],
        history: ListeningHistory,
        signals: ListeningSignals = ListeningSignals(),
        now: Date = .now,
        calendar: Calendar = .current,
        seed: UInt64
    ) -> LiveMix {
        let affinity = AutoplayAffinity(seeds: seeds, history: history)
        let seedIdentities = Set(seeds.map(\.songIdentity))
        let played = MixBuilder.aggregate(history, signals: signals, now: now, calendar: calendar)
        let others = tracks.filter { !seedIdentities.contains($0.identity) }
        let mix = local(others, played: played, metadata: history.songMetadata, signals: signals, now: now, seed: seed, newShare: 0.25) { track, _ in
            let known = history.songMetadata[track.identity]
            return affinity.likeness(artistName: track.artist, genre: track.genre ?? known?.genre, releaseYear: track.year ?? known?.releaseYear)
        }
        return LiveMix(candidates: mix.candidates, newShare: affinity.newShare(closeMatches: mix.candidates.filter { !$0.isNew }), seed: seed)
    }

    /// Your songs as candidates: one per song, the file before a server's copy, played ones
    /// weighted as Motif Radio weighs them, never-played ones as new finds.
    private static func local(
        _ tracks: [LocalTrack],
        played: [MixBuilder.Aggregate],
        metadata: [String: SongMetadata],
        signals: ListeningSignals,
        now: Date,
        seed: UInt64,
        newShare: Double,
        moment: RadioMoment = .anytime,
        factor: (LocalTrack, MixBuilder.Aggregate?) -> Double
    ) -> LiveMix {
        let played = Dictionary(played.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        let rested = now.addingTimeInterval(-restPeriod)
        var seen = Set<String>()
        let candidates: [Candidate] = tracks
            .sorted { !$0.isFromServer && $1.isFromServer }
            .compactMap { track in
                guard seen.insert(track.identity).inserted, !signals.excludes(track.identity, now: now) else { return nil }
                let known = metadata[track.identity]
                let genre = track.genre ?? known?.genre
                if let aggregate = played[track.identity] {
                    return Candidate(
                        song: track.mixSong(plays: aggregate.dates.count, lastHeard: aggregate.lastHeard),
                        weight: weight(plays: aggregate.dates.count, lastHeard: aggregate.lastHeard, now: now) * factor(track, aggregate),
                        isResting: aggregate.lastHeard >= rested,
                        genre: genre,
                        releaseYear: track.year ?? known?.releaseYear
                    )
                }
                return Candidate(song: track.mixSong(), weight: factor(track, nil), isNew: true, genre: genre, releaseYear: track.year ?? known?.releaseYear)
            }
        return LiveMix(candidates: candidates, newShare: newShare, moment: moment, seed: seed)
    }
}
