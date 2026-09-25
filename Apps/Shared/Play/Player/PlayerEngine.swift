import Foundation

/// What actually makes sound. ``PlayerModel`` is the same for both; the engine is Apple Music
/// through MusicKit, or a pretend one for sample data, which mustn't reach Apple Music.
@MainActor
protocol PlayerEngine: AnyObject {
    /// Called whenever anything below changes, except the playback time, which moves all the
    /// time and is read when needed.
    var onChange: (() -> Void)? { get set }

    var status: PlayerStatus { get }
    var current: PlayerTrack? { get }
    /// After the current song, in play order. Empty on a station, which has no queue.
    var upNext: [PlayerTrack] { get }
    var playbackTime: TimeInterval { get }
    var isShuffled: Bool { get }
    var repeatMode: PlayerRepeat { get }

    /// Replaces the queue and starts playing. Throws ``PlayerProblem``.
    func play(_ request: PlayRequest, context: PlayContext, shuffled: Bool) async throws
    /// Adds after the current song, or at the end of the queue.
    func enqueue(_ request: PlayRequest, next: Bool) async throws

    func pause()
    func resume() async throws
    func skipToNext() async throws
    func skipToPrevious() async throws
    func seek(to time: TimeInterval)
    func setShuffled(_ isShuffled: Bool)
    func setRepeat(_ mode: PlayerRepeat)
    /// Plays a song from ``upNext`` now, dropping the ones before it.
    func jump(toUpNext index: Int) async throws
    /// Offsets into ``upNext``.
    func removeUpNext(at offsets: IndexSet)
    func moveUpNext(from offsets: IndexSet, to destination: Int)

    /// Whether it finds history songs by title and artist, rather than needing Apple Music ids:
    /// the pretend player, and the one for your own music.
    var playsByName: Bool { get }
    /// Takes over the audio session and the remote controls, as the player in use.
    func activate()
    /// Stops and hands them back, for another player to take over.
    func deactivate()
}

extension PlayerEngine {
    var playsByName: Bool { false }
    func activate() {}
    func deactivate() {}
}
