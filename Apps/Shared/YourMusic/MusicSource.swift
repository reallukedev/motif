import SwiftUI
import MotifCore

/// Where Play's music comes from: Apple Music's catalog, or music you own, as files on this
/// iPhone and on your own music servers.
nonisolated enum MusicSource: String, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case yourMusic

    var id: String { rawValue }

    static let storageKey = "musicSource"

    static var current: MusicSource {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MusicSource.init(rawValue:)) ?? .appleMusic
    }

    var title: LocalizedStringKey {
        switch self {
        case .appleMusic: "Apple Music"
        case .yourMusic: "Your Music"
        }
    }

    var symbol: String {
        switch self {
        case .appleMusic: "music.note"
        case .yourMusic: "externaldrive.fill"
        }
    }

    /// The title as a plain string, for a row's value.
    var name: String {
        switch self {
        case .appleMusic: String(localized: "Apple Music")
        case .yourMusic: String(localized: "Your Music")
        }
    }
}

/// How server songs stream when they aren't downloaded.
/// Automatic Downloads: songs from your servers come down to this iPhone as you play or add
/// them, so they play at once, and with no connection, from then on.
enum AutomaticDownloads {
    static let storageKey = "yourMusicAutomaticDownloads"

    /// On unless turned off.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

enum StreamQuality: String, CaseIterable, Identifiable {
    /// The file as it is on the server: FLAC stays FLAC.
    case original
    /// Re-encoded by the server, for a slower connection.
    case high
    case dataSaver

    var id: String { rawValue }

    static let storageKey = "yourMusicStreamQuality"

    static var current: StreamQuality {
        UserDefaults.standard.string(forKey: storageKey).flatMap(StreamQuality.init(rawValue:)) ?? .original
    }

    var title: LocalizedStringKey {
        switch self {
        case .original: "Original"
        case .high: "High (320 kbps)"
        case .dataSaver: "Data Saver (128 kbps)"
        }
    }

    /// For the server's stream: nil keeps the original.
    var maxBitRate: Int? {
        switch self {
        case .original: nil
        case .high: 320
        case .dataSaver: 128
        }
    }
}

/// Whether Your Music suggests songs you don't have.
enum SuggestionMode: String, CaseIterable, Identifiable {
    /// Suggestions found in your music, on your servers or in Lidarr, including ones Lidarr is still getting.
    case everything
    /// Only suggestions you can play or get: in your music, on your server or in Lidarr.
    case onlyYours
    /// No suggestions: your library, and nothing else.
    case off

    var id: String { rawValue }

    static let storageKey = "yourMusicSuggestions"

    static var current: SuggestionMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SuggestionMode.init(rawValue:)) ?? .everything
    }

    var title: LocalizedStringKey {
        switch self {
        case .everything: "Everything"
        case .onlyYours: "Only Music I Have"
        case .off: "Off"
        }
    }
}

/// Whether a song you've been suggested can play, in Your Music.
/// What's known of one song from outside your music, observed on its own so its rows redraw
/// only when it's answered.
@MainActor
@Observable
final class SongAnswer {
    var state: SongAvailability?
    /// The look it's from. See ``YourMusic/availabilityGeneration``.
    @ObservationIgnored var generation = -1
}

enum SongAvailability: Equatable {
    /// Still being looked for.
    case checking
    /// In your music: a file, a download, or a song on your server.
    case playable(LocalTrack)
    /// Lidarr has its file; your server just hasn't synced it yet.
    case inLidarr(album: String)
    /// Lidarr follows its album and is looking for it.
    case comingFromLidarr
    case unavailable

    var track: LocalTrack? {
        if case .playable(let track) = self { return track }
        return nil
    }

    /// Shown under Only Music I Have: everything but what can't be had.
    var isYours: Bool {
        switch self {
        case .checking, .playable, .inLidarr: true
        case .comingFromLidarr, .unavailable: false
        }
    }

    /// Why a song that can't play doesn't, for a moment's message.
    var message: String? {
        switch self {
        case .checking: String(localized: "Still Looking for This Song")
        case .playable: nil
        case .inLidarr: String(localized: "In Lidarr: Download It to Play")
        case .comingFromLidarr: String(localized: "Lidarr Is Getting This Song")
        case .unavailable: String(localized: "This Song Isn't Available")
        }
    }
}
