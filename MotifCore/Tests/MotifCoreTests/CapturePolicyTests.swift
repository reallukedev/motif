import Testing
import Foundation
@testable import MotifCore

@Suite("Dedupe window")
struct DedupePolicyTests {
    let policy = DedupePolicy(window: 600)
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("a song never seen before is always captured")
    func firstSighting() {
        #expect(policy.shouldCapture(lastSeen: nil, now: now))
    }

    @Test("a repeat inside the window is the same play", arguments: [0.0, 1.0, 300.0, 599.0])
    func insideWindow(elapsed: TimeInterval) {
        #expect(!policy.shouldCapture(lastSeen: now.addingTimeInterval(-elapsed), now: now))
    }

    /// The boundary is inclusive: exactly one window later counts as a new play.
    @Test("a repeat at or after the window is a new play", arguments: [600.0, 601.0, 3_600.0])
    func outsideWindow(elapsed: TimeInterval) {
        #expect(policy.shouldCapture(lastSeen: now.addingTimeInterval(-elapsed), now: now))
    }
}

@Suite("Session segmentation")
struct SessionPolicyTests {
    let policy = SessionPolicy(silenceTimeout: 900)
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("with no session open, anything starts a new one")
    func noOpenSession() {
        let decision = policy.decide(
            openSessionStation: "Apple Music 1",
            openSessionLastActivity: nil,
            observedStation: "Apple Music 1",
            now: now
        )
        #expect(decision == .startNew)
    }

    @Test("continuing on the same station stays in the session")
    func sameStation() {
        let decision = policy.decide(
            openSessionStation: "Apple Music 1",
            openSessionLastActivity: now.addingTimeInterval(-60),
            observedStation: "Apple Music 1",
            now: now
        )
        #expect(decision == .current)
    }

    /// A session is contiguous listening to *one* station, so a change ends it even with
    /// no gap at all.
    @Test("changing station starts a new session even with no silence")
    func stationChange() {
        let decision = policy.decide(
            openSessionStation: "Apple Music 1",
            openSessionLastActivity: now,
            observedStation: "Apple Música Uno",
            now: now
        )
        #expect(decision == .startNew)
    }

    @Test("silence past the timeout starts a new session")
    func silenceTimeout() {
        let decision = policy.decide(
            openSessionStation: "Apple Music 1",
            openSessionLastActivity: now.addingTimeInterval(-901),
            observedStation: "Apple Music 1",
            now: now
        )
        #expect(decision == .startNew)
    }

    /// macOS often cannot name the station. Fragmenting the session every time would be
    /// worse than assuming it has not changed.
    @Test("an unknown incoming station does not fragment the session")
    func unknownStation() {
        let decision = policy.decide(
            openSessionStation: "Apple Music 1",
            openSessionLastActivity: now.addingTimeInterval(-60),
            observedStation: nil,
            now: now
        )
        #expect(decision == .current)
    }
}

@Suite("Scrobble threshold")
struct ScrobblePolicyTests {
    let policy = ScrobblePolicy()

    /// Last.fm's floor. ListenBrainz has none, so the stricter rule satisfies both.
    @Test("tracks of 30 seconds or less never scrobble", arguments: [1.0, 29.0, 30.0])
    func tooShort(duration: TimeInterval) {
        #expect(!policy.shouldScrobble(duration: duration, playedFor: duration))
    }

    @Test("a short track scrobbles at half its length")
    func halfway() {
        #expect(policy.shouldScrobble(duration: 200, playedFor: 100))
        #expect(!policy.shouldScrobble(duration: 200, playedFor: 99))
    }

    /// For anything over eight minutes, four minutes is the earlier of the two thresholds.
    @Test("a long track scrobbles at four minutes, not at half")
    func fourMinuteCap() {
        #expect(policy.shouldScrobble(duration: 1_200, playedFor: 240))
        #expect(!policy.shouldScrobble(duration: 1_200, playedFor: 239))
    }
}
