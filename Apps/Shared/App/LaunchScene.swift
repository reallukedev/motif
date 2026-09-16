import Foundation
import MotifCore

/// Where to start, from launch arguments. Used for screenshots and UI checks, so a given
/// screen can be reached without tapping through the app. Debug builds only.
///
///     -MotifTab charts            Summary, History, Charts or Search (iPhone)
///     -MotifSidebar history       a sidebar item (Mac)
///     -MotifScroll rhythm         a section of Summary to scroll to
///     -MotifOpen "artist:mara solis"   an artist, song:<title>|<artist>,
///                                      or album:<title>|<artist>
///     -MotifSettings YES          open Settings
///     -MotifActivate YES          come to the front, so the window is drawn focused (Mac)
///     -statsRange year            the range, since it's stored under that key
enum LaunchScene {
    static var tab: String? { value("MotifTab") }
    static var sidebar: String? { value("MotifSidebar") }
    static var scrollAnchor: String? { value("MotifScroll") }
    static var opensSettings: Bool { value("MotifSettings") == "YES" }
    static var activates: Bool { value("MotifActivate") == "YES" }

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

