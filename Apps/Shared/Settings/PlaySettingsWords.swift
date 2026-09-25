import Foundation
import MotifCore

/// The words for Settings ▸ Play on iPhone and the Mac's Play pane, worked out from plain
/// values so both read the same in every state and the views only lay them out.
enum PlaySettingsWords {

    // MARK: - Status

    /// Where Play stands, as the hero's status line reads it.
    struct Standing: Equatable {
        var source: MusicSource
        var opening: OpeningTab
        /// Whether Motif may play Apple Music.
        var allowsAppleMusic: Bool
        /// iPhone's Offline Mode, with how many songs are downloaded. Nil when it's off.
        var offlineSongs: Int?
        /// Songs in your music: files, and every song on your servers.
        var songs: Int
        var servers: Int
        /// The first server with a problem, by name.
        var troubledServer: TroubledServer?
    }

    struct TroubledServer: Equatable {
        var name: String
        var needsPassword: Bool
    }

    static func status(_ standing: Standing) -> (line: String, tone: SettingsTone) {
        switch standing.source {
        case .appleMusic:
            guard standing.allowsAppleMusic else {
                #if os(macOS)
                return (String(localized: "Allow Apple Music in General to play it here."), .attention)
                #else
                return (String(localized: "Allow Apple Music in Settings ▸ Apple Music to play it here."), .attention)
                #endif
            }
            if let offline = standing.offlineSongs {
                let songs = plain(AttributedString(localized: "^[\(offline) downloaded song](inflect: true)"))
                return (String(localized: "Offline Mode · \(songs)"), .plain)
            }
            return (String(localized: "Plays Apple Music · opens to \(openingName(standing.opening))"), .plain)
        case .yourMusic:
            if let server = standing.troubledServer {
                let name = quoted(server.name)
                return server.needsPassword
                    ? (String(localized: "\(name) needs its password"), .attention)
                    : (String(localized: "\(name) can’t be reached"), .attention)
            }
            guard standing.songs > 0 || standing.servers > 0 else {
                return (String(localized: "Add songs or connect a server to start."), .attention)
            }
            let songs = plain(AttributedString(localized: "^[\(standing.songs) song](inflect: true)"))
            return (String(localized: "Plays Your Music · \(songs)"), .plain)
        }
    }

    // MARK: - Source

    static func sourceFooter(_ source: MusicSource, quickSwitch: QuickSwitchState) -> String {
        #if os(macOS)
        let what = source == .appleMusic
            ? String(localized: "Listen Now and your library play Apple Music. Choose Your Music to play the FLAC and other files you own, and songs on your own music server.")
            : String(localized: "Listen Now and your library play your own music: files on this Mac, and songs on your servers. Every song is kept in your history, just like Apple Music’s.")
        #else
        let what = source == .appleMusic
            ? String(localized: "Play plays Apple Music. Choose Your Music to play the FLAC and other files you own, and songs on your own music server.")
            : String(localized: "Play plays your own music: files on this iPhone, and songs on your servers. Every song is kept in your history, just like Apple Music’s.")
        #endif
        switch quickSwitch {
        case .unavailable:
            return what
        case .off:
            #if os(macOS)
            return what + " " + String(localized: "Quick Switch puts both a click away, in Listen Now’s title.")
            #else
            return what + " " + String(localized: "Quick Switch puts both a tap away, in Play’s title.")
            #endif
        case .on:
            #if os(macOS)
            return what + " " + String(localized: "Click Listen Now’s title to switch. What’s playing carries on until you play something from the other.")
            #else
            return what + " " + String(localized: "Tap Play’s title to switch. What’s playing carries on until you play something from the other, and Play suggests your downloads when you’re offline. To switch with a Focus, add Motif’s filter in Settings ▸ Focus.")
            #endif
        }
    }

    enum QuickSwitchState: Equatable {
        /// Only offered with Apple Music allowed and music of your own.
        case unavailable
        case off
        case on
    }

    // MARK: - Around Motif

    /// Where Motif opens: "Play" on iPhone, "Listen Now" on the Mac, where Play is the
    /// sidebar's Listen Now.
    static func openingName(_ tab: OpeningTab) -> String {
        switch tab {
        case .summary: String(localized: "Summary")
        #if os(macOS)
        case .play: String(localized: "Listen Now")
        #else
        case .play: String(localized: "Play")
        #endif
        }
    }

    static func openingFooter(_ tab: OpeningTab) -> String {
        #if os(macOS)
        tab == .play
            ? String(localized: "Motif opens to Listen Now, and Listen Now and Radio come first in the sidebar, as ⌘1 and ⌘2.")
            : String(localized: "Motif opens to Summary, and your listening comes first in the sidebar, as ⌘1 onwards.")
        #else
        tab == .play
            ? String(localized: "Motif opens to Play, and Play comes first in the tab bar.")
            : String(localized: "Motif opens to Summary, and Play comes last in the tab bar.")
        #endif
    }

    /// "Motif" or "Apple Music"; on the Mac, "Music" is the Music app.
    static func destinationName(_ destination: SongDestination) -> String {
        switch destination {
        case .motif: String(localized: "Motif")
        #if os(macOS)
        case .appleMusic: String(localized: "Music")
        #else
        case .appleMusic: String(localized: "Apple Music")
        #endif
        }
    }

    static func destinationFooter(_ destination: SongDestination) -> String {
        #if os(macOS)
        destination == .motif
            ? String(localized: "Play on a song or album in Your Listening plays it here, in Motif.")
            : String(localized: "Play on a song or album in Your Listening opens it in the Music app.")
        #else
        destination == .motif
            ? String(localized: "Play on a song or album in Summary, History and Charts plays it here.")
            : String(localized: "Play on a song or album in Summary, History and Charts opens it in Apple Music.")
        #endif
    }

    /// Your other devices, and on iPhone, shaking it.
    /// - Parameter needsLocalNetwork: Local Network is off for Motif, so it can't find them.
    static func devicesFooter(showsNearby: Bool, shakeToPlay: Bool, needsLocalNetwork: Bool = false) -> String {
        var lines: [String] = []
        #if os(iOS)
        if shakeToPlay {
            lines.append(String(localized: "Shake iPhone to play a song you haven’t heard that Motif thinks you’ll like, with Motif Radio after it."))
        }
        #endif
        if showsNearby {
            #if os(macOS)
            lines.append(String(localized: "Listen Now shows what Motif on your iPhone or iPad is playing when it’s nearby, with its controls and Play Here. Only your own devices, signed in to your iCloud, can connect."))
            #else
            lines.append(String(localized: "Play shows what Motif on your Mac or iPad is playing when it’s nearby, with its controls and Play Here. Only your own devices, signed in to your iCloud, can connect."))
            #endif
            if needsLocalNetwork { lines.append(localNetworkOff) }
        }
        return lines.joined(separator: " ")
    }

    /// Why your devices can't be found, and where to fix it.
    static var localNetworkOff: String {
        #if os(macOS)
        String(localized: "Motif can’t look for them: turn on Motif in System Settings › Privacy & Security › Local Network.")
        #else
        String(localized: "Motif can’t look for them: turn on Local Network in Settings › Apps › Motif.")
        #endif
    }

    // MARK: - Your Music

    static func suggestionFooter(_ mode: SuggestionMode) -> String {
        switch mode {
        case .everything:
            String(localized: "Your servers find songs by the artists you play and artists like them, mixed with songs you have and haven’t played yet. No Apple Music needed.")
        case .onlyYours:
            #if os(macOS)
            String(localized: "Motif suggests only songs you have, on this Mac or your servers. Nothing new is found for you.")
            #else
            String(localized: "Motif suggests only songs you have, on this iPhone or your servers. Nothing new is found for you.")
            #endif
        case .off:
            #if os(macOS)
            String(localized: "No suggestions: Listen Now shows your own music and nothing else.")
            #else
            String(localized: "No suggestions: Play shows your own music and nothing else.")
            #endif
        }
    }

    /// iPhone's footer for Downloads and Streaming. The Mac's rows say it in their details.
    static func downloadsFooter(automatic: Bool, quality: StreamQuality) -> String {
        let downloads = automatic
            ? String(localized: "Songs you play or add from your servers download to this iPhone, so they start at once and play with no connection.")
            : String(localized: "Songs download only when you ask.")
        let streaming = quality == .original
            ? String(localized: "On Wi-Fi and cellular, songs stream as they are on your server, FLAC included.")
            : String(localized: "On Wi-Fi, songs stream as they are on your server. On cellular, your server makes a smaller copy as they play.")
        return downloads + " " + streaming
    }

    // MARK: - Motif Radio

    /// Where Motif Radio shows, which depends on the source and on what the layout shows.
    struct RadioPlace: Equatable {
        var source: MusicSource
        var showsForYou: Bool
        var showsSuggestedSongs: Bool
        /// Your Music's suggestions aren't off.
        var suggests: Bool
    }

    /// On iPhone the footer carries it all. The Mac's rows say what each switch does, so its
    /// footer says only where the station is and what Siri plays.
    static func radioFooter(isOn: Bool, place: RadioPlace, downloadsFirst: Bool, deletesAfterPlaying: Bool) -> String {
        #if os(macOS)
        guard isOn else {
            return String(localized: "Siri plays your mix for this time of day when you say “Play music in Motif.”")
        }
        return [radioWhere(place), String(localized: "Siri plays it when you say “Play music in Motif.”")]
            .compactMap(\.self)
            .joined(separator: " ")
        #else
        guard isOn else {
            return String(localized: "Motif Radio is hidden. Siri plays your mix for this time of day when you say “Play music in Motif.”")
        }
        var lines = [String(localized: "Your own station, from everything you love and new finds like it, picked as it plays.")]
        if let whereItIs = radioWhere(place) {
            lines.append(whereItIs)
        }
        lines.append(String(localized: "Siri plays it when you say “Play music in Motif.”"))
        guard place.source == .yourMusic, downloadsFirst else { return lines.joined(separator: " ") }
        lines.append(String(localized: "It starts with songs on this iPhone, so it plays at once, and downloads its new finds in the background. They wait in Up Next until they’re here, and you can swipe away any you don’t want."))
        if deletesAfterPlaying {
            lines.append(String(localized: "Each new find’s download goes once it’s played. Keep one from Up Next, or add it to a playlist, and it stays."))
        }
        return lines.joined(separator: " ")
        #endif
    }

    private static func radioWhere(_ place: RadioPlace) -> String? {
        switch place.source {
        case .appleMusic:
            #if os(macOS)
            if place.showsForYou { return String(localized: "It’s in For You, at the top of Listen Now, and on Radio.") }
            if place.showsSuggestedSongs { return String(localized: "It leads Suggested Songs on Listen Now, and it’s on Radio.") }
            return String(localized: "It’s on Radio in the sidebar.")
            #else
            if place.showsForYou { return String(localized: "It’s in For You, at the top of Play.") }
            if place.showsSuggestedSongs { return String(localized: "It leads Suggested Songs, since For You is hidden.") }
            return nil
            #endif
        case .yourMusic:
            #if os(macOS)
            return place.suggests
                ? String(localized: "It leads Suggested Songs on Listen Now, and it’s on Radio.")
                : String(localized: "It’s at the top of Listen Now, and on Radio.")
            #else
            return place.suggests
                ? String(localized: "It leads Suggested Songs.")
                : String(localized: "It’s at the top of Play.")
            #endif
        }
    }

    // MARK: - Content and transitions

    static func explicitFooter(_ allows: Bool) -> String {
        allows
            ? String(localized: "When a song comes in both versions, Motif plays the explicit one.")
            : String(localized: "Motif plays clean versions and leaves out songs that only come explicit. On stations, it skips them.")
    }

    static func transitionFooter(_ transition: SongTransition) -> String {
        transition == .crossfade
            ? String(localized: "Each song fades into the next. Songs that run into each other on an album still play without a gap. Starts with the next thing you play.")
            : String(localized: "Each song ends before the next one starts.")
    }

    // MARK: - Layout

    /// "All Shown", or "9 of 12 Shown".
    static func layoutValue(_ layout: PlayLayout) -> String {
        let all = layout.offered.count
        let shown = layout.offered.count(where: layout.isVisible)
        return shown == all
            ? String(localized: "All Shown")
            : String(localized: "\(shown) of \(all) Shown")
    }

    /// For the Mac's row: what the layout adds up to.
    static func layoutDetail(_ layout: PlayLayout) -> String {
        if layout == .standard {
            return String(localized: "Every section, in the standard order.")
        }
        let hidden = layout.offered.count { !layout.isVisible($0) }
        guard hidden > 0 else { return String(localized: "Every section, in your own order.") }
        return plain(AttributedString(localized: "^[\(hidden) section](inflect: true) hidden."))
    }

    // MARK: - Mixes

    /// What the mixes remember from skips and "Suggest Less".
    struct MixMemory: Equatable {
        /// Songs the mixes leave out: skipped early twice lately, or asked to hear less of.
        var leftOut: Int
        var askedLess: Int
        /// Skipped once, so still in the mixes, but one skip from leaving.
        var skippedOnce: Int

        init(leftOut: Int, askedLess: Int, skippedOnce: Int) {
            self.leftOut = leftOut
            self.askedLess = askedLess
            self.skippedOnce = skippedOnce
        }

        init(_ signals: ListeningSignals, now: Date = .now) {
            let songs = Set(signals.skips.keys).union(signals.suggestLess)
            let excluded = songs.filter { signals.excludes($0, now: now) }
            leftOut = excluded.count
            askedLess = signals.suggestLess.count
            skippedOnce = songs.count { !excluded.contains($0) && signals.recentSkips(of: $0, now: now) > 0 }
        }

        var isEmpty: Bool { leftOut == 0 && skippedOnce == 0 }
    }

    /// "7 songs left out · 2 you asked to hear less of", for the Mac's row and iPhone's value.
    static func mixDetail(_ memory: MixMemory) -> String {
        guard !memory.isEmpty else { return String(localized: "Nothing skipped yet") }
        guard memory.leftOut > 0 else {
            return plain(AttributedString(localized: "Nothing left out · ^[\(memory.skippedOnce) song](inflect: true) skipped once"))
        }
        let leftOut = plain(AttributedString(localized: "^[\(memory.leftOut) song](inflect: true) left out"))
        guard memory.askedLess > 0 else { return leftOut }
        return String(localized: "\(leftOut) · \(memory.askedLess) you asked to hear less of")
    }

    static func resetMessage(_ memory: MixMemory) -> String {
        guard memory.leftOut > 0 else {
            return String(localized: "Motif forgets the songs you’ve skipped once. Nothing is left out of your mixes yet.")
        }
        let songs = plain(AttributedString(localized: "^[\(memory.leftOut) song](inflect: true)"))
        return String(localized: "The \(songs) your mixes leave out come back into them, and Motif forgets every skip.")
    }

    /// The confirmation's button, with the count when songs come back.
    static func resetButton(_ memory: MixMemory) -> String {
        guard memory.leftOut > 0 else { return String(localized: "Reset Mix Suggestions") }
        return plain(AttributedString(localized: "Bring Back ^[\(memory.leftOut) Song](inflect: true)"))
    }

    static var mixesFooter: String {
        #if os(macOS)
        String(localized: "Mixes leave out songs you skip early twice or ask to hear less of. That stays on this Mac.")
        #else
        String(localized: "Mixes leave out songs you skip early twice or ask to hear less of. That stays on this iPhone.")
        #endif
    }

    // MARK: - Helpers

    /// Inflection resolved, for places that show the markup literally: status strings, dialog
    /// titles and messages.
    static func plain(_ text: AttributedString) -> String {
        String(text.characters)
    }

    /// Curly quotes, so a name reads as a name inside a sentence.
    static func quoted(_ name: String) -> String {
        "\u{201C}\(name)\u{201D}"
    }
}
