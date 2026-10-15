import Foundation

/// The preview's own sound, band by band, kept small enough to store with a ``Groove`` and
/// replayed in time with the song: every hit, fill, held chord and quiet moment where the
/// preview had them, so a busy track looks busy and a ballad swells as it really does.
///
/// It's cut into chunks, a bar each when the song has a beat, so a chunk replays on the
/// song's own bars, and two seconds each when it doesn't. The chunks play forward, then back,
/// across the song, each one always forward inside, so a hit never plays backwards.
public nonisolated struct GrooveTexture: Codable, Equatable, Sendable {
    /// Frames a chunk: a thirty-second note each in a bar of four.
    public static let framesPerChunk = 32
    /// A chunk's length, for a song with no beat to keep.
    public static let freeChunk = 2.0

    /// Seconds a chunk lasts: a bar at the song's tempo, or ``freeChunk``.
    public var chunkSeconds: Double
    public var bandCount: Int
    /// Each frame's bands, 0 to 255, frame after frame.
    public var levels: Data

    public init(chunkSeconds: Double, bandCount: Int, levels: Data) {
        self.chunkSeconds = chunkSeconds
        self.bandCount = bandCount
        self.levels = levels
    }

    public var chunkCount: Int {
        bandCount > 0 ? levels.count / (bandCount * Self.framesPerChunk) : 0
    }

    /// Whether there's enough to replay: two chunks at least, so it can turn back.
    public var isPlayable: Bool {
        chunkCount >= 2 && chunkSeconds.isFinite && chunkSeconds > 0
    }

    /// The bands, 0 to 1, `position` seconds into the song.
    public func levels(at position: Double) -> [Float] {
        guard isPlayable else { return [] }
        let place = min(max(0, position.isFinite ? position : 0), 1_000_000) / chunkSeconds
        let chunk = Int(place)
        let frame = min(Self.framesPerChunk - 1, Int((place - Double(chunk)) * Double(Self.framesPerChunk)))
        let start = (Self.chunk(chunk, of: chunkCount) * Self.framesPerChunk + frame) * bandCount
        return levels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            (0..<bandCount).map { band in Float(bytes[start + band]) / 255 }
        }
    }

    /// The preview's chunk for the song's `chunk`: forward, then back, then forward again.
    static func chunk(_ chunk: Int, of count: Int) -> Int {
        guard count > 1 else { return 0 }
        let cycle = 2 * (count - 1)
        let place = chunk % cycle
        return place < count ? place : cycle - place
    }
}
