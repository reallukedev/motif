import Testing
import Foundation
@testable import MotifCore

@Suite("Library order")
struct LibraryOrderingTests {
    struct Item: Equatable {
        let title: String
        var artist = ""
        var album = ""
        var added: Date?
        var plays = 0

        var keys: LibrarySortKeys {
            LibrarySortKeys(title: title, artist: artist, album: album, added: added, plays: plays)
        }
    }

    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func titles(_ items: [Item]) -> [String] { items.map(\.title) }

    @Test("names go A to Z as Music has them: no case, no accents, no leading article, numbers in order, # last")
    func names() {
        let items = ["the Beatles", "Zed", "1999", "Émilie", "A Tribe Called Quest", "abba", "Track 10", "Track 2", "東京"]
            .map { Item(title: $0) }
        let sorted = LibrarySort.sorted(items, by: .title) { $0.keys }
        #expect(titles(sorted) == ["abba", "the Beatles", "Émilie", "Track 2", "Track 10", "A Tribe Called Quest", "Zed", "1999", "東京"])
    }

    @Test("descending names run Z to A, with the ones under # first")
    func namesDescending() {
        let items = ["Beta", "Alpha", "7 Rings"].map { Item(title: $0) }
        let sorted = LibrarySort.sorted(items, by: LibraryOrder(.title, ascending: false)) { $0.keys }
        #expect(titles(sorted) == ["7 Rings", "Beta", "Alpha"])
    }

    @Test("newest first, and anything without a date after everything with one")
    func dates() {
        let items = [
            Item(title: "Old", added: now.addingTimeInterval(-100)),
            Item(title: "Undated"),
            Item(title: "New", added: now),
        ]
        #expect(titles(LibrarySort.sorted(items, by: .natural(.added)) { $0.keys }) == ["New", "Old", "Undated"])
        #expect(titles(LibrarySort.sorted(items, by: LibraryOrder(.added, ascending: true)) { $0.keys }) == ["Old", "New", "Undated"])
    }

    @Test("ties go by title, then artist, so the same library always reads the same way")
    func ties() {
        let items = [
            Item(title: "Same", artist: "Zoe", plays: 3),
            Item(title: "Other", plays: 3),
            Item(title: "Same", artist: "Ada", plays: 3),
            Item(title: "Top", plays: 9),
        ]
        let sorted = LibrarySort.sorted(items, by: .natural(.plays)) { $0.keys }
        #expect(sorted.map { "\($0.title) \($0.artist)" } == ["Top ", "Other ", "Same Ada", "Same Zoe"])
    }

    @Test("an artist's order keeps their albums together by title")
    func byArtist() {
        let items = [
            Item(title: "Bell", artist: "The Hollows"),
            Item(title: "Alone", artist: "Ivy"),
            Item(title: "Anchor", artist: "Hollows"),
        ]
        let sorted = LibrarySort.sorted(items, by: .natural(.artist)) { $0.keys }
        #expect(titles(sorted) == ["Anchor", "Bell", "Alone"])
    }

    @Test("a filter needs every word, anywhere in the title, artist or album, ignoring case and accents")
    func filter() {
        let items = [
            Item(title: "Still Water", artist: "Ada Kestrel", album: "Tides"),
            Item(title: "Café Nights", artist: "Luma"),
            Item(title: "Water Under", artist: "Nova"),
        ]
        #expect(titles(LibrarySort.filtered(items, matching: "water ada") { $0.keys }) == ["Still Water"])
        #expect(titles(LibrarySort.filtered(items, matching: "CAFE") { $0.keys }) == ["Café Nights"])
        #expect(titles(LibrarySort.filtered(items, matching: "tides") { $0.keys }) == ["Still Water"])
        #expect(LibrarySort.filtered(items, matching: "  ") { $0.keys }.count == 3)
    }

    @Test("sections follow the index letters, # last")
    func sections() {
        let items = ["Abba", "the Avalanches", "Björk", "2Pac", "Air"].map { Item(title: $0) }
        let sorted = LibrarySort.sorted(items, by: .title) { $0.keys }
        let sections = LibrarySort.sections(sorted) { $0.title }
        #expect(sections.map(\.letter) == ["A", "B", "#"])
        #expect(sections.first.map { titles($0.items) } == ["Abba", "Air", "the Avalanches"])
    }

    @Test("index letters", arguments: [
        ("The Beatles", "B"), ("émilie", "E"), ("1999", "#"), ("東京", "#"), ("The", "T"), ("", "#"),
    ])
    func indexLetter(name: String, letter: String) {
        #expect(LibraryCollation.indexLetter(name) == letter)
    }

    @Test("an order survives being stored")
    func storedOrder() {
        let order = LibraryOrder(.played, ascending: false)
        #expect(LibraryOrder(rawValue: order.rawValue) == order)
        #expect(LibraryOrder(rawValue: "time.ascending") == LibraryOrder(.time, ascending: true))
        #expect(LibraryOrder(rawValue: "loudness.ascending") == nil)
    }
}
