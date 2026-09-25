import Foundation

/// A song from your own music rather than Apple Music: a file on this iPhone, or a song on a
/// music server you've connected, downloaded or not.
public struct LocalTrack: Codable, Sendable, Hashable, Identifiable {
    /// Where the song lives.
    public enum Origin: Codable, Sendable, Hashable {
        /// A file in Motif's Music folder, by its path inside it.
        case file(path: String)
        /// A song on a music server, by the server's id for it.
        case server(serverID: String, songID: String)
    }

    /// Where the cover comes from.
    public enum Artwork: Codable, Sendable, Hashable {
        /// A picture Motif saved, by its name in the artwork folder.
        case file(name: String)
        /// The server's cover, by its id for it.
        case server(serverID: String, coverID: String)
    }

    public let id: String
    public var origin: Origin
    public var title: String
    public var artist: String
    /// The album's artist, where it differs: "Various Artists" on a compilation.
    public var albumArtist: String?
    public var album: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: Int?
    public var genre: String?
    public var duration: TimeInterval?
    public var format: AudioFormat?
    public var artwork: Artwork?
    /// When it came into the library, for Recently Added.
    public var addedAt: Date

    public init(
        origin: Origin,
        title: String,
        artist: String,
        albumArtist: String? = nil,
        album: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        duration: TimeInterval? = nil,
        format: AudioFormat? = nil,
        artwork: Artwork? = nil,
        addedAt: Date = .now
    ) {
        self.id = Self.id(for: origin)
        self.origin = origin
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.duration = duration
        self.format = format
        self.artwork = artwork
        self.addedAt = addedAt
    }

    public static func id(for origin: Origin) -> String {
        switch origin {
        case .file(let path): "file:\(path)"
        case .server(let server, let song): "server:\(server):\(song)"
        }
    }

    /// The key Motif's history groups plays by, so a local song and the same song heard in
    /// Apple Music count together.
    public var identity: String { HistoryImport.key(title: title, artistName: artist) }

    /// Who the album is by: its album artist, or the song's.
    public var albumArtistName: String { albumArtist.flatMap { $0.isEmpty ? nil : $0 } ?? artist }

    /// Groups a song with the rest of its album, however the tags are cased.
    public var albumKey: String {
        StatsCalculator.folded(albumArtistName) + "\u{1F}" + StatsCalculator.folded(album ?? title)
    }

    public var artistKey: String { StatsCalculator.folded(albumArtistName) }

    public var isFromServer: Bool {
        if case .server = origin { return true }
        return false
    }

    public var serverID: String? {
        if case .server(let server, _) = origin { return server }
        return nil
    }

    /// For a mix: the song as one of Motif's, with its id standing in for a catalog id.
    public func mixSong(plays: Int = 0, lastHeard: Date = .distantPast) -> MixSong {
        MixSong(
            songIdentity: identity,
            songID: id,
            title: title,
            artistName: artist,
            albumTitle: album,
            artworkURL: nil,
            plays: plays,
            lastHeard: lastHeard,
            genre: genre
        )
    }
}

/// How a song is encoded: "FLAC · 24-bit/96 kHz", or "MP3 · 320 kbps".
public struct AudioFormat: Codable, Sendable, Hashable {
    /// "FLAC", "ALAC", "MP3", "AAC", "WAV", "AIFF".
    public var codec: String
    public var sampleRate: Int?
    public var bitDepth: Int?
    /// In kilobits a second, for lossy files.
    public var bitRate: Int?

    public init(codec: String, sampleRate: Int? = nil, bitDepth: Int? = nil, bitRate: Int? = nil) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitRate = bitRate
    }

    public var isLossless: Bool {
        ["FLAC", "ALAC", "WAV", "AIFF"].contains(codec.uppercased())
    }

    /// Past CD quality: more than 16 bits, or faster than 48 kHz.
    public var isHiRes: Bool {
        isLossless && ((bitDepth ?? 16) > 16 || (sampleRate ?? 44_100) > 48_000)
    }

    /// "24-bit/96 kHz", "16-bit/44.1 kHz", or "320 kbps".
    public var detail: String? {
        if isLossless, let bitDepth, let sampleRate {
            let khz = Double(sampleRate) / 1_000
            let rate = khz.rounded() == khz ? String(Int(khz)) : String(format: "%.1f", khz)
            return "\(bitDepth)-bit/\(rate) kHz"
        }
        if let bitRate, bitRate > 0 { return "\(bitRate) kbps" }
        return nil
    }

    /// The codec a file's extension, or a server's suffix, names.
    public static func codec(forExtension suffix: String) -> String {
        switch suffix.lowercased() {
        case "flac": "FLAC"
        case "mp3": "MP3"
        case "m4a", "mp4", "aac": "AAC"
        case "alac": "ALAC"
        case "wav": "WAV"
        case "aif", "aiff", "aifc": "AIFF"
        case "ogg", "oga": "Ogg"
        case "opus": "Opus"
        default: suffix.uppercased()
        }
    }

    /// The file extensions Motif can play from the Music folder.
    public static let playableExtensions: Set<String> = ["flac", "mp3", "m4a", "mp4", "aac", "alac", "wav", "aif", "aiff", "aifc"]
}
