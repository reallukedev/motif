import Foundation

/// The ceiling on how many songs Motif puts in the radio playlist.
///
/// A station left running adds a song every few minutes, and the Apple Music API can't remove
/// a track once it's in (see ``AppleMusicPlaylistRequestBuilder``). So the limit is enforced
/// on the way in: once the playlist is full, new radio songs are still kept in the history,
/// they just aren't written. Raising the limit, or trimming the playlist in Apple Music, lets
/// the waiting songs through on the next pass.
public enum PlaylistSizeLimit {
    public static let `default` = 250
    /// What Settings offers. The floor keeps the playlist worth having; the ceiling is well
    /// past the point where anyone would scroll it.
    public static let allowed = 50...2000
    /// The stepper's increment, which every offered value is a multiple of.
    public static let step = 50

    public static func clamped(_ value: Int) -> Int {
        min(allowed.upperBound, max(allowed.lowerBound, value))
    }

    /// How many more songs may be written before the playlist is full.
    ///
    /// - Parameters:
    ///   - existing: songs in the playlist now, from whatever source. A playlist someone has
    ///     added to by hand can already be over the limit, which leaves no room rather than
    ///     a negative one.
    ///   - limit: the ceiling, or nil when the user has turned the limit off.
    public static func room(existing: Int, limit: Int?) -> Int {
        guard let limit else { return .max }
        return max(0, limit - max(0, existing))
    }
}
