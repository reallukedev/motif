import Testing
import Foundation
@testable import MotifCore

/// The playlist cap. Apple Music can't remove a track once it's in, so the only thing keeping
/// "Heard on Radio" a usable size is refusing to write past the limit.
@Suite("Playlist size limit")
struct PlaylistSizeLimitTests {

    @Test("an empty playlist has room for the whole limit")
    func emptyPlaylist() {
        #expect(PlaylistSizeLimit.room(existing: 0, limit: 250) == 250)
    }

    @Test("room is what's left under the limit")
    func partiallyFull() {
        #expect(PlaylistSizeLimit.room(existing: 249, limit: 250) == 1)
    }

    @Test("a full playlist has no room")
    func full() {
        #expect(PlaylistSizeLimit.room(existing: 250, limit: 250) == 0)
    }

    /// Someone can add to the playlist by hand, so it can already be past the limit.
    @Test("a playlist over the limit has no room rather than negative room")
    func overFull() {
        #expect(PlaylistSizeLimit.room(existing: 400, limit: 250) == 0)
    }

    @Test("no limit means unlimited room")
    func limitOff() {
        #expect(PlaylistSizeLimit.room(existing: 10_000, limit: nil) == .max)
    }

    @Test("the default is 250 and sits inside what Settings offers")
    func defaultLimit() {
        #expect(PlaylistSizeLimit.default == 250)
        #expect(PlaylistSizeLimit.allowed.contains(PlaylistSizeLimit.default))
        #expect(PlaylistSizeLimit.default.isMultiple(of: PlaylistSizeLimit.step))
    }

    /// A value from an older build, or one written by hand, mustn't switch the cap off.
    @Test("values outside the range are clamped", arguments: [
        (0, 50), (-100, 50), (49, 50), (250, 250), (2_000, 2_000), (99_999, 2_000),
    ])
    func clamping(value: Int, expected: Int) {
        #expect(PlaylistSizeLimit.clamped(value) == expected)
    }
}

/// The request and response for counting a playlist.
@Suite("Playlist track counting")
struct PlaylistTrackCountTests {

    @Test("counting targets the playlist's tracks collection with paging")
    func tracksRequest() throws {
        let request = AppleMusicPlaylistRequestBuilder.playlistTracks(
            playlistID: "p.abc123",
            limit: 100,
            offset: 200
        )
        let url = try #require(request.url?.absoluteString)

        #expect(request.httpMethod == "GET")
        #expect(url.hasPrefix("https://api.music.apple.com/v1/me/library/playlists/p.abc123/tracks?"))
        #expect(url.contains("limit=100"))
        #expect(url.contains("offset=200"))
    }

    /// Apple states a total for some library relationships, which saves paging through.
    @Test("a stated total is used as the count")
    func readsStatedTotal() throws {
        let data = try #require(#"{"data":[{"id":"i.1"}],"meta":{"total":317}}"#.data(using: .utf8))
        let page = AppleMusicPlaylistRequestBuilder.parseTracksPage(from: data)

        #expect(page.total == 317)
        #expect(page.count == 1)
    }

    @Test("a page without a total reports what it holds and whether more follow")
    func readsPageWithoutTotal() throws {
        let body = #"{"data":[{"id":"i.1"},{"id":"i.2"}],"next":"/v1/me/library/playlists/p.1/tracks?offset=2"}"#
        let data = try #require(body.data(using: .utf8))
        let page = AppleMusicPlaylistRequestBuilder.parseTracksPage(from: data)

        #expect(page.total == nil)
        #expect(page.count == 2)
        #expect(page.hasMore)
    }

    @Test("the last page says there are no more")
    func readsLastPage() throws {
        let data = try #require(#"{"data":[{"id":"i.1"}]}"#.data(using: .utf8))
        let page = AppleMusicPlaylistRequestBuilder.parseTracksPage(from: data)

        #expect(!page.hasMore)
        #expect(page.count == 1)
    }

    /// An empty playlist answers 404, and a body that isn't what we expect shouldn't throw.
    @Test("an unreadable body counts as nothing")
    func readsGarbage() throws {
        let data = try #require("not json".data(using: .utf8))
        let page = AppleMusicPlaylistRequestBuilder.parseTracksPage(from: data)

        #expect(page.count == 0)
        #expect(page.total == nil)
        #expect(!page.hasMore)
    }
}
