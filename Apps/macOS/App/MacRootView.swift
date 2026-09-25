import SwiftUI
import MotifCore

/// The main window: the sidebar of places, the page chosen, and the song playing at the foot
/// of it, with Up Next and the song's history in a popover rising from it.
struct MacRootView: View {
    @Bindable var model: AppModel
    @State private var query = LaunchScene.searchText ?? ""
    @Environment(\.openWindow) private var openWindow
    @AppStorage(OpeningTab.storageKey) private var openingTab: OpeningTab = .summary
    @AppStorage(PlayPreferences.songDestinationKey) private var songDestination = SongDestination.motif
    @AppStorage(SearchScope.macStorageKey) private var searchScope: SearchScope = .appleMusic
    /// The panel and the full player: the window's, not the app's.
    @State private var playerWindow = PlayerWindowState()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        if let store = model.store, let capture = model.capture, let playback = model.playback {
            @Bindable var navigator = model.playNavigator
            @Bindable var playerWindow = playerWindow
            let player = model.player
            NavigationSplitView {
                MacSidebar(
                    selection: $model.sidebarSelection,
                    opening: openingTab,
                    library: SidebarItem.library(for: model.musicSource, hasLidarr: model.lidarr.isSetUp),
                    libraryTitle: model.musicSource == .yourMusic ? "Your Music" : "Library"
                )
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            } detail: {
                NavigationStack(path: $navigator.path) {
                    detail
                        .pageChrome()
                        .motifDestinations()
                        .playDestinations()
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: Text("Search"))
            .searchFocused($isSearchFocused)
            .environment(playerWindow)
            .environment(\.beginSearch, BeginSearchAction { scope in beginSearch(in: scope) })
            .onChange(of: model.sidebarSelection) {
                navigator.path = NavigationPath()
                query = ""
            }
            // Initial too, for a window the request itself had to open.
            .onChange(of: model.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                query = ""
                navigator.path = NavigationPath([route])
                model.pendingRoute = nil
            }
            .onChange(of: model.musicSource) { old, source in
                follow(sourceChangeFrom: old, to: source)
            }
            .onChange(of: player.hasQueue) { _, hasQueue in
                if !hasQueue { playerWindow.showsPanel = false }
            }
            // The popover is the bar's, and the full player covers the bar.
            .onChange(of: isShowingFullPlayer) { _, isShowing in
                if isShowing { playerWindow.showsPanel = false }
            }
            // The full player takes the whole window: the toolbar, the keyboard and VoiceOver
            // leave the page behind it until it closes.
            .toolbarVisibility(isShowingFullPlayer ? .hidden : .automatic, for: .windowToolbar)
            .accessibilityHidden(isShowingFullPlayer)
            .overlay {
                if isShowingFullPlayer {
                    FullPlayer { playerWindow.showsFullPlayer = false }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : PlayMotion.panel, value: isShowingFullPlayer)
            .playerFeedback()
            // Your devices, at the far end of the titlebar on every page, as Spotify keeps its
            // Connect button in reach wherever you are.
            .background {
                TitlebarAccessory(isHidden: isShowingFullPlayer) {
                    DevicesButton()
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.extraLarge)
                        .padding(.trailing, 12)
                        .padding(.leading, 6)
                        .frame(height: 52)
                        .environment(model)
                        .environment(model.player)
                }
            }
            // Songs being added to a playlist, from a menu anywhere.
            .sheet(item: Bindable(model.yourMusic.playlists).picking) { PlaylistPickerSheet(pick: $0) }
            .playerCommands(
                showsPanel: $playerWindow.showsPanel,
                panelPage: $playerWindow.panelPage,
                showsFullPlayer: $playerWindow.showsFullPlayer,
                goToCurrentSong: goToCurrentSong,
                beginSearch: { beginSearch(in: nil) }
            )
            .opensDeepLinks(in: model)
            .observesLibrary(model.library)
            .modelContainer(store.container)
            .environment(capture)
            .environment(playback)
            .playEnvironment(model, playsSongsInMotif: songDestination == .motif)
            .task { await model.playFeed.followSubscription() }
            .task { await model.lidarr.check() }
            .task(id: model.musicSource) {
                if model.musicSource == .yourMusic { model.prepareYourMusic() }
            }
            .onChange(of: model.playFeed.builtRevision) {
                if model.musicSource == .yourMusic { model.prepareYourMusic() }
                LaunchScene.startDemoPlayback(model)
                LaunchScene.openMix(model)
            }
            // Through the Mac's one voice: Music may be the player your devices are shown.
            .onChange(of: "\(player.current?.id ?? "").\(player.isPlaying)") { Task { await NearbyMac.tell(model) } }
            #if DEBUG
            .task {
                if UserDefaults.standard.bool(forKey: "MotifMenuBarPreview") {
                    openWindow(id: "menubar-preview")
                }
                // A launch from a script isn't activated, so screenshots show a greyed-out window.
                // Only the deprecated form still takes focus from another app on macOS 27.
                if LaunchScene.activates {
                    NSApp.activate(ignoringOtherApps: true)
                }
                CollectionScreenshotSetup.apply()
                if UserDefaults.standard.bool(forKey: "MotifMiniPlayer") {
                    // Once the main window is up, as someone would open it.
                    try? await Task.sleep(for: .seconds(2))
                    openWindow(id: MiniPlayerWindow.id)
                }
                if LaunchScene.opensSettings {
                    MenuBarFooter.bringSettingsForward(openSettings: openSettings)
                }
            }
            #endif
        } else {
            ContentUnavailableView {
                Label("Motif Can't Open Your History", systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.startupError ?? "The database couldn't be opened.")
            }
        }
    }

    /// Pages pushed for one source mean nothing in the other. A library row the other source
    /// also has (Albums, Songs) stays chosen and shows that source's; one it doesn't have
    /// (Downloads, Lidarr) goes back to Listen Now.
    private func follow(sourceChangeFrom old: MusicSource, to source: MusicSource) {
        guard old != source else { return }
        model.playNavigator.path = NavigationPath()
        if let selection = model.sidebarSelection,
           SidebarItem.library(for: old, hasLidarr: true).contains(selection),
           !SidebarItem.library(for: source, hasLidarr: model.lidarr.isSetUp).contains(selection) {
            model.sidebarSelection = .listenNow
        }
        if source == .yourMusic { model.prepareYourMusic() }
    }

    private var isShowingFullPlayer: Bool {
        playerWindow.showsFullPlayer && model.player.hasQueue
    }

    /// The cursor in the sidebar's search field, out of the full player, in `scope` if given.
    private func beginSearch(in scope: SearchScope?) {
        playerWindow.showsFullPlayer = false
        if let scope { searchScope = scope }
        isSearchFocused = true
    }

    /// The playing song's album, or its stats when there's no album to show.
    private func goToCurrentSong() {
        guard let track = model.player.current else { return }
        playerWindow.showsFullPlayer = false
        query = ""
        let navigator = model.playNavigator
        if let local = track.local {
            navigator.show(.localAlbum(local.albumKey))
        } else if let song = track.song {
            Task {
                if let album = await SongLinks.album(of: song) {
                    navigator.show(.album(album))
                } else {
                    navigator.show(.stats(.song(track.songIdentity)))
                }
            }
        } else {
            navigator.show(.stats(.song(track.songIdentity)))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            MacSearchResults(query: query, scope: $searchScope) { query = $0 }
        } else {
            switch model.sidebarSelection ?? SidebarItem.opening {
            case .listenNow: ListenNowPage()
            case .radio: RadioPage()
            case .summary: MacSummaryView()
            case .history: MacHistoryView()
            case .topSongs: TopChartView(kind: .songs)
            case .topArtists: TopChartView(kind: .artists)
            case .topAlbums: TopChartView(kind: .albums)
            case .recentlyAdded, .playlists, .albums, .artists, .songs, .downloads, .lidarr:
                LibraryPage(item: model.sidebarSelection ?? .playlists, source: model.musicSource)
            }
        }
    }
}

/// Places, in the order Open To gives them, then the library of the music Play is on, as
/// Music's sidebar ends with its library.
private struct MacSidebar: View {
    @Binding var selection: SidebarItem?
    let opening: OpeningTab
    let library: [SidebarItem]
    let libraryTitle: LocalizedStringKey

    var body: some View {
        List(selection: $selection) {
            let leading = SidebarItem.leading(opening: opening)
            let playing = leading.filter { $0 == .listenNow || $0 == .radio }
            let listening = leading.filter { $0 != .listenNow && $0 != .radio }
            if opening == .play {
                Section { rows(playing) }
                Section("Your Listening") { rows(listening) }
            } else {
                Section { rows(listening) }
                Section("Play") { rows(playing) }
            }
            Section(libraryTitle) { rows(library) }
        }
    }

    private func rows(_ items: [SidebarItem]) -> some View {
        ForEach(items) { item in
            Label(item.title, systemImage: item.symbol)
                .tag(item)
        }
    }
}

extension SearchScope {
    /// Where the Mac window remembers the scope searched last.
    static let macStorageKey = "macSearchScope"
}

extension View {
    /// Everything a page that plays music reads: the player and what it plays from, and where
    /// its pages push.
    func playEnvironment(_ model: AppModel, playsSongsInMotif: Bool) -> some View {
        modifier(PlayEnvironment(model: model, playsSongsInMotif: playsSongsInMotif))
    }
}

private struct PlayEnvironment: ViewModifier {
    let model: AppModel
    let playsSongsInMotif: Bool

    func body(content: Content) -> some View {
        let player = model.player
        let navigator = model.playNavigator
        content
            .environment(model)
            .environment(player)
            .environment(model.playFeed)
            .environment(model.discovery)
            .environment(model.yourMusic)
            .environment(model.lidarr)
            .environment(navigator)
            .environment(\.openPlayRoute, OpenPlayRouteAction(stack: "main") { navigator.show($0) })
            // A song's Play button plays in Motif, where every play is kept, unless Settings
            // sends songs to Music.
            .environment(\.playSongs, playsSongsInMotif ? PlaySongsAction { items, title in
                player.play(.history(items.map(HistorySong.init)), from: .songs(title))
            } : nil)
    }
}
