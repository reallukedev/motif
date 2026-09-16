import SwiftUI
import MotifCore

struct MotifApp: App {
    /// Holds the model, the Dock behaviour and the player monitor, and starts them at launch
    /// whether or not a window opens.
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the menu bar extra is shown. `@AppStorage` because `MenuBarExtra` doesn't
    /// re-render on a `@State` change in the `App`, and SwiftUI writes `false` back here if
    /// the user drags the icon out.
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var menuBarArtwork = MenuBarArtwork()

    private var model: AppModel { appDelegate.model }
    private var behaviour: MacAppBehaviour { appDelegate.behaviour }
    private var monitor: NowPlayingMonitor { appDelegate.monitor }

    /// Mirrored into `@AppStorage` so the status item redraws when the setting changes.
    /// SwiftUI can't observe `CaptureSettings`.
    @AppStorage(CaptureSettings.menuBarLabelStyleKey, store: CaptureSettings.sharedDefaults) private var menuBarLabelStyleRaw =
        MenuBarLabelStyle.default.rawValue
    @AppStorage(CaptureSettings.menuBarLabelFormatKey, store: CaptureSettings.sharedDefaults) private var menuBarLabelFormat =
        MenuBarLabelFormat.default
    @AppStorage(CaptureSettings.animatesMenuBarKey, store: CaptureSettings.sharedDefaults) private var animatesMenuBar = true

    /// The cover for the song the label is naming, or nil if it has none yet.
    ///
    /// Not `nowPlaying?.artworkURL ?? lastCapture?.artworkURL`: while a new song's artwork
    /// is still being looked up, that would put the previous song's cover next to the new
    /// title. Only fall back to `lastCapture` when nothing is playing, as the label does.
    private var menuBarArtworkURL: String? {
        guard let capture = model.capture else { return nil }
        if capture.nowPlaying != nil { return capture.nowPlaying?.artworkURL }
        return capture.lastCapture?.artworkURL
    }

    private var menuBarLabelStyle: MenuBarLabelStyle {
        MenuBarLabelStyle(stored: menuBarLabelStyleRaw)
    }

    var body: some Scene {
        WindowGroup("Motif", id: "main") {
            MacRootView(model: model)
                .environment(behaviour)
                .frame(minWidth: 820, minHeight: 560)
                // "Open Motif" makes the app `.regular` to bring the window forward. Once the
                // last main window has gone, hide the Dock icon again if that's the setting.
                .tracksMainWindow { [behaviour] in behaviour.applyActivationPolicy() }
        }
        .defaultSize(width: 1180, height: 800)
        .commands { MotifCommands(model: model) }
        .onChange(of: scenePhase) { _, phase in
            // A Mac window can sit closed for days with the app still running, so coming
            // back to it is the moment to catch up with what the iPhone has been doing.
            guard phase == .active else { return }
            model.syncOnForeground()
        }

        #if DEBUG
        // The menu bar window can't be screenshotted, so this shows the same view in a normal
        // window. Opened with -MotifMenuBarPreview YES.
        Window("Menu Bar Preview", id: "menubar-preview") {
            MenuBarContent(model: model, monitor: monitor)
                .environment(behaviour)
        }
        .windowResizability(.contentSize)
        #endif

        Settings {
            MacSettingsView(model: model)
                .modelContainer(for: model.store)
                .environment(behaviour)
        }

        // `isInserted:` is the only way to toggle this at runtime. SceneBuilder has no
        // buildEither, and its buildOptional only takes availability checks.
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent(model: model, monitor: monitor)
                .environment(behaviour)
        } label: {
            MenuBarLabel(
                nowPlaying: model.capture?.nowPlaying,
                lastCapture: model.capture?.lastCapture,
                isCapturing: model.capture?.isRunning == true,
                isPlaying: model.capture?.isSomethingPlaying,
                style: menuBarLabelStyle,
                format: menuBarLabelFormat,
                animates: animatesMenuBar
            )
            .environment(menuBarArtwork)
            .task(id: "\(menuBarArtworkURL ?? "")|\(menuBarLabelStyleRaw)") {
                menuBarArtwork.load(
                    menuBarArtworkURL,
                    // Only when a title follows, so a lone cover stays centred.
                    trailingGap: menuBarLabelStyle == .artworkAndTitle || menuBarLabelStyle == .custom
                        ? MenuBarArtwork.trailingGap
                        : 0
                )
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu commands. Icons are forced on because macOS 27 hides menu item symbols by default.
struct MotifCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(SidebarItem.allCases) { item in
                Button(item.title, systemImage: item.symbol) {
                    model.sidebarSelection = item
                }
                .keyboardShortcut(item.shortcut, modifiers: .command)
                .labelStyle(.titleAndIcon)
            }
            Divider()
        }

        CommandGroup(after: .newItem) {
            Button("Check for Missed Songs", systemImage: "arrow.clockwise") {
                Task { await model.capture?.catchUp() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .labelStyle(.titleAndIcon)
            .disabled(model.isShowingSampleData)

            Divider()

            Button("Play Back Today", systemImage: "play.circle") {
                Task { await model.playback?.playBackToday() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .labelStyle(.titleAndIcon)
            .disabled(model.isShowingSampleData)

            Button("Save Current Radio Song", systemImage: "plus.circle") {
                Task { await model.capture?.captureCurrentSong() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .labelStyle(.titleAndIcon)
            .disabled(model.isShowingSampleData)
        }
    }
}

private extension View {
    /// The Settings scene is its own root, so it needs the container attached again or the
    /// station list comes up empty.
    @ViewBuilder
    func modelContainer(for store: MotifStore?) -> some View {
        if let store {
            modelContainer(store.container)
        } else {
            self
        }
    }
}
