import Foundation

/// Turns captures and sessions into the numbers the statistics screens show.
///
/// Pure functions over plain values, so it's all testable without SwiftData. There's no
/// cache: five thousand captures take a few milliseconds (see `StatsCalculatorTests`).
public enum StatsCalculator {

    /// Pass every capture, not just the range: whether a song is new depends on
    /// everything before it.
    public static func summary(
        range: StatsRange,
        captures: [CaptureStat],
        sessions: [SessionStat],
        calendar: Calendar = .current,
        now: Date = .now,
        topLimit: Int = 5,
        songLimit: Int = 8
    ) -> StatsSummary {
        summary(
            range: range,
            history: ListeningHistory(captures),
            sessions: sessions,
            calendar: calendar,
            now: now,
            topLimit: topLimit,
            songLimit: songLimit
        )
    }

    public static func summary(
        range: StatsRange,
        history: ListeningHistory,
        sessions: [SessionStat],
        calendar: Calendar = .current,
        now: Date = .now,
        topLimit: Int = 5,
        songLimit: Int = 8
    ) -> StatsSummary {
        let interval = range.interval(containing: now, calendar: calendar)
        let indices = history.indices(in: interval)
        let ordered = history.captures
        let inRange = Array(ordered[indices])

        let sessionsInRange = sessions.filter { session in
            guard let interval else { return true }
            return overlap(of: session, with: interval) != nil
        }

        let listening = indices.reduce(0) { $0 + history.seconds[$1] }
        let comparison = comparisonInterval(for: range, history: history, calendar: calendar, now: now)
        let previousIndices = comparison.map { history.indices(in: $0) }

        // All time has no interval, so its chart runs from the first capture to now, and
        // across at least a week: a day-old history would otherwise be one lone bar, which
        // isn't a chart.
        let span = interval ?? ordered.first.map { first in
            let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: min(first.capturedAt, weekAgo), end: max(now, first.capturedAt))
        }
        let unit = timelineUnit(for: range, span: span, calendar: calendar)
        var days = CalendarUnitCursor(calendar: calendar, unit: .day)
        let activeDays = Set(inRange.compactMap { days.start(of: $0.capturedAt) }).count
        let elapsedDays = elapsedDayCount(range: range, interval: interval, history: history, calendar: calendar, now: now)

        let firstHearings = indices.filter { history.isFirstHearing[$0] }
        let songTallies = tallySongs(indices, in: history)
        let artistTallies = tallyArtists(indices, in: history)
        let albumTallies = tallyAlbums(indices, in: history)
        let streak = streak(in: history, calendar: calendar, now: now)
        let timeline = timeline(indices, in: history, unit: unit, span: span, calendar: calendar)
        let listeningSessions = listeningSessions(indices, in: history)
        let genres = genreFigures(indices, in: history, calendar: calendar, limit: max(topLimit, 8))
        let dayTypes = dayTypeAverages(
            indices,
            in: history,
            range: range,
            interval: interval,
            calendar: calendar,
            now: now
        )

        let context = InsightContext(
            range: range,
            interval: interval,
            history: history,
            indices: indices,
            inRange: inRange,
            sessions: sessionsInRange,
            listeningSeconds: listening,
            previousListeningSeconds: previousIndices.map { $0.reduce(0) { $0 + history.seconds[$1] } },
            firstTimeHeardCount: firstHearings.count,
            newArtistCount: indices.count { history.isFirstArtistHearing[$0] },
            topSongs: songTallies,
            topArtists: artistTallies,
            uniqueArtistCount: artistTallies.count,
            streak: streak,
            genres: genres,
            calendar: calendar
        )

        return StatsSummary(
            range: range,
            generatedAt: now,
            interval: interval,
            captureCount: inRange.count,
            uniqueSongCount: songTallies.count,
            uniqueArtistCount: artistTallies.count,
            listeningSeconds: listening,
            activeDays: activeDays,
            dailyAverageSeconds: elapsedDays > 0 ? listening / Double(elapsedDays) : 0,
            previousCaptureCount: previousIndices?.count,
            previousListeningSeconds: context.previousListeningSeconds,
            sessionCount: sessionsInRange.count,
            radioSessionSeconds: sessionsInRange.reduce(0) { total, session in
                total + (interval.map { overlap(of: session, with: $0) ?? 0 }
                    ?? max(0, session.finishedAt.timeIntervalSince(session.startedAt)))
            },
            firstTimeHeardCount: firstHearings.count,
            newArtistCount: context.newArtistCount,
            topSongs: Array(songTallies.prefix(songLimit)),
            topArtists: Array(artistTallies.prefix(topLimit)),
            topAlbums: Array(albumTallies.prefix(topLimit)),
            topStations: rank(inRange.compactMap(\.stationName), limit: topLimit),
            discoveries: Array(
                tallySongs(firstHearings, in: history)
                    .sorted { ($0.firstHeard, $1.title) > ($1.firstHeard, $0.title) }
                    .prefix(songLimit)
            ),
            capturesWithoutStation: capturesWithoutStation(inRange),
            timeline: timeline,
            timelineUnit: unit,
            hourly: hourly(for: inRange, calendar: calendar),
            weekdays: weekdays(for: inRange, calendar: calendar, now: now),
            heatMap: heatMap(for: inRange, calendar: calendar),
            sources: sources(for: inRange),
            streak: streak,
            insights: insights(context),
            uniqueAlbumCount: albumTallies.count,
            oneOffSongCount: songTallies.count { $0.count == 1 },
            deepestArtist: deepestArtist(in: artistTallies),
            // Without earlier history every song is new, and the list would just be Top Songs.
            newFavourites: context.hasHistoryBeforeRange
                ? newFavourites(indices, firstHearings: firstHearings, in: history, limit: songLimit)
                : [],
            newSongTimeline: self.timeline(firstHearings, in: history, unit: unit, span: span, calendar: calendar),
            pace: pace(
                timeline: timeline,
                range: range,
                interval: interval,
                history: history,
                unit: unit,
                calendar: calendar,
                now: now
            ),
            dayParts: dayParts(indices, in: history, calendar: calendar),
            weekdayAverageSeconds: dayTypes.weekday,
            weekendAverageSeconds: dayTypes.weekend,
            listeningSessions: listeningSessions,
            records: records(indices, in: history, longestSession: listeningSessions.longest, calendar: calendar),
            topGenres: genres.topGenres,
            genreCount: genres.genreCount,
            knownGenrePlays: genres.knownGenrePlays,
            decades: genres.decades,
            knownYearPlays: genres.knownYearPlays,
            recentReleasePlays: genres.recentReleasePlays,
            medianReleaseYear: genres.medianReleaseYear,
            oldestRelease: genres.oldest
        )
    }

    /// Plays with no station name, or only whitespace. Each distinct name is folded once.
    static func capturesWithoutStation(_ captures: [CaptureStat]) -> Int {
        var isBlank: [String: Bool] = [:]
        return captures.count { capture in
            guard let name = capture.stationName else { return true }
            if let known = isBlank[name] { return known }
            let blank = folded(name).isEmpty
            isBlank[name] = blank
            return blank
        }
    }

    // MARK: - Comparison periods

    /// The part of the previous period that lines up with how far we are into this one.
    /// Comparing a half-finished week with a whole one made every Monday look like a slump.
    /// `nil` if there's no history from before this period started.
    static func comparisonInterval(
        for range: StatsRange,
        history: ListeningHistory,
        calendar: Calendar,
        now: Date
    ) -> DateInterval? {
        guard let current = range.interval(containing: now, calendar: calendar),
              let previous = range.previousInterval(before: current, calendar: calendar),
              let earliest = history.first?.capturedAt, earliest < current.start
        else { return nil }
        let elapsed = min(now, current.end).timeIntervalSince(current.start)
        return DateInterval(start: previous.start, end: min(previous.end, previous.start.addingTimeInterval(elapsed)))
    }

    /// Days of the range so far, including today.
    static func elapsedDayCount(
        range: StatsRange,
        interval: DateInterval?,
        history: ListeningHistory,
        calendar: Calendar,
        now: Date
    ) -> Int {
        guard let start = interval?.start ?? history.first?.capturedAt else { return 0 }
        let end = min(now, interval?.end.addingTimeInterval(-1) ?? now)
        guard end >= start else { return 0 }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
        return days + 1
    }

    // MARK: - Charts over time

    /// Days for a week or month, months for a year. All time depends on how much history
    /// there is.
    static func timelineUnit(
        for range: StatsRange,
        span: DateInterval?,
        calendar: Calendar
    ) -> Calendar.Component {
        switch range {
        case .week, .month: .day
        case .year: .month
        case .allTime:
            // Under ~10 weeks, days still fit.
            (span?.duration ?? 0) > 70 * 86_400 ? .month : .day
        }
    }

    /// One bucket per unit across the span, including empty ones so gaps show up. Capped at
    /// 120 columns, keeping the most recent.
    static func timeline(
        _ indices: some Sequence<Int>,
        in history: ListeningHistory,
        unit: Calendar.Component,
        span: DateInterval?,
        calendar: Calendar,
        maximumColumns: Int = 120
    ) -> [TimeBucket] {
        guard let span, var cursor = calendar.dateInterval(of: unit, for: span.start)?.start
        else { return [] }

        var counts: [Date: (count: Int, seconds: TimeInterval)] = [:]
        var units = CalendarUnitCursor(calendar: calendar, unit: unit)
        for index in indices {
            let capture = history.captures[index]
            guard let start = units.start(of: capture.capturedAt) else { continue }
            counts[start, default: (0, 0)].count += 1
            counts[start, default: (0, 0)].seconds += history.seconds[index]
        }

        var buckets: [TimeBucket] = []
        // `span.end` is exclusive; without the -1 a range ending on a boundary gets an
        // extra empty column.
        let limit = span.end.addingTimeInterval(-1)
        while cursor <= limit {
            let entry = counts[cursor]
            buckets.append(TimeBucket(start: cursor, count: entry?.count ?? 0, seconds: entry?.seconds ?? 0))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        return Array(buckets.suffix(maximumColumns))
    }

    /// The last `count` days, today included and last, with empty days kept.
    public static func recentDays(
        _ count: Int,
        history: ListeningHistory,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [TimeBucket] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today)
        else { return [] }
        let span = DateInterval(start: start, end: end)
        return timeline(history.indices(in: span), in: history, unit: .day, span: span, calendar: calendar)
    }

    /// All 24 hours, including empty ones.
    static func hourly(for captures: [CaptureStat], calendar: Calendar) -> [HourCount] {
        var counts: [Int: Int] = [:]
        var clock = DayClock(calendar: calendar)
        for capture in captures {
            guard let hour = clock.facts(for: capture.capturedAt)?.hour else { continue }
            counts[hour, default: 0] += 1
        }
        return (0...23).map { HourCount(hour: $0, count: counts[$0] ?? 0) }
    }

    /// Seven days in the locale's order. The weekend comes from the calendar, since it
    /// isn't Saturday and Sunday everywhere.
    static func weekdays(for captures: [CaptureStat], calendar: Calendar, now: Date) -> [WeekdayCount] {
        var counts: [Int: Int] = [:]
        var clock = DayClock(calendar: calendar)
        for capture in captures {
            guard let weekday = clock.facts(for: capture.capturedAt)?.weekday else { continue }
            counts[weekday, default: 0] += 1
        }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let weekday = calendar.component(.weekday, from: day)
            return WeekdayCount(
                weekday: weekday,
                count: counts[weekday] ?? 0,
                isWeekend: calendar.isDateInWeekend(day)
            )
        }
    }

    /// The full 7×24 grid, empty cells included.
    static func heatMap(for captures: [CaptureStat], calendar: Calendar) -> [HeatCell] {
        var counts: [Int: Int] = [:]
        var clock = DayClock(calendar: calendar)
        for capture in captures {
            guard let facts = clock.facts(for: capture.capturedAt) else { continue }
            counts[facts.weekday * 100 + facts.hour, default: 0] += 1
        }
        return (1...7).flatMap { weekday in
            (0...23).map { hour in
                HeatCell(weekday: weekday, hour: hour, count: counts[weekday * 100 + hour] ?? 0)
            }
        }
    }

    static func sources(for captures: [CaptureStat]) -> [SourceCount] {
        let counts = counts(of: captures) { $0.kind }
        return CaptureKind.allCases
            .compactMap { kind in counts[kind].map { SourceCount(kind: kind, count: $0) } }
            .sorted { ($0.count, $1.kind.rawValue) > ($1.count, $0.kind.rawValue) }
    }

    // MARK: - Streaks

    /// Consecutive days with any listening. A streak isn't broken until a full day passes
    /// with nothing, so it still counts if the last song was yesterday.
    public static func streak(in history: ListeningHistory, calendar: Calendar = .current, now: Date = .now) -> Streak {
        guard !history.isEmpty else { return .none }
        var cursor = CalendarUnitCursor(calendar: calendar, unit: .day)
        let days = Set(history.captures.compactMap { cursor.start(of: $0.capturedAt) })
        let sortedDays = days.sorted()

        var longest = 0
        var run = 0
        var previous: Date?
        for day in sortedDays {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return Streak(current: 0, longest: longest, currentStart: nil)
        }
        guard var cursor = days.contains(today) ? today : (days.contains(yesterday) ? yesterday : nil)
        else { return Streak(current: 0, longest: longest, currentStart: nil) }

        var current = 0
        var start = cursor
        while days.contains(cursor) {
            current += 1
            start = cursor
            guard let before = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = before
        }
        return Streak(current: current, longest: max(longest, current), currentStart: start)
    }

    // MARK: - Tallies

    /// Songs, most played first. Ties go to the most recent, then alphabetical, so the
    /// order doesn't shuffle between renders.
    static func tallySongs(_ indices: some Sequence<Int>, in history: ListeningHistory) -> [SongTally] {
        var groups: [String: [Int]] = [:]
        for index in indices { groups[history.captures[index].songIdentity, default: []].append(index) }

        return groups.map { identity, members in
            let captures = members.map { history.captures[$0] }
            // Members are in history order.
            let first = captures[0]
            let latest = captures[captures.count - 1]
            // Use a resolved row if there is one, so the song can be played.
            let resolved = captures.last { !$0.songID.isEmpty } ?? latest
            return SongTally(
                id: identity,
                songKey: resolved.songKey,
                songID: resolved.songID,
                title: resolved.title,
                artistName: resolved.artistName,
                albumTitle: captures.last { $0.albumTitle?.isEmpty == false }?.albumTitle,
                artworkURL: bestArtwork(in: captures),
                count: captures.count,
                firstHeard: first.capturedAt,
                lastHeard: latest.capturedAt,
                listeningSeconds: members.reduce(0) { $0 + history.seconds[$1] }
            )
        }
        .sorted { ($0.count, $0.lastHeard, $1.title) > ($1.count, $1.lastHeard, $0.title) }
    }

    /// Artists, most played first. Blank names are skipped.
    static func tallyArtists(_ indices: some Sequence<Int>, in history: ListeningHistory) -> [ArtistTally] {
        var groups: [String: [Int]] = [:]
        for index in indices where !history.captures[index].artistIdentity.isEmpty {
            groups[history.captures[index].artistIdentity, default: []].append(index)
        }

        return groups.map { identity, members in
            let captures = members.map { history.captures[$0] }
            let spellings = counts(of: captures) { $0.artistName.trimmingCharacters(in: .whitespacesAndNewlines) }
            let name = spellings.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? captures[0].artistName
            let bySong = Dictionary(grouping: captures, by: \.songIdentity)
            let favourite = bySong.values.max { ($0.count, $0.last?.capturedAt ?? .distantPast) < ($1.count, $1.last?.capturedAt ?? .distantPast) }
            return ArtistTally(
                id: identity,
                name: name,
                count: captures.count,
                songCount: bySong.count,
                listeningSeconds: members.reduce(0) { $0 + history.seconds[$1] },
                artworkURL: history.artistArtwork[identity]
                    ?? favourite.flatMap(bestArtwork)
                    ?? bestArtwork(in: captures),
                firstHeard: captures[0].capturedAt,
                lastHeard: captures[captures.count - 1].capturedAt
            )
        }
        .sorted { ($0.count, $0.listeningSeconds, $1.name) > ($1.count, $1.listeningSeconds, $0.name) }
    }

    /// Albums, most played first. Captures without an album are skipped.
    static func tallyAlbums(_ indices: some Sequence<Int>, in history: ListeningHistory) -> [AlbumTally] {
        var groups: [String: [Int]] = [:]
        for index in indices {
            guard let identity = history.captures[index].albumIdentity else { continue }
            groups[identity, default: []].append(index)
        }

        return groups.map { identity, members in
            let captures = members.map { history.captures[$0] }
            let latest = captures[captures.count - 1]
            return AlbumTally(
                id: identity,
                title: latest.albumTitle ?? "",
                artistName: latest.artistName,
                count: captures.count,
                songCount: Set(captures.map(\.songIdentity)).count,
                artworkURL: bestArtwork(in: captures),
                listeningSeconds: members.reduce(0) { $0 + history.seconds[$1] }
            )
        }
        .sorted { ($0.count, $0.listeningSeconds, $1.title) > ($1.count, $1.listeningSeconds, $0.title) }
    }

    /// Most recent artwork URL that will actually load (MusicKit sometimes hands out
    /// `musicKit://artwork/transient/…` URLs that don't).
    static func bestArtwork(in captures: [CaptureStat]) -> String? {
        captures.last { ArtworkURL.isLoadable($0.artworkURL) }?.artworkURL
    }

    /// Counts names, most frequent first, ties alphabetical.
    static func rank(_ names: [String], limit: Int) -> [NamedCount] {
        var counts: [String: Int] = [:]
        for name in names where !normalised(name).isEmpty {
            counts[name, default: 0] += 1
        }
        return counts
            .map { NamedCount(name: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.name) < ($0.count, $1.name) }
            .prefix(limit)
            .map { $0 }
    }

    static func counts<Key: Hashable>(
        of captures: [CaptureStat],
        by key: (CaptureStat) -> Key
    ) -> [Key: Int] {
        var counts: [Key: Int] = [:]
        for capture in captures { counts[key(capture), default: 0] += 1 }
        return counts
    }

    /// The part of a session inside `interval`, or `nil` if they don't overlap. Clipping
    /// keeps "this week" and "this month" from both claiming the whole of a session that
    /// spans the boundary.
    static func overlap(of session: SessionStat, with interval: DateInterval) -> TimeInterval? {
        let start = max(session.startedAt, interval.start)
        let end = min(session.finishedAt, interval.end)
        guard end > start else { return nil }
        return end.timeIntervalSince(start)
    }

    static func normalised(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trimmed, case- and accent-insensitive.
    public static func folded(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension StatsRange {
    /// The calendar period ("this week", not "the last seven days"), or `nil` for all time.
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let component else { return nil }
        return calendar.dateInterval(of: component, for: date)
    }

    /// Last week, last month or last year. Uses the calendar rather than subtracting a
    /// length, because months differ.
    public func previousInterval(before current: DateInterval, calendar: Calendar = .current) -> DateInterval? {
        guard let component else { return nil }
        return calendar.dateInterval(of: component, for: current.start.addingTimeInterval(-1))
    }

    var component: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .allTime: nil
        }
    }
}
