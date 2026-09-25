import Testing
import Foundation
@testable import MotifCore

@Suite("What your devices say to each other")
struct NearbyMessageTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("a message comes back as it went, behind its length", arguments: [
        NearbyMessage.hello(id: "A1", name: "Luke's Mac", platform: "Mac"),
        .state(NearbyState(title: "Juno", artist: "Sabrina Carpenter", isPlaying: true, position: 42, duration: 223)),
        .command(.next),
        .pause,
        .seek(84.5),
        .takeOver(NearbyState(title: "Juno", artist: "Sabrina Carpenter", album: "Short n' Sweet", isPlaying: true, position: 42, duration: 223)),
    ])
    func roundTrip(message: NearbyMessage) throws {
        let framed = try NearbyFraming.frame(message)
        let length = try #require(NearbyFraming.length(of: framed.prefix(4)))
        #expect(length == framed.count - 4)
        let decoded = try NearbyFraming.message(from: framed.dropFirst(4))
        #expect(decoded == message)
    }

    @Test("a header too long, or not four bytes, is refused")
    func badHeaders() {
        #expect(NearbyFraming.length(of: Data([0x7F, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(NearbyFraming.length(of: Data([0, 1])) == nil)
        #expect(NearbyFraming.length(of: Data([0, 0, 1, 0])) == 256)
    }

    @Test("the position moves on while playing, and stops at the song's end")
    func position() {
        let playing = NearbyState(title: "Juno", isPlaying: true, position: 100, duration: 110, sentAt: now)
        #expect(playing.position(at: now.addingTimeInterval(5)) == 105)
        #expect(playing.position(at: now.addingTimeInterval(60)) == 110)
        let paused = NearbyState(title: "Juno", isPlaying: false, position: 100, duration: 110, sentAt: now)
        #expect(paused.position(at: now.addingTimeInterval(5)) == 100)
    }

    @Test("the same song a moment later isn't worth sending again, a pause is")
    func sameness() {
        let first = NearbyState(title: "Juno", isPlaying: true, position: 10, sentAt: now)
        var later = first
        later.sentAt = now.addingTimeInterval(1)
        later.position = 11
        #expect(first.isSame(as: later))
        var paused = later
        paused.isPlaying = false
        #expect(!first.isSame(as: paused))
    }
}
