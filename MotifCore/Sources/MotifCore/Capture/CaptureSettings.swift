import Foundation

/// User-facing capture settings, shared with extensions through the App Group.
///
/// In `UserDefaults` so widgets and intents can read them without opening the model container.
public struct CaptureSettings: Sendable {
    public static let playlistNameKey = "playlistName"
    public static let playlistIDKey = "playlistID"
    public static let dedupeWindowKey = "dedupeWindowSeconds"
    public static let autoAddKey = "autoAddToPlaylist"
    public static let forceCaptureKey = "forceCapture"
    public static let autoPlayBackKey = "autoPlayBack"
    public static let capturesOnDemandKey = "capturesOnDemand"
    public static let minimumListenKey = "minimumListenSeconds"
    public static let importsRecentlyPlayedKey = "importsRecentlyPlayed"
    public static let forgottenSongsKey = "forgottenSongs"
    public static let scrobblesToLastFMKey = "scrobblesToLastFM"
    public static let scrobblesImportedKey = "scrobblesImported"
    public static let menuBarLabelStyleKey = "menuBarLabelStyle"
    public static let menuBarLabelFormatKey = "menuBarLabelFormat"
    public static let animatesMenuBarKey = "animatesMenuBar"
    public static let excludedStationsKey = "excludedStations"
    public static let showsUpNextInWidgetKey = "showsUpNextInWidget"
    public static let recentlyPlayedAnchorKey = "recentlyPlayedAnchor"
    public static let artworkMissesKey = "artworkMisses"
    public static let lastFMHistoryKey = "lastFMHistoryImport"

    public static let defaultPlaylistName = "Heard on Radio"

    /// The suite name, not the `UserDefaults`, which isn't `Sendable`.
    /// `UserDefaults(suiteName:)` returns a shared instance, so resolving it each time is cheap.
    private let suiteName: String?

    /// Falls back to standard defaults without an App Group (previews, tests).
    public init(suiteName: String? = AppGroup.identifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// The store this type uses. Pass it to `@AppStorage`, which otherwise writes to
    /// `UserDefaults.standard` where nothing here will read it.
    public static var sharedDefaults: UserDefaults {
        AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// A blank name reads as unset. A whitespace-only name once broke playback, since Music
    /// was asked for `playlist " "`.
    public var playlistName: String {
        get {
            let stored = defaults.string(forKey: Self.playlistNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored! : Self.defaultPlaylistName
        }
        nonmutating set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? Self.defaultPlaylistName : trimmed,
                         forKey: Self.playlistNameKey)
        }
    }

    /// The playlist we created. Nil until then. Stored by ID so renaming the playlist
    /// doesn't make us create another.
    public var playlistID: String? {
        get { defaults.string(forKey: Self.playlistIDKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.playlistIDKey) }
    }

    public var dedupePolicy: DedupePolicy {
        let stored = defaults.double(forKey: Self.dedupeWindowKey)
        return DedupePolicy(window: stored > 0 ? stored : DedupePolicy.default.window)
    }

    public func setDedupeWindow(seconds: TimeInterval) {
        defaults.set(seconds, forKey: Self.dedupeWindowKey)
    }

    /// Whether to play the day's radio songs again once a station stops, so Apple counts
    /// them as plays. Off by default: it starts music on its own, so the user has to opt in.
    /// The songs play audibly, and apps that read Apple's history will list them twice.
    public var autoPlayBack: Bool {
        get { defaults.object(forKey: Self.autoPlayBackKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.autoPlayBackKey) }
    }

    /// How long a song must play before it counts. Defaults to 30 seconds, Last.fm's
    /// threshold. Zero captures as soon as a song is seen.
    public var minimumListenSeconds: TimeInterval {
        get {
            guard defaults.object(forKey: Self.minimumListenKey) != nil else { return 30 }
            return max(0, defaults.double(forKey: Self.minimumListenKey))
        }
        nonmutating set { defaults.set(max(0, newValue), forKey: Self.minimumListenKey) }
    }

    /// Whether to keep on-demand plays as well as radio. On by default.
    public var capturesOnDemand: Bool {
        get { defaults.object(forKey: Self.capturesOnDemandKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.capturesOnDemandKey) }
    }

    /// Whether to import listening that happened while Motif wasn't running. On by default;
    /// iOS suspends Motif within about thirty seconds in the background, so this is most of
    /// the iPhone's history.
    public var importsRecentlyPlayed: Bool {
        get { defaults.object(forKey: Self.importsRecentlyPlayedKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.importsRecentlyPlayedKey) }
    }

    /// What the macOS menu bar shows. Defaults to the note symbol.
    public var menuBarLabelStyle: MenuBarLabelStyle {
        get { MenuBarLabelStyle(stored: defaults.string(forKey: Self.menuBarLabelStyleKey)) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.menuBarLabelStyleKey) }
    }

    /// Whether the status item cross-fades when the song changes. On by default; Reduce
    /// Motion turns it off regardless.
    public var animatesMenuBar: Bool {
        get { defaults.object(forKey: Self.animatesMenuBarKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.animatesMenuBarKey) }
    }

    /// The user's own format, used only by ``MenuBarLabelStyle/custom``.
    ///
    /// Empty is allowed (cover and no text), so blank isn't replaced with the default.
    public var menuBarLabelFormat: String {
        get { defaults.string(forKey: Self.menuBarLabelFormatKey) ?? MenuBarLabelFormat.default }
        nonmutating set { defaults.set(newValue, forKey: Self.menuBarLabelFormatKey) }
    }

    /// Whether the Today widget shows what "Play back" will play next. On by default.
    public var showsUpNextInWidget: Bool {
        get { defaults.object(forKey: Self.showsUpNextInWidgetKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.showsUpNextInWidgetKey) }
    }

    public var autoAddToPlaylist: Bool {
        get { defaults.object(forKey: Self.autoAddKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.autoAddKey) }
    }

    /// Captures even when the radio heuristic says no.
    public var forceCapture: Bool {
        get { defaults.bool(forKey: Self.forceCaptureKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.forceCaptureKey) }
    }

    public var excludedStations: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.excludedStationsKey) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Self.excludedStationsKey) }
    }

    /// Apple's recently played list as it was at the last import, as `HistoryImport.key`
    /// values, newest first.
    public var recentlyPlayedAnchor: [String] {
        get { defaults.stringArray(forKey: Self.recentlyPlayedAnchorKey) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.recentlyPlayedAnchorKey) }
    }

    /// Songs the user has removed, by ``HistoryImport/key(title:artistName:)``. They're
    /// still in Apple's recently-played list, so without this the next import brings them back.
    public var forgottenSongs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.forgottenSongsKey) ?? []) }
        nonmutating set { defaults.set(Array(newValue).sorted(), forKey: Self.forgottenSongsKey) }
    }

    /// Whether to send listening to Last.fm. On by default, but nothing is sent until an
    /// account is connected.
    public var scrobblesToLastFM: Bool {
        get { defaults.object(forKey: Self.scrobblesToLastFMKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.scrobblesToLastFMKey) }
    }

    /// Whether to scrobble imported songs. On by default: on the iPhone, recovered songs are
    /// most of the history, so leaving them out meant most listening never reached Last.fm.
    /// The trade-off is the time: imports are dated when found, so a scrobble can be hours
    /// late (see ``HistoryImport``).
    public var scrobblesImported: Bool {
        get { defaults.object(forKey: Self.scrobblesImportedKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.scrobblesImportedKey) }
    }

    /// Songs the catalog had no cover for, by song ID, with when to ask again.
    ///
    /// Kept so the artwork backfill moves on past them rather than asking about the same
    /// songs on every pass. See ``CaptureCoordinator``. Stored as seconds since 1970, which
    /// a property list holds without fuss.
    public var artworkMisses: [String: Date] {
        get {
            let stored = defaults.dictionary(forKey: Self.artworkMissesKey) as? [String: Double] ?? [:]
            return stored.mapValues { Date(timeIntervalSince1970: $0) }
        }
        nonmutating set {
            defaults.set(newValue.mapValues(\.timeIntervalSince1970), forKey: Self.artworkMissesKey)
        }
    }

    /// How far importing the Last.fm history has got, for whichever account it was. Kept on
    /// this device: the rows sync, and another device's import skips what they cover.
    /// Stored as JSON. See ``LastFMHistory/Progress``.
    public var lastFMHistoryProgress: LastFMHistory.Progress? {
        get {
            defaults.data(forKey: Self.lastFMHistoryKey)
                .flatMap { try? JSONDecoder().decode(LastFMHistory.Progress.self, from: $0) }
        }
        nonmutating set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.lastFMHistoryKey)
        }
    }

    /// The progress for this account, or a fresh start if it's never been imported or the
    /// progress is another account's.
    public func lastFMHistory(for username: String) -> LastFMHistory.Progress {
        guard let stored = lastFMHistoryProgress, stored.username == username else {
            return LastFMHistory.Progress(username: username)
        }
        return stored
    }

    public func hasForgotten(title: String, artistName: String) -> Bool {
        forgottenSongs.contains(HistoryImport.key(title: title, artistName: artistName))
    }

    public func isExcluded(station: String?) -> Bool {
        guard let station else { return false }
        return excludedStations.contains(station)
    }
}
