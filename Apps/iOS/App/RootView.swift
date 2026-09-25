import SwiftUI
import MusicKit
import MotifCore

struct RootView: View {
    @Bindable var model: AppModel
    @AppStorage(PlayPreferences.songDestinationKey) private var songDestination = SongDestination.motif
    @State private var summaryPath = LaunchScene.route.map { NavigationPath([$0]) } ?? NavigationPath()
    /// Where the app opens also decides where Play sits: first when it's where Motif opens,
    /// last otherwise, so the opening tab is always far left.
    @AppStorage(OpeningTab.storageKey) private var openingTab: OpeningTab = .summary
    @State private var showsNowPlaying = false
    @Namespace private var nowPlayingTransition
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    var body: some View {
        if let store = model.store, let capture = model.capture, let playback = model.playback {
            @Bindable var player = model.player
            let navigator = model.playNavigator
            // A stable identity per tab, so moving Play between the ends keeps each tab's
            // state, and any sheet open on it, rather than rebuilding it.
            TabView(selection: $model.selectedTab) {
                ForEach(tabOrder, id: \.self) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        stack(for: tab, navigator: navigator)
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: player.hasQueue || model.controlledDevice != nil) {
                // Another device's song while it's the one being controlled, as Spotify
                // Connect shows it; otherwise this iPhone's.
                if let device = model.controlledDevice {
                    RemoteMiniPlayer(device: device)
                } else {
                    MiniPlayer { showsNowPlaying = true }
                        .matchedTransitionSource(id: "nowPlaying", in: nowPlayingTransition)
                }
            }
            .fullScreenCover(isPresented: $showsNowPlaying) {
                NowPlayingView(onNavigate: go(to:))
                    .navigationTransition(.zoom(sourceID: "nowPlaying", in: nowPlayingTransition))
            }
            // The song a shake finds plays in Now Playing, so you see what it is.
            .shakeToPlay(model.player) { showsNowPlaying = true }
            // Songs being added to a playlist, from a menu anywhere.
            .sheet(item: Bindable(model.yourMusic.playlists).picking) { PlaylistPickerSheet(pick: $0) }
            // Under Now Playing while it's open; it shows its own.
            .playerFeedback(isActive: !showsNowPlaying)
            .opensDeepLinks(in: model)
            // A song from a widget. Summary is the tab whose stack can be pushed from here.
            // Initial too, for a link that launched the app.
            .onChange(of: model.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                model.selectedTab = .summary
                summaryPath = NavigationPath([route])
                model.pendingRoute = nil
            }
            // The history and the mixes follow the store in AppModel, for the whole process:
            // Motif also plays with no window, for CarPlay and Siri.
            .onChange(of: model.playFeed.builtRevision) {
                // Sample data's own music is made from the sample history, now it's read.
                if model.musicSource == .yourMusic { model.prepareYourMusic() }
                LaunchScene.startDemoPlayback(model)
                LaunchScene.openMix(model)
            }
            .task { await model.playFeed.followSubscription() }
            .onChange(of: player.hasQueue) { _, hasQueue in
                if hasQueue, LaunchScene.opensNowPlaying { showsNowPlaying = true }
            }
            .modelContainer(store.container)
            .environment(model)
            .environment(capture)
            .environment(playback)
            .environment(model.player)
            .environment(model.playFeed)
            .environment(model.discovery)
            .environment(model.yourMusic)
            .environment(model.lidarr)
            .environment(model.downloadedSongs)
            .environment(model.playNavigator)
            // A song's Play button plays here, where the play is kept, unless Settings sends
            // songs to Apple Music.
            .environment(\.playSongs, songDestination == .motif ? PlaySongsAction { items, title in
                player.play(.history(items.map(HistorySong.init)), from: .songs(title))
            } : nil)
            .task { await model.startCapture() }
            // Lidarr's actions show wherever music does, whatever the source.
            .task { await model.lidarr.check() }
            // Your other devices nearby, and what's playing here for them.
            .task {
                guard !model.isDemoLaunch else { return }
                model.nearby.start()
            }
            .onChange(of: "\(player.current?.id ?? "").\(player.isPlaying)") { model.tellNearby() }
            // Playlists merged with Apple Music, once your servers have had a moment to answer.
            .task {
                guard !model.isDemoLaunch else { return }
                try? await Task.sleep(for: .seconds(5))
                await model.yourMusic.playlistMerge.mergeIfOn()
            }
            .onChange(of: model.musicSource, initial: true) { old, source in
                // Pages pushed for one source mean nothing in the other.
                if old != source { model.playNavigator.path = NavigationPath() }
                if source == .yourMusic { model.prepareYourMusic() }
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS only sees music while Motif is open, so pick up what was missed each
                // time it comes back. Launch is covered by `startCapture`.
                if phase == .background {
                    wasInBackground = true
                } else if phase == .active, wasInBackground, !model.isDemoLaunch {
                    wasInBackground = false
                    Task { await capture.catchUp() }
                    Task { await model.yourMusic.playlistMerge.mergeIfOn() }
                    model.nearby.resume()
                    // Songs dropped into Files while Motif was away.
                    if model.musicSource == .yourMusic { Task { await model.yourMusic.scan() } }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Motif Can't Open Your History", systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.startupError ?? "The database couldn't be opened.")
            }
        }
    }

    /// The tab Motif opens to is far left: Play first when it opens to Play, last otherwise.
    private var tabOrder: [AppTab] {
        openingTab == .play ? [.play, .summary, .history, .charts] : [.summary, .history, .charts, .play]
    }

    @ViewBuilder
    private func stack(for tab: AppTab, navigator: PlayNavigator) -> some View {
        switch tab {
        case .summary:
            NavigationStack(path: $summaryPath) {
                SummaryScreen()
                    .motifDestinations()
                    .playDestinations()
            }
            .environment(\.openPlayRoute, OpenPlayRouteAction(stack: "summary") { summaryPath.append($0) })
        case .play:
            @Bindable var navigator = navigator
            NavigationStack(path: $navigator.path) {
                Group {
                    if model.musicSource == .yourMusic {
                        YourMusicScreen()
                    } else {
                        AppleMusicPlayScreen()
                    }
                }
                .quickSourceSwitch()
                .playDestinations()
                .motifDestinations()
            }
            .environment(\.openPlayRoute, OpenPlayRouteAction(stack: "play") { navigator.show($0) })
        case .history:
            NavigationStack { HistoryScreen().motifDestinations() }
        case .charts:
            NavigationStack { ChartsScreen().motifDestinations() }
        }
    }

    /// After Now Playing closes: onto the Play tab's stack, or Summary's for your stats.
    private func go(to destination: NowPlayingDestination) {
        switch destination {
        case .play(let route):
            model.selectedTab = .play
            model.playNavigator.show(route)
        case .stats(let route):
            model.selectedTab = .summary
            summaryPath.append(route)
        }
    }
}
