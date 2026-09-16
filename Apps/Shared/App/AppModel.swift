import SwiftUI
import Observation
import MotifCore
import MotifMusic
import MusicKit

/// Everything the app needs at launch, built once and shared by every scene.
@MainActor
@Observable
final class AppModel {
    /// The real store. `nil` only if it couldn't be opened at all.
    let store: MotifStore?
    let capture: CaptureService?
    let playback: PlaybackController?
    let startupError: String?

    /// Mirrors settings and song statuses between the user's devices. Nil in a demo launch,
    /// which must not write anything of the user's to iCloud.
    let settingsSync: SettingsSync?

    /// Folds in the duplicate rows sync produces, as soon as they land rather than on the
    /// next turn of the housekeeping timer.
    let reconciler: SyncReconciler?

    /// Whether iCloud is actually taking this device's changes, which an open store doesn't
    /// prove. Nil in a demo launch.
    let syncMonitor: CloudSyncMonitor?

    /// True when launched with `-MotifDemoData YES`. The real store is never opened, so a
    /// screenshot session can't touch anyone's history, iCloud or Last.fm.
    let isDemoLaunch: Bool

    let library = Library()

    /// A page for the main window to open, asked for from outside it (the menu bar's
    /// "View Song Stats"). The window pushes it and clears it.
    var pendingRoute: Route?

    /// The Mac sidebar selection. Lives here so menu commands can change it.
    var sidebarSelection: SidebarItem? = LaunchScene.sidebar.flatMap(SidebarItem.init(rawValue:)) ?? .summary

    /// The iPhone's tab. Lives here so Summary's "See All" can move to Charts, which owns the
    /// full lists, instead of pushing a second copy inside Summary.
    var selectedTab: AppTab = AppTab(launchName: LaunchScene.tab) ?? .summary

    /// Apple Music access, as last read. Summary and Settings explain what it's for and offer
    /// to ask, rather than the app asking out of nowhere at launch.
    private(set) var musicAuthorization: MusicAuthorization.Status = MusicAuthorization.currentStatus

    /// Whether ``startCapture()`` has run. Startup belongs to the process, not to a window:
    /// running it again for each new window would undo a paused capture and start a second
    /// demo feed.
    @ObservationIgnored private var hasStarted = false

    init() {
        isDemoLaunch = DemoMode.isRequestedAtLaunch
        // Listening before the store opens, since that is when the mirror reports setup.
        let syncMonitor = isDemoLaunch ? nil : CloudSyncMonitor()
        syncMonitor?.start()
        self.syncMonitor = syncMonitor
        do {
            let store = isDemoLaunch ? try DemoMode.makeStore() : try MotifStore.shared()
            // Start watching saves before anything writes. Not in a demo launch, which
            // mustn't open the real store.
            if !isDemoLaunch { _ = WidgetRefresher.shared }
            let capture = CaptureService(store: store)
            let playback = PlaybackController(store: store, service: PlatformPlaybackService.make())
            // The capture service decides when a station has stopped; the controller does
            // the playing. This is the one place that knows about both.
            capture.autoPlayback = { [weak playback] in await playback?.playBackToday() }
            self.store = store
            self.capture = capture
            self.playback = playback
            self.startupError = nil
            self.settingsSync = isDemoLaunch ? nil : SettingsSync.forCurrentBuild()
            self.reconciler = isDemoLaunch ? nil : SyncReconciler(store: store)
            // Starts the first read of the history now, in the background, so it's under way
            // before any screen asks for it.
            library.connect(to: store, looksUpCatalog: !isDemoLaunch)
        } catch {
            self.store = nil
            self.capture = nil
            self.playback = nil
            self.startupError = error.localizedDescription
            self.settingsSync = nil
            self.reconciler = nil
        }
    }

    /// Whether Summary has a banner to show: a store that fell back to memory.
    var hasBanner: Bool {
        if !isDemoLaunch, case .inMemory = store?.backing { return true }
        return false
    }

    /// Showing made-up data, which only a demo launch does. Playback, deleting and Last.fm
    /// are switched off.
    var isShowingSampleData: Bool { isDemoLaunch }

    /// Starts capture and catches up on anything missed while the app was closed. Runs once
    /// per process; later calls return straight away. Does nothing in a demo launch.
    func startCapture() async {
        guard !hasStarted else { return }
        hasStarted = true
        if isDemoLaunch, DemoMode.isLiveRequested, let store {
            await DemoMode.runLiveFeed(into: store)
        }
        guard !isDemoLaunch, let capture else { return }
        capture.start()
        // Before the catch-up, so settings another device changed are in force for the
        // captures it is about to make.
        settingsSync?.start()
        reconciler?.start()
        // Doesn't ask for Apple Music access: a prompt at launch arrives with no reason given.
        // Capture works without it. Catalog search, artwork, the playlist and Recently Played
        // fail with `permissionDenied` until it's granted, so the catch-up runs again then.
        await capture.catchUp()
    }

    /// Asks for Apple Music access. Only called from a control that has already said what
    /// the access is for.
    func requestMusicAccess() async {
        let previous = musicAuthorization
        musicAuthorization = await MusicAuthorization.request()
        catchUpIfNewlyAuthorized(since: previous)
    }

    /// Reads access again. It can be changed in Settings while Motif keeps running.
    func refreshMusicAuthorization() {
        let previous = musicAuthorization
        musicAuthorization = MusicAuthorization.currentStatus
        catchUpIfNewlyAuthorized(since: previous)
    }

    /// The launch catch-up couldn't reach Recently Played or the catalog without access, so
    /// it's worth another go the moment access arrives.
    private func catchUpIfNewlyAuthorized(since previous: MusicAuthorization.Status) {
        guard previous != .authorized, musicAuthorization == .authorized,
              hasStarted, !isDemoLaunch, let capture
        else { return }
        Task { await capture.catchUp() }
    }

    /// Catches up with iCloud when the app comes back to the front.
    ///
    /// Both sides go quiet while the app is away — iOS suspends it, and a Mac window can sit
    /// closed for days — so this is where the user is most likely to be looking at stale
    /// settings or at rows another device has already merged.
    func syncOnForeground() {
        guard !isDemoLaunch else { return }
        refreshMusicAuthorization()
        settingsSync?.reconcileAll()
        reconciler?.reconcile()
    }
}

/// The iPhone's tabs.
enum AppTab: String, Hashable {
    case summary, history, charts, search

    init?(launchName: String?) {
        guard let launchName else { return nil }
        self.init(rawValue: launchName)
    }
}

/// The Mac sidebar.
enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case summary
    case history
    case topSongs
    case topArtists
    case topAlbums

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .summary: "Summary"
        case .history: "History"
        case .topSongs: "Songs"
        case .topArtists: "Artists"
        case .topAlbums: "Albums"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "chart.bar.xaxis"
        case .history: "clock.arrow.circlepath"
        case .topSongs: "music.note"
        case .topArtists: "music.microphone"
        case .topAlbums: "square.stack"
        }
    }

    /// ⌘1 to ⌘5, in sidebar order.
    var shortcut: KeyEquivalent {
        switch self {
        case .summary: "1"
        case .history: "2"
        case .topSongs: "3"
        case .topArtists: "4"
        case .topAlbums: "5"
        }
    }

    var chart: ChartKind? {
        switch self {
        case .topSongs: .songs
        case .topArtists: .artists
        case .topAlbums: .albums
        case .summary, .history: nil
        }
    }

    /// The sidebar row that shows a chart, for Summary's "See All".
    init(chart: ChartKind) {
        switch chart {
        case .songs: self = .topSongs
        case .artists: self = .topArtists
        case .albums: self = .topAlbums
        }
    }
}
