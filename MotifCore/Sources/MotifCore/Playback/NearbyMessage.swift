import Foundation

/// What's playing on one of your devices, as it tells your others nearby.
public struct NearbyState: Codable, Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    /// A cover anyone can load: Apple Music's. Covers from your own server aren't sent, since
    /// they'd carry its password.
    public var artworkURL: String?
    public var isPlaying: Bool
    /// How far into the song, at `sentAt`, where the device knows.
    public var position: TimeInterval?
    public var duration: TimeInterval?
    public var sentAt: Date
    public var canSkipBack: Bool
    public var canSkipForward: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artworkURL: String? = nil,
        isPlaying: Bool = false,
        position: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        sentAt: Date = .now,
        canSkipBack: Bool = true,
        canSkipForward: Bool = true
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.sentAt = sentAt
        self.canSkipBack = canSkipBack
        self.canSkipForward = canSkipForward
    }

    /// Whether there's a song to show at all.
    public var hasSong: Bool { title?.isEmpty == false }

    /// Where the song is now: moved on by the time since it was sent, while it plays, and no
    /// further than its end.
    public func position(at date: Date) -> TimeInterval? {
        guard let position else { return nil }
        let moved = isPlaying ? max(0, date.timeIntervalSince(sentAt)) : 0
        guard let duration else { return position + moved }
        return min(duration, position + moved)
    }

    /// The same song and state, ignoring the moment it was sent: whether it's worth sending again.
    public func isSame(as other: NearbyState) -> Bool {
        var mine = self
        var theirs = other
        mine.sentAt = .distantPast
        theirs.sentAt = .distantPast
        // A second either way is the same place in the song.
        if let a = mine.position, let b = theirs.position, abs(a - b) < 1.5, isPlaying == other.isPlaying {
            mine.position = nil
            theirs.position = nil
        }
        return mine == theirs
    }
}

/// What your devices say to each other.
public enum NearbyMessage: Codable, Sendable, Equatable {
    /// The first thing each side says: who it is.
    case hello(id: String, name: String, platform: String)
    case state(NearbyState)
    case command(TransportCommand)
    /// Asks the other to pause, as the song moves here.
    case pause
    /// Asks the other to move to a point in its song, from its player's scrubber here.
    case seek(TimeInterval)
    /// Hands the other this song to play from where it's got to, as music moves there. It
    /// answers with ``pause`` once it's playing, as a song brought across does.
    case takeOver(NearbyState)
}

extension TransportCommand: Codable {}

/// Messages on the wire: each as JSON behind its length, four bytes, most significant first.
public enum NearbyFraming {
    /// Longer than any message could honestly be: a connection saying otherwise is dropped.
    public static let largest = 256 * 1024

    public static func frame(_ message: NearbyMessage) throws -> Data {
        let body = try JSONEncoder().encode(message)
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    /// The length a header gives, or nil for one that isn't four bytes or is too long.
    public static func length(of header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        return length <= largest ? length : nil
    }

    public static func message(from body: Data) throws -> NearbyMessage {
        try JSONDecoder().decode(NearbyMessage.self, from: body)
    }
}
