import Testing
import Foundation
import SwiftData
@testable import MotifCore

/// Which captures a play-back marks, and when it stops listening to the player.
@MainActor
@Suite("Playback following")
struct PlaybackFollowingTests {
    let store: MotifStore
    let service = FakePlaybackService()
    /// Captures are dated from the start of today, so `playBackToday`, which reads the real
    /// clock, sees them as today's even just after midnight.
    let today = Calendar.current.startOfDay(for: .now)

    init() throws {
        store = try MotifStore(inMemory: true)
    }

    @discardableResult
    func capture(
        _ songID: String,
        kind: CaptureKind = .radio,
        secondsIntoToday: TimeInterval = 1
    ) throws -> Capture {
        let capture = Capture(
            songID: songID,
            title: "T\(songID)",
            artistName: "A",
            kind: kind,
            capturedAt: today.addingTimeInterval(secondsIntoToday),
            deviceID: "this-device"
        )
        store.context.insert(capture)
        try store.context.save()
        return capture
    }

    /// It used to mark every unmarked capture of the song, whatever day or kind.
    @Test("only the captures that were queued are marked")
    func marksOnlyQueuedCaptures() async throws {
        let queued = try capture("1")
        let yesterday = try capture("1", secondsIntoToday: -60)
        let onDemand = try capture("1", kind: .onDemand, secondsIntoToday: 2)

        let controller = PlaybackController(store: store, service: service)
        await controller.playBackToday()
        service.reach("1")

        try await waitUntil { queued.playedBackAt != nil }
        #expect(yesterday.playedBackAt == nil)
        #expect(onDemand.playedBackAt == nil)
    }

    @Test("following stops once every queued song has been reached")
    func stopsWhenDone() async throws {
        let first = try capture("1", secondsIntoToday: 1)
        let second = try capture("2", secondsIntoToday: 2)

        let controller = PlaybackController(store: store, service: service)
        await controller.playBackToday()
        #expect(controller.isFollowingPlayback)
        service.reach("1")
        service.reach("2")

        try await waitUntil { !controller.isFollowingPlayback }
        #expect(first.playedBackAt != nil)
        #expect(second.playedBackAt != nil)
    }

    /// On iOS it followed the system player for good, so a later play of a queued song from
    /// somewhere else marked it.
    @Test("a song that wasn't queued ends the play-back")
    func foreignSongStops() async throws {
        let first = try capture("1", secondsIntoToday: 1)
        let second = try capture("2", secondsIntoToday: 2)

        let controller = PlaybackController(store: store, service: service)
        await controller.playBackToday()
        service.reach("1")
        try await waitUntil { first.playedBackAt != nil }
        service.reach("elsewhere")
        try await waitUntil { !controller.isFollowingPlayback }

        service.reach("2")
        try await Task.sleep(for: .milliseconds(50))
        #expect(second.playedBackAt == nil)
    }

    /// The player can report what it was playing before the queue took over.
    @Test("an unqueued first report doesn't end the play-back")
    func staleFirstReport() async throws {
        let first = try capture("1")

        let controller = PlaybackController(store: store, service: service)
        await controller.playBackToday()
        service.reach("before")
        service.reach("1")

        try await waitUntil { first.playedBackAt != nil }
    }

    @Test("playing a song from statistics marks only today's owed capture of it")
    func itemPlayMarksTodaysCapture() async throws {
        let owed = try capture("1")
        let yesterday = try capture("1", secondsIntoToday: -60)

        let controller = PlaybackController(store: store, service: service)
        await controller.play(PlaybackItem(songID: "1", title: "T1", artistName: "A"))
        service.reach("1")

        try await waitUntil { owed.playedBackAt != nil }
        #expect(yesterday.playedBackAt == nil)
    }

    /// Sync can merge a capture away before playback reaches it.
    @Test("a queued capture deleted before it's reached is skipped")
    func deletedBeforeReached() async throws {
        let gone = try capture("1", secondsIntoToday: 1)
        let kept = try capture("2", secondsIntoToday: 2)

        let controller = PlaybackController(store: store, service: service)
        await controller.playBackToday()
        store.context.delete(gone)
        try store.context.save()
        service.reach("1")
        service.reach("2")

        try await waitUntil { kept.playedBackAt != nil }
    }
}
