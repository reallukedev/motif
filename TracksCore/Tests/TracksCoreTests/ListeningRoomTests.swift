import Foundation
import Testing
@testable import TracksCore

struct ListeningRoomTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    struct Play {
        var title: String
        var genre: String
        var year: Int? = nil
        /// Days before now, and the hour it was played.
        var daysAgo: Double
        var hour: Int = 20
    }

    func history(_ plays: [Play]) -> ListeningHistory {
        var stats: [CaptureStat] = []
        var metadata: [String: SongMetadata] = [:]
        for play in plays {
            let day = calendar.startOfDay(for: now.addingTimeInterval(-play.daysAgo * 86_400))
            let date = day.addingTimeInterval(Double(play.hour) * 3_600)
            stats.append(CaptureStat(songKey: play.title, songID: play.title, title: play.title, artistName: "Artist", capturedAt: date))
            metadata[HistoryImport.key(title: play.title, artistName: "Artist")] = SongMetadata(genre: play.genre, releaseYear: play.year)
        }
        return ListeningHistory(stats).with(artistArtwork: [:], songMetadata: metadata)
    }

    @Test("a mood holds your songs whose genre suits it, the most played first")
    func moodSongs() {
        let room = ListeningRoom.mood(.chill, in: history([
            Play(title: "Calm", genre: "Ambient", daysAgo: 1),
            Play(title: "Calm", genre: "Ambient", daysAgo: 2),
            Play(title: "Smooth", genre: "Jazz", daysAgo: 3),
            Play(title: "Loud", genre: "Metal", daysAgo: 1),
        ]), now: now, calendar: calendar)
        #expect(room.songs.map(\.song.title) == ["Calm", "Smooth"])
        #expect(room.plays == 3)
    }

    @Test("when you play it most is said only once one part of the day stands out")
    func peak() {
        let evenings = (0..<12).map { Play(title: "Song \($0 % 4)", genre: "Jazz", daysAgo: Double($0), hour: 19) }
        #expect(ListeningRoom.genre(MusicGenre.all.first { $0.id == "jazz" }!, in: history(evenings), now: now, calendar: calendar).peak == .evening)
        let few = Array(evenings.prefix(5))
        #expect(ListeningRoom.genre(MusicGenre.all.first { $0.id == "jazz" }!, in: history(few), now: now, calendar: calendar).peak == nil)
    }

    @Test("Wind Down keeps evening songs and runs from brighter genres to calmer")
    func windDown() {
        let room = ListeningRoom.mood(.chill, in: history([
            Play(title: "Morning", genre: "Ambient", daysAgo: 1, hour: 8),
            Play(title: "Ambient", genre: "Ambient", daysAgo: 1),
            Play(title: "Indie", genre: "Indie Rock", daysAgo: 2),
            Play(title: "Soul", genre: "Soul", daysAgo: 3),
        ]), now: now, calendar: calendar)
        let order = room.windDown().map(\.song.title)
        #expect(!order.contains("Morning"))
        #expect(order.last == "Ambient")
    }

    @Test("a section with fewer than three songs says too little to show")
    func fewest() {
        let room = ListeningRoom.mood(.heartbreak, in: history([
            Play(title: "Again", genre: "Blues", daysAgo: 1),
            Play(title: "Again", genre: "Blues", daysAgo: 1),
            Play(title: "Again", genre: "Blues", daysAgo: 1),
        ]), now: now, calendar: calendar)
        #expect(room.overAndOver().isEmpty)
    }

    @Test("over and over finds songs played three times or more in one day")
    func overAndOver() {
        let plays = ["A", "B", "C"].flatMap { title in (0..<3).map { _ in Play(title: title, genre: "Blues", daysAgo: 4) } }
            + [Play(title: "Once", genre: "Blues", daysAgo: 1)]
        let room = ListeningRoom.mood(.heartbreak, in: history(plays), now: now, calendar: calendar)
        #expect(Set(room.overAndOver().map(\.song.title)) == ["A", "B", "C"])
        #expect(room.overAndOver().allSatisfy { $0.bestDay == 3 })
    }

    @Test("rising holds songs played more in the last 30 days than the 30 before")
    func rising() {
        let plays = ["Up", "Up2", "Up3"].flatMap { title in [Play(title: title, genre: "Rap", daysAgo: 2), Play(title: title, genre: "Rap", daysAgo: 5)] }
            + [Play(title: "Down", genre: "Rap", daysAgo: 40), Play(title: "Down", genre: "Rap", daysAgo: 45), Play(title: "Down", genre: "Rap", daysAgo: 3)]
        let room = ListeningRoom.genre(MusicGenre.all.first { $0.id == "hip-hop" }!, in: history(plays), now: now, calendar: calendar)
        #expect(Set(room.rising().map(\.song.title)) == ["Up", "Up2", "Up3"])
    }

    @Test("decades show only once your songs span two or more")
    func decades() {
        let ninetiesOnly = ListeningRoom.genre(MusicGenre.all.first { $0.id == "rock" }!, in: history([
            Play(title: "A", genre: "Rock", year: 1991, daysAgo: 1),
            Play(title: "B", genre: "Rock", year: 1997, daysAgo: 1),
        ]), now: now, calendar: calendar)
        #expect(ninetiesOnly.decades().isEmpty)

        let spread = ListeningRoom.genre(MusicGenre.all.first { $0.id == "rock" }!, in: history([
            Play(title: "A", genre: "Rock", year: 1991, daysAgo: 1),
            Play(title: "B", genre: "Rock", year: 2004, daysAgo: 1),
            Play(title: "C", genre: "Rock", daysAgo: 1),
        ]), now: now, calendar: calendar)
        #expect(spread.decades().map(\.start) == [1990, 2000])
    }

    @Test("songs heard on the road are the ones played inside a drive")
    func onTheRoad() {
        let titles = ["A", "B", "C", "D"]
        let plays = titles.map { Play(title: $0, genre: "Indie Rock", daysAgo: 1, hour: 18) }
        let day = calendar.startOfDay(for: now.addingTimeInterval(-86_400))
        let drive = DateInterval(start: day.addingTimeInterval(17.5 * 3_600), duration: 3_600)
        let room = ListeningRoom.mood(.drive, in: history(plays), drives: DriveLog(drives: [drive]), now: now, calendar: calendar)
        #expect(room.onTheRoad().count == 4)
        let withoutDrives = ListeningRoom.mood(.drive, in: history(plays), now: now, calendar: calendar)
        #expect(withoutDrives.onTheRoad().isEmpty)
    }
}
