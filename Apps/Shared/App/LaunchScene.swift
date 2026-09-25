import Foundation
import MotifCore

/// Where to start, from launch arguments. Used for screenshots and UI checks, so a given
/// screen can be reached without tapping through the app. Debug builds only.
///
///     -MotifTab charts            Summary, Play, History or Charts (iPhone)
///     -MotifSearch YES            open search on the first tab (iPhone)
///     -MotifDemoPlaying YES       with sample data, start the Play tab's first mix (iPhone);
///                                 "station" for Motif Radio, or a mood such as "chill"
///     -MotifNowPlaying YES        open Now Playing once something plays (iPhone)
///     -MotifQueue YES             and show Up Next in it (iPhone), or the panel (Mac)
///     -MotifSleeve YES            and turn the cover over to Your History
///     -MotifMix onRepeat          open one of the Play tab's mixes by id (iPhone)
///     -MotifSampleAlbum YES       open an invented Apple Music album page (iPhone)
///     -MotifMood chill            open a mood's page (iPhone)
///     -MotifPage songs            open the Song Finder (or "songs.chill" for a lens), the
///                                 Artist Finder ("artists") or New from Your Artists
///                                 ("releases") (iPhone)
///     -MotifRadioTuner YES        open Motif Radio's tuning from its card (iPhone)
///     -MotifSettings play         open Settings at one of its pages: play, history, radio,
///                                 appleMusic, lastFM or iCloud (iPhone)
///     -MotifEditPlay YES          open Edit Play (iPhone)
///     -MotifSidebar history       a sidebar item (Mac): listenNow, radio, summary, history,
///                                 topSongs, playlists, albums and the like
///     -MotifScroll rhythm         a section of Summary to scroll to
///     -MotifOpen "artist:mara solis"   an artist, song:<title>|<artist>,
///                                      or album:<title>|<artist>
///     -MotifSettings YES          open Settings
///     -MotifSearchText "mara"     search for this in the sidebar (Mac)
///     -MotifMiniPlayer YES        open the Mini Player too (Mac)
///     -MotifActivate YES          come to the front, so the window is drawn focused (Mac)
///     -statsRange year            the range, since it's stored under that key
///     -MotifPeriodsBack 1         start Summary that many weeks, months or years back
///     -chartSpan day              Top Charts' period: day, week, month, year or allTime
///     -MotifChartDate 2026-09-01  start Top Charts on the period holding this day
///     -separatesMusicSources YES  count Apple Music and Your Music apart, and
///     -statsSourceScope yourMusic show one of them: all, appleMusic or yourMusic
///     -MotifDemoDriving YES       Motif Radio as if driving
///     -MotifRadioTunerAnchor moments  open the Tune sheet at Time and Driving
///     -MotifRadioTunerAnchor day  open the Tune sheet on Through the Day (iPhone)
///     -MotifThroughTheDayAnchor bottom  scroll Through the Day to its foot
///     -MotifThroughTheDay YES     open Through the Day from the Play pane (Mac)
///     -MotifAppearance light      draw the Mac sheet light whatever the Mac's setting
///     -MotifNearbyDemo YES        a device nearby playing a song (or "paused", or "control"
///                                 to show it in the player)
///     -MotifDevices YES           open Your Devices
enum LaunchScene {
    static var tab: String? { value("MotifTab") }
    static var sidebar: String? { value("MotifSidebar") }
    static var scrollAnchor: String? { value("MotifScroll") }
    static var opensSettings: Bool { value("MotifSettings") != nil }
    static var opensDevices: Bool { value("MotifDevices") == "YES" }
    /// The page of Settings to open on, by its name.
    static var settingsPageName: String? { value("MotifSettings") }
    static var opensPlaySettings: Bool { value("MotifSettings") == "play" }
    /// How many weeks, months or years back Summary starts.
    static var periodOffset: Int { -(value("MotifPeriodsBack").flatMap(Int.init).map(abs) ?? 0) }
    static var opensEditPlay: Bool { value("MotifEditPlay") == "YES" }
    static var activates: Bool { value("MotifActivate") == "YES" }
    static var opensSearch: Bool { value("MotifSearch") == "YES" }
    /// Text already in the search field (Mac).
    static var searchText: String? { value("MotifSearchText") }
    static var opensNowPlaying: Bool { value("MotifNowPlaying") == "YES" }
    static var opensQueue: Bool { value("MotifQueue") == "YES" }
    static var opensSleeve: Bool { value("MotifSleeve") == "YES" }
    static var opensRadioTuner: Bool { value("MotifRadioTuner") == "YES" }
    /// The day Top Charts starts on, as yyyy-MM-dd.
    static var chartDate: Date? {
        value("MotifChartDate").flatMap { try? Date($0, strategy: .iso8601.year().month().day()) }
    }

    static var route: Route? {
        guard let open = value("MotifOpen") else { return nil }
        let parts = open.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "artist":
            return .artist(parts[1])
        case "song":
            let song = parts[1].split(separator: "|").map(String.init)
            guard song.count == 2 else { return nil }
            return .song(HistoryImport.key(title: song[0], artistName: song[1]))
        case "album":
            // Album and artist together, as `CaptureStat.albumIdentity` builds it.
            let album = parts[1].split(separator: "|").map(String.init)
            guard album.count == 2 else { return nil }
            return .album("\(StatsCalculator.folded(album[0]))\u{1F}\(StatsCalculator.folded(album[1]))")
        default:
            return nil
        }
    }

    private static func value(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }
}

extension LaunchScene {
    /// Starts the first mix with sample data, for screenshots of the player. Once per launch.
    @MainActor
    static func startDemoPlayback(_ model: AppModel) {
        guard model.isDemoLaunch, let playing = value("MotifDemoPlaying"), !hasStartedDemoPlayback else { return }
        if playing == "station" {
            hasStartedDemoPlayback = true
            model.player.playMotifRadio()
            return
        }
        if playing == "local", let album = model.yourMusic.index.recentlyAdded.first {
            hasStartedDemoPlayback = true
            model.player.play(.local(album.tracks), from: PlayContext(kind: .album, title: album.title))
            return
        }
        if let mood = Mood(rawValue: playing) {
            hasStartedDemoPlayback = true
            Task { await MoodPlayback.start(mood, model: model) }
            return
        }
        guard playing == "YES", let mix = model.playFeed.mixes.rightNow ?? model.playFeed.mixes.mixes.first else { return }
        hasStartedDemoPlayback = true
        model.player.play(.history(model.player.songs(in: mix)), from: PlayContext(kind: .mix, title: mix.kind.title))
    }

    @MainActor private static var hasStartedDemoPlayback = false

    /// Opens the mix named by `-MotifMix` on the Play tab, once its mixes exist.
    @MainActor
    static func openMix(_ model: AppModel) {
        #if DEBUG
        if let name = value("MotifMood"), let mood = Mood(rawValue: name), !hasOpenedMix {
            hasOpenedMix = true
            show(.mood(mood), in: model)
            return
        }
        if let page = value("MotifPage"), !hasOpenedMix {
            let parts = page.split(separator: ".").map(String.init)
            let route: PlayRoute? = switch parts.first {
            case "songs": .songFinder(parts.count > 1 ? SongLens.all.first { $0.id == parts[1] || $0.id == "mood.\(parts[1])" } ?? .forYou : .forYou)
            case "artists": .artistFinder
            case "releases": .newReleases
            case "yourSongs": .yourMusic(.songs)
            case "yourAlbums": .yourMusic(.albums)
            case "yourArtists": .yourMusic(.artists)
            case "downloads": .yourMusic(.downloads)
            case "lidarr": .lidarr
            case "localAlbum": model.yourMusic.index.recentlyAdded.first.map { .localAlbum($0.id) }
            case "localArtist": model.yourMusic.index.artists.first.map { .localArtist($0.id) }
            default: nil
            }
            if let route {
                hasOpenedMix = true
                show(route, in: model)
                return
            }
        }
        if value("MotifSampleAlbum") == "YES", !hasOpenedMix {
            hasOpenedMix = true
            show(.album(PreviewMusic.album()), in: model)
            return
        }
        #endif
        guard let id = value("MotifMix"), !hasOpenedMix, model.playFeed.mixes.mix(id: id) != nil else { return }
        hasOpenedMix = true
        show(.mix(id), in: model)
    }

    @MainActor private static var hasOpenedMix = false

    /// A page on the Play tab on iPhone, or on Listen Now on the Mac, once the window has
    /// moved there: moving to another place clears the stack it pushes onto.
    @MainActor
    private static func show(_ route: PlayRoute, in model: AppModel) {
        model.selectedTab = .play
        guard model.sidebarSelection != .listenNow else {
            model.playNavigator.show(route)
            return
        }
        model.sidebarSelection = .listenNow
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            model.playNavigator.show(route)
        }
    }
}
