#if os(iOS)
import Testing
import Foundation
import MusicKit
import MotifCore
@testable import MotifMusic

/// The iOS capture path: turning `SystemMusicPlayer`'s current queue entry into an
/// observation. Songs are decoded from Apple Music API JSON, so these run in the Simulator
/// with no Apple Music account.
@Suite("iOS system player capture")
@MainActor
struct SystemMusicPlayerSourceTests {

    @Test("a resolved song becomes an observation of that song")
    func resolvedSong() throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: 28.1)
        )
        #expect(observation.title == "Lost Boys")
        #expect(observation.artistName == "Phoebe Bridgers")
        #expect(observation.albumTitle == "Punisher")
        #expect(observation.catalogSongID == "1440833098")
        #expect(observation.duration == 148.734)
        #expect(observation.playbackState == .playing)
        #expect(observation.playerPosition == 28.1)
        #expect(observation.stationName == nil)
        #expect(observation.isCapturable)
    }

    /// iOS never runs a catalog search. If the ID went missing, the track couldn't be
    /// written to the playlist or played back.
    @Test("a resolved song carries its catalog ID, so no search is needed")
    func noCatalogSearch() throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: 0)
        )
        #expect(observation.catalogQuery == nil)
    }

    @Test("an empty queue has nothing to observe")
    func emptyQueue() {
        #expect(SystemMusicPlayerSource.observation(from: nil, status: .playing, playbackTime: 0) == nil)
    }

    /// Radio detection on iOS reads the entry id back out of the raw fields.
    @Test("the entry id and title are kept in the raw fields")
    func rawFields() throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: 0)
        )
        #expect(observation.rawFields["entry.id"] == entry.id)
        #expect(observation.rawFields["entry.title"] == "Lost Boys")
        #expect(observation.rawFields["entry.subtitle"] == "Phoebe Bridgers")
    }

    /// The Music app pauses the queue without changing the entry. The observation still
    /// arrives, but it must not become a capture.
    @Test("a paused song is observed but not captured")
    func pausedSong() throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .paused, playbackTime: 12)
        )
        #expect(observation.playbackState == .paused)
        #expect(observation.isCapturable == false)
    }

    @Test("an on-demand song with a real duration is not radio")
    func onDemandIsNotRadio() throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: 28.1)
        )
        #expect(observation.radioVerdict() == .onDemand)
    }

    @Test("a position the player can't report is left unknown", arguments: [TimeInterval.nan, .infinity])
    func nonFinitePosition(playbackTime: TimeInterval) throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song())
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: playbackTime)
        )
        #expect(observation.playerPosition == nil)
    }

    /// A stored URL that can't load is never replaced, because the backfill only fills rows
    /// with no artwork. See ``ArtworkURL``.
    @Test("artwork is kept only when it can be loaded", arguments: zip(
        [
            "https://is1-ssl.mzstatic.com/image/thumb/Music/{w}x{h}bb.jpg",
            "musicKit://artwork/transient/{w}x{h}",
            nil,
        ],
        [
            "https://is1-ssl.mzstatic.com/image/thumb/Music/300x300bb.jpg",
            nil,
            nil,
        ]
    ))
    func artwork(template: String?, expected: String?) throws {
        let entry = MusicPlayer.Queue.Entry(try Self.song(artwork: template))
        let observation = try #require(
            SystemMusicPlayerSource.observation(from: entry, status: .playing, playbackTime: 0)
        )
        #expect(observation.artworkURL == expected)
    }

    @Test("playing and paused carry over", arguments: zip(
        [MusicPlayer.PlaybackStatus.playing, .paused],
        [PlaybackState.playing, .paused]
    ))
    func playbackState(status: MusicPlayer.PlaybackStatus, expected: PlaybackState) {
        #expect(SystemMusicPlayerSource.playbackState(status) == expected)
    }

    /// An interruption is a phone call or another app taking audio. Nothing is audible.
    @Test("stopped and interrupted both count as stopped", arguments: [
        MusicPlayer.PlaybackStatus.stopped, .interrupted,
    ])
    func stoppedStates(status: MusicPlayer.PlaybackStatus) {
        #expect(SystemMusicPlayerSource.playbackState(status) == .stopped)
    }

    /// "Lost Boys" by Phoebe Bridgers, shaped like an Apple Music API song resource.
    static func song(
        artwork: String? = "https://is1-ssl.mzstatic.com/image/thumb/Music/{w}x{h}bb.jpg"
    ) throws -> Song {
        let artworkJSON = artwork.map { #","artwork":{"url":"\#($0)","width":3000,"height":3000}"# } ?? ""
        let json = #"""
        {"id":"1440833098","type":"songs","attributes":{"name":"Lost Boys",\#
        "artistName":"Phoebe Bridgers","albumName":"Punisher","durationInMillis":148734\#(artworkJSON)}}
        """#
        return try JSONDecoder().decode(Song.self, from: Data(json.utf8))
    }
}
#endif
