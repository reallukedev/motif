import UIKit
import CarPlay
import MusicKit
import MotifCore

/// Motif in the car: four tabs made for a glance and one tap, as Music has them, built from
/// CarPlay's own templates so they look and work like the rest of the car.
///
/// - Listen Now leads with large cards (where you left off, the mix for right now, Motif
///   Radio), then what you played last, your mixes, and your week.
/// - Radio opens on Motif Radio's own header, then every mood as a tile, then Apple's live
///   stations.
/// - Library opens Playlists, Artists, Albums, Songs and Downloaded as pages, an album or
///   playlist with Play and Shuffle at the top, as Music's do.
/// - Search is Siri, since CarPlay gives music apps a voice rather than a keyboard, and your
///   recent searches from the phone.
///
/// Everything plays through the same player as the phone, so every song is kept. The files
/// beside this one build each tab, Now Playing, and the pictures.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver, CPTabBarTemplateDelegate {
    var interface: CPInterfaceController?
    var scale: CGFloat = 2
    /// How many covers a shelf shows: one line's worth on this car's screen. The car keeps room
    /// for every cover it's given even when it draws only one line, which left a blank band
    /// under each shelf; the rest are a tap away on the shelf's page.
    var shelfLength = 4
    let model = AppModel.shared
    private var watch: Task<Void, Never>?
    private var refresh: Task<Void, Never>?
    private var radioRefresh: Task<Void, Never>?
    /// Watches the settings the car shows (Motif Radio on or off, Autoplay), which live in
    /// UserDefaults, where nothing observable says they changed.
    private var settingsObserver: NSObjectProtocol?
    private var shownSettings: (radio: Bool, autoplay: Bool)?
    /// What each tab was last built from, so a tab only reloads when something on it changed.
    /// A reload while someone's scrolling moves the list under their finger.
    private var builtFrom: [ObjectIdentifier: Int] = [:]
    /// What the Library tab was last built for: the source, and Apple Music access or the size
    /// of your own library.
    private var libraryBuiltFor: String?
    /// Up Next while it's open, to keep it current as the queue moves.
    var queue: CPListTemplate?
    var isQueueShown = false
    var nowPlayingWatch: Task<Void, Never>?
    var keepTicker: Task<Void, Never>?
    var lastKeepStep: Int?
    /// Songs added to the library from Now Playing, so its button can show it worked.
    var addedToLibrary: Set<String> = []
    /// Where Motif Radio stood when Radio was last built, so the tab is redrawn when it changes.
    var radioRowState: String?

    lazy var listenNow = tab(String(localized: "Listen Now"), symbol: "play.circle.fill")
    lazy var radio = tab(String(localized: "Radio"), symbol: "dot.radiowaves.left.and.right")
    lazy var library = tab(String(localized: "Library"), symbol: "square.stack.fill")
    lazy var search = tab(String(localized: "Search"), symbol: "magnifyingglass")

    // MARK: - Connecting

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        scale = interfaceController.carTraitCollection.displayScale
        // About 160 points a cover, beside the car's own side bar and the list's page arrows.
        let width = scene.carWindow.bounds.width
        shelfLength = min(Int(CPMaximumNumberOfGridImages), max(4, Int((width - 150) / 160)))
        configureNowPlaying()
        // Siri, where the car's music apps put it: at the top of Search, or of Library in a car
        // with room for only three tabs.
        let siri = CPAssistantCellConfiguration(position: .top, visibility: .always, assistantAction: .playMedia)
        let hasSearch = CPTabBarTemplate.maximumTabCount >= 4
        if hasSearch {
            search.assistantCellConfiguration = siri
            update(search, searchSections())
        } else {
            library.assistantCellConfiguration = siri
        }
        let tabs = CPTabBarTemplate(templates: hasSearch ? [listenNow, radio, library, search] : [listenNow, radio, library])
        tabs.delegate = self
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)

        // The car can start Motif with no phone window, so nothing else has started capture.
        Task { await model.startCapture() }
        Task {
            await model.prepareForPlaying()
            rebuild()
            await model.playFeed.loadAppleMusic()
            await model.playFeed.loadFromYourArtists()
            rebuild()
        }
        shownSettings = (PlayPreferences.isMotifRadioOn, PlayPreferences.autoplay)
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
        }
        watch = Task { [weak self] in
            guard let model = self?.model else { return }
            let (feed, library, yourMusic, player) = (model.playFeed, model.library, model.yourMusic, model.player)
            let changes = Observations {
                ContentKey(
                    revision: library.revision,
                    mixes: feed.mixes.all.map(\.id),
                    shelves: (feed.recentlyPlayed + feed.liveStations + feed.newReleases + feed.charts).map(\.id)
                        + feed.recommendations.map(\.id),
                    discover: feed.discover.count,
                    source: model.musicSource,
                    yourMusic: yourMusic.index.tracks.count,
                    yourPlaylists: yourMusic.playlists.all.count,
                    downloads: yourMusic.downloads.items.count,
                    playing: player.context?.title,
                    waiting: player.waitingSession?.tracks.first?.id,
                    captures: model.library.history.captures.count >= 20
                )
            }
            for await _ in changes {
                self?.rebuild()
            }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        watch?.cancel()
        refresh?.cancel()
        radioRefresh?.cancel()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        nowPlayingWatch?.cancel()
        keepTicker?.cancel()
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
        queue = nil
        isQueueShown = false
        radioRowState = nil
        builtFrom = [:]
        libraryBuiltFor = nil
    }

    /// Search's recent searches can change on the phone at any time, and nothing says so: they're
    /// read again each time the tab is opened.
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        guard selectedTemplate === search else { return }
        update(search, searchSections())
    }

    private struct ContentKey: Equatable {
        let revision: Int
        let mixes: [String]
        let shelves: [String]
        let discover: Int
        let source: MusicSource
        let yourMusic: Int
        let yourPlaylists: Int
        let downloads: Int
        /// What's playing, for the rows that show it.
        let playing: String?
        /// The song left paused, for Listen Now's Continue card.
        let waiting: String?
        /// Whether there's enough listening for Motif Radio.
        let captures: Bool
    }

    private func tab(_ title: String, symbol: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: symbol)
        template.emptyViewTitleVariants = [String(localized: "Loading…")]
        return template
    }

    /// Rebuilds the tabs a moment after the last change, since a capture changes the history,
    /// the mixes and the stats one after another. A tab whose rows came out the same is left
    /// alone.
    private func rebuild() {
        refresh?.cancel()
        refresh = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let listen = await listenNowSections()
            guard !Task.isCancelled else { return }
            update(listenNow, listen)
            let stations = await radioSections()
            guard !Task.isCancelled else { return }
            update(radio, stations)
            // The recent searches are the source's own.
            update(search, searchSections())
            // The library doesn't change with a capture: once, and again if the source,
            // access, or your own music changes.
            let music = model.yourMusic
            let key = model.musicSource == .yourMusic
                ? "yourMusic.\(music.index.albums.count).\(music.playlists.all.count).\(music.downloads.items.isEmpty)"
                : "appleMusic.\(MusicAuthorization.currentStatus)"
            if libraryBuiltFor != key {
                let shelves = model.musicSource == .yourMusic ? await yourMusicLibrarySections() : await appleMusicLibrarySections()
                guard !Task.isCancelled else { return }
                library.updateSections(shelves)
                libraryBuiltFor = key
            }
        }
    }

    /// Redraws what shows a setting when one the car shows has changed: any change to
    /// UserDefaults lands here, most of them nothing to do with the car.
    private func settingsMayHaveChanged() {
        let now = (radio: PlayPreferences.isMotifRadioOn, autoplay: PlayPreferences.autoplay)
        guard let shown = shownSettings, shown != now else { return }
        shownSettings = now
        updateNowPlayingButtons()
        if shown.radio != now.radio { rebuild() }
    }

    /// Radio's list again, on its own: its first row follows Motif Radio starting and pausing.
    func refreshRadioList() {
        radioRefresh?.cancel()
        radioRefresh = Task {
            let sections = await radioSections()
            guard !Task.isCancelled else { return }
            update(radio, sections)
        }
    }

    private func update(_ template: CPListTemplate, _ sections: [CPListSection]) {
        let signature = Self.signature(of: sections)
        guard builtFrom[ObjectIdentifier(template)] != signature else { return }
        builtFrom[ObjectIdentifier(template)] = signature
        template.updateSections(sections)
    }

    /// What a row plays, as a number for its `userInfo`, so a row that reads the same but plays
    /// something new (a mix remade after a song counts) still reloads.
    static func contentToken(_ parts: [String]) -> Int {
        var hasher = Hasher()
        parts.forEach { hasher.combine($0) }
        return hasher.finalize()
    }

    /// What a list shows, as one number: its headers, rows, what they say, which is playing,
    /// and what they play.
    private static func signature(of sections: [CPListSection]) -> Int {
        var hasher = Hasher()
        for section in sections {
            hasher.combine(section.header)
            for item in section.items {
                switch item {
                case let row as CPListItem:
                    hasher.combine(row.text)
                    hasher.combine(row.detailText)
                    hasher.combine(row.isPlaying)
                    hasher.combine(row.userInfo as? Int)
                case let row as CPListImageRowItem:
                    hasher.combine(row.text)
                    hasher.combine(row.userInfo as? Int)
                    for element in row.elements {
                        switch element {
                        case let card as CPListImageRowItemCardElement:
                            hasher.combine(card.title)
                            hasher.combine(card.subtitle)
                        case let tile as CPListImageRowItemImageGridElement:
                            hasher.combine(tile.title)
                        case let entry as CPListImageRowItemRowElement:
                            hasher.combine(entry.title)
                            hasher.combine(entry.subtitle)
                        case let person as CPListImageRowItemCondensedElement:
                            hasher.combine(person.title)
                            hasher.combine(person.subtitle)
                        default:
                            break
                        }
                    }
                default:
                    break
                }
            }
        }
        return hasher.finalize()
    }

    /// Whether Motif Radio is on and has enough of your listening to play from.
    var hasMotifRadio: Bool {
        PlayPreferences.isMotifRadioOn && model.library.history.captures.count >= 20
    }

    /// Whether what's playing came from here: a mix, mood or station by its name.
    func isPlaying(_ title: String) -> Bool {
        model.player.hasQueue && model.player.context?.title == title
    }

    // MARK: - Playing

    /// Plays, then shows Now Playing, or says what went wrong, in the car: no one should need
    /// the phone to find out.
    func play(_ action: @escaping () async -> Void, completion: @escaping () -> Void) {
        // Asking for Apple Music access from the car would put a prompt on a phone no one is
        // looking at, and leave the row spinning. Decided here, not from a problem left over
        // from the phone, which would otherwise stop every row playing.
        let needsAccess = !model.isDemoLaunch && model.musicSource == .appleMusic
            && MusicAuthorization.currentStatus != .authorized
        model.player.problem = needsAccess ? .accessDenied : nil
        Task { [weak self] in
            if !needsAccess { await action() }
            completion()
            guard let self else { return }
            if let problem = model.player.problem {
                model.player.problem = nil
                show(problem)
            } else {
                showNowPlaying()
            }
        }
    }

    /// Brings Now Playing up: back to it when it's already open under a page (an album opened
    /// from it), since CarPlay won't take the same screen twice.
    func showNowPlaying() {
        guard let interface else { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        if interface.topTemplate === nowPlaying { return }
        if interface.templates.contains(where: { $0 === nowPlaying }) {
            interface.pop(to: nowPlaying, animated: true, completion: nil)
            return
        }
        // CarPlay takes five screens at most, and Now Playing needs room above it for Up Next
        // and the album. Played from deep in a tab, it starts a fresh trail from the tab.
        if interface.templates.count >= Self.deepestBeforeNowPlaying {
            interface.popToRootTemplate(animated: false, completion: nil)
        }
        interface.pushTemplate(nowPlaying, animated: true, completion: nil)
    }

    /// How many screens can sit under Now Playing and still leave one above it.
    static let deepestBeforeNowPlaying = 4

    /// A problem in a sheet with what went wrong and what to do, since the car's alert only
    /// has room for a title.
    private func show(_ problem: PlayerProblem) {
        let sheet = CPActionSheetTemplate(
            title: problem.title,
            message: problem.message,
            actions: [CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                self?.interface?.dismissTemplate(animated: true, completion: nil)
            }]
        )
        interface?.presentTemplate(sheet, animated: true, completion: nil)
    }
}

