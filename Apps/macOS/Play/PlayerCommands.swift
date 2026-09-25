import SwiftUI
import MotifCore

/// Opens the full player over the window.
struct OpenFullPlayerAction {
    let run: @MainActor () -> Void

    @MainActor
    func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var openFullPlayer = OpenFullPlayerAction {}
}

/// What the frontmost main window can do for the Controls menu: its panel and its full player
/// belong to the window, not the app.
struct PlayerWindowActions {
    var showsPanel: Bool
    var panelPage: PlayerPanelPage
    var showsFullPlayer: Bool
    let showPanel: @MainActor (PlayerPanelPage) -> Void
    let toggleFullPlayer: @MainActor () -> Void
    let goToCurrentSong: @MainActor () -> Void
    let beginSearch: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var playerWindow: PlayerWindowActions?
}

extension View {
    /// Publishes the window's player actions to the menu bar.
    func playerCommands(
        showsPanel: Binding<Bool>,
        panelPage: Binding<PlayerPanelPage>,
        showsFullPlayer: Binding<Bool>,
        goToCurrentSong: @escaping @MainActor () -> Void,
        beginSearch: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(PlayerCommandsModifier(showsPanel: showsPanel, panelPage: panelPage, showsFullPlayer: showsFullPlayer, goToCurrentSong: goToCurrentSong, beginSearch: beginSearch))
    }
}

private struct PlayerCommandsModifier: ViewModifier {
    @Binding var showsPanel: Bool
    @Binding var panelPage: PlayerPanelPage
    @Binding var showsFullPlayer: Bool
    let goToCurrentSong: @MainActor () -> Void
    let beginSearch: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.playerWindow, PlayerWindowActions(
                showsPanel: showsPanel,
                panelPage: panelPage,
                showsFullPlayer: showsFullPlayer,
                showPanel: { page in
                    if showsPanel, panelPage == page {
                        showsPanel = false
                    } else {
                        panelPage = page
                        showsPanel = true
                    }
                },
                toggleFullPlayer: { showsFullPlayer.toggle() },
                goToCurrentSong: goToCurrentSong,
                beginSearch: beginSearch
            ))
            .environment(\.openFullPlayer, OpenFullPlayerAction { showsFullPlayer = true })
    }
}

/// The Controls menu: everything the player does, with Music's shortcuts. And Search, in the
/// Edit menu where people look for Find.
struct ControlsCommands: Commands {
    let player: PlayerModel
    @FocusedValue(\.playerWindow) private var window
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PlayPreferences.motifRadioKey) private var isRadioOn = true

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            // ⌥⌘F, as the search of everything: ⌘F stays Find, for the text in front.
            Button("Search", systemImage: "magnifyingglass") { window?.beginSearch() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(window == nil)
        }

        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause" : "play") {
                player.togglePlayPause()
            }
            .disabled(!player.hasQueue)

            Button("Next", systemImage: "forward") { player.skipToNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!player.hasQueue)

            Button("Previous", systemImage: "backward") { player.skipToPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!player.hasQueue || player.context?.isStation == true)

            Button("Go to Current Song", systemImage: "arrow.forward.circle") { window?.goToCurrentSong() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!player.hasQueue || window == nil)

            Divider()

            Toggle(isOn: Binding(get: { player.isShuffled }, set: { _ in player.toggleShuffle() })) {
                Label("Shuffle", systemImage: "shuffle")
            }
            .disabled(!canReorder)

            Picker(selection: Binding(get: { player.repeatMode }, set: { player.setRepeat($0) })) {
                Text("Off").tag(PlayerRepeat.off)
                Text("All").tag(PlayerRepeat.all)
                Text("One").tag(PlayerRepeat.one)
            } label: {
                Label("Repeat", systemImage: "repeat")
            }
            .disabled(!canReorder)

            Menu {
                SleepTimerItems(player: player)
            } label: {
                Label("Sleep Timer", systemImage: "moon.zzz")
            }
            .disabled(!player.hasQueue)

            Divider()

            Button("Play Motif Radio", systemImage: "dot.radiowaves.left.and.right") { player.playMotifRadio() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!isRadioOn)

            // The iPhone's shake, for the Mac.
            Button("Play Something New", systemImage: "sparkles") {
                Task { await player.playSomethingNew() }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button(isShowing(.upNext) ? "Hide Up Next" : "Show Up Next", systemImage: "list.bullet") {
                window?.showPanel(.upNext)
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(!player.hasQueue || window == nil)

            Button(isShowing(.history) ? "Hide Your History" : "Show Your History", systemImage: "clock.arrow.circlepath") {
                window?.showPanel(.history)
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            .disabled(!player.hasQueue || window == nil)

            Button(window?.showsFullPlayer == true ? "Exit Full Player" : "Full Player", systemImage: "arrow.up.left.and.arrow.down.right") {
                window?.toggleFullPlayer()
            }
            // Music's shortcut. ⌃⌘F is the window's own Enter Full Screen.
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!player.hasQueue || window == nil)

            Button("Mini Player", systemImage: "rectangle.inset.bottomright.filled") {
                openWindow(id: MiniPlayerWindow.id)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!player.hasQueue)
        }
    }

    /// A station or a live mix picks as it goes: there's no order to shuffle or end to repeat.
    private var canReorder: Bool {
        player.hasQueue && player.context?.isStation != true && !player.isLive
    }

    private func isShowing(_ page: PlayerPanelPage) -> Bool {
        window?.showsPanel == true && window?.panelPage == page
    }
}
