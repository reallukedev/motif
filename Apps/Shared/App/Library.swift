import SwiftUI
import SwiftData
import Observation
import MotifCore

/// The listening history as plain values, rebuilt whenever the store changes.
///
/// Screens read `history` and compute what they need from it; the `revision` changes on
/// every rebuild so they know when to recompute.
@MainActor
@Observable
final class Library {
    private(set) var history = ListeningHistory([])
    private(set) var sessions: [SessionStat] = []
    private(set) var revision = 0
    /// False until the first rebuild, so screens can tell "loading" from "empty".
    private(set) var isLoaded = false

    func update(captures: [Capture], sessions: [Session]) {
        history = ListeningHistory(captures.map(\.stat))
        self.sessions = sessions.map {
            SessionStat(
                startedAt: $0.startedAt,
                finishedAt: $0.endedAt ?? $0.lastActivityAt,
                stationName: $0.station?.name
            )
        }
        isLoaded = true
        revision += 1
    }

    /// Forces a recompute without new data, e.g. when the day changes and "this week" moves.
    func invalidate() {
        revision += 1
    }
}

extension Capture {
    var stat: CaptureStat {
        CaptureStat(
            songKey: songKey,
            songID: songID,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            capturedAt: capturedAt,
            stationName: session?.station?.name,
            playedBackAt: playedBackAt,
            kind: kind
        )
    }
}

/// Keeps `Library` in step with the store. Put it once at the root of each scene, inside
/// the `modelContainer`.
struct LibraryObserver: ViewModifier {
    let library: Library
    @Query(sort: \Capture.capturedAt) private var captures: [Capture]
    @Query(sort: \Session.startedAt) private var sessions: [Session]

    func body(content: Content) -> some View {
        content
            .task(id: signature) {
                library.update(captures: captures, sessions: sessions)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                library.invalidate()
            }
    }

    /// Changes whenever something the statistics show could have changed: a new row, a
    /// cover arriving, a scrobble going out, a song played back.
    private var signature: [Int] {
        var artwork = 0
        var scrobbled = 0
        var playedBack = 0
        for capture in captures {
            if capture.artworkURL != nil { artwork += 1 }
            if capture.scrobbledAt != nil { scrobbled += 1 }
            if capture.playedBackAt != nil { playedBack += 1 }
        }
        return [
            captures.count,
            Int(captures.last?.capturedAt.timeIntervalSinceReferenceDate ?? 0),
            artwork, scrobbled, playedBack,
            sessions.count,
            Int(sessions.last?.lastActivityAt.timeIntervalSinceReferenceDate ?? 0),
        ]
    }
}

extension View {
    func observesLibrary(_ library: Library) -> some View {
        modifier(LibraryObserver(library: library))
    }
}
