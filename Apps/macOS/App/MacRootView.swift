import SwiftUI
import MotifCore

/// The main window: sidebar on the left, the chosen view on the right.
struct MacRootView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var path = NavigationPath(LaunchScene.route.map { [$0] } ?? [])
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let store = model.store, let capture = model.capture, let playback = model.playback {
            NavigationSplitView {
                List(selection: $model.sidebarSelection) {
                    Section {
                        sidebarRow(.summary)
                        sidebarRow(.history)
                    }
                    Section("Top Charts") {
                        sidebarRow(.topSongs)
                        sidebarRow(.topArtists)
                        sidebarRow(.topAlbums)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            } detail: {
                NavigationStack(path: $path) {
                    detail
                        .motifDestinations()
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Songs, Artists and Albums")
            .onChange(of: model.sidebarSelection) {
                path = NavigationPath()
                query = ""
            }
            // Initial too, for a window the request itself had to open.
            .onChange(of: model.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                query = ""
                path = NavigationPath([route])
                model.pendingRoute = nil
            }
            .opensDeepLinks(in: model)
            .observesLibrary(model.library)
            .modelContainer(store.container)
            .environment(model)
            .environment(capture)
            .environment(playback)
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

    @ViewBuilder
    private var detail: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsList(query: query)
                .navigationTitle("Search")
        } else {
            switch model.sidebarSelection ?? .summary {
            case .summary: MacSummaryView()
            case .history: MacHistoryView()
            case .topSongs: TopChartView(kind: .songs)
            case .topArtists: TopChartView(kind: .artists)
            case .topAlbums: TopChartView(kind: .albums)
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}
