import SwiftUI
import Observation
import MotifCore
import MotifMusic

/// Everything the app needs at launch, built once and shared by every scene.
@MainActor
@Observable
final class AppModel {
    /// The real store. `nil` only if it couldn't be opened at all.
    let store: MotifStore?
    let capture: CaptureService?
    let playback: PlaybackController?
    let startupError: String?

    /// True when launched with `-MotifDemoData YES`. The real store is never opened, so a
    /// screenshot session can't touch anyone's history, iCloud or Last.fm.
    let isDemoLaunch: Bool

    /// An in-memory store full of made-up listening, when the person asked to look around
    /// before they have any history of their own.
    private(set) var sampleStore: MotifStore?

    let library = Library()

    /// The Mac sidebar selection. Lives here so menu commands can change it.
    var sidebarSelection: SidebarItem? = LaunchScene.sidebar.flatMap(SidebarItem.init(rawValue:)) ?? .summary

    init() {
        isDemoLaunch = DemoMode.isRequestedAtLaunch
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
        } catch {
            self.store = nil
            self.capture = nil
            self.playback = nil
            self.startupError = error.localizedDescription
        }
    }

    /// The store the windows should show: sample data while it's on, otherwise the real one.
    var activeStore: MotifStore? { sampleStore ?? store }

    /// Whether Summary has a banner to show: sample data the person chose, or a store that
    /// fell back to memory.
    var hasBanner: Bool {
        if sampleStore != nil { return true }
        if !isDemoLaunch, case .inMemory = store?.backing { return true }
        return false
    }

    /// Anything showing made-up data. Playback, deleting and Last.fm are switched off.
    var isShowingSampleData: Bool { isDemoLaunch || sampleStore != nil }

    /// Starts capture and catches up on anything missed while the app was closed. Does
    /// nothing in a demo launch.
    func startCapture() async {
        guard !isDemoLaunch, let capture else { return }
        capture.start()
        await capture.catchUp()
    }

    func showSampleData() {
        guard sampleStore == nil else { return }
        sampleStore = try? DemoMode.makeStore()
    }

    func hideSampleData() {
        sampleStore = nil
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
}
