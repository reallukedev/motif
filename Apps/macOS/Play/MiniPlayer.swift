import SwiftUI
import MotifCore

/// Music's Mini Player: the cover alone in a small window that stays above the others, with
/// the song and its controls over it while the pointer is there.
struct MiniPlayerWindow: Scene {
    static let id = "mini-player"
    let model: AppModel

    var body: some Scene {
        Window("Mini Player", id: Self.id) {
            if let capture = model.capture {
                MiniPlayer()
                    .environment(model)
                    .environment(model.player)
                    .environment(model.playFeed)
                    .environment(model.yourMusic)
                    .environment(capture)
                    .environment(\.openPlayRoute, OpenPlayRouteAction(stack: "miniPlayer") { route in
                        // Pages open in the main window, brought forward for them.
                        model.playNavigator.show(route)
                        NSApp.activate(ignoringOtherApps: true)
                        MainWindow.open?.makeKeyAndOrderFront(nil)
                    })
            }
        }
        // No title bar at all: the cover is the whole window, dragged anywhere by its cover.
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.bottomTrailing)
        .restorationBehavior(.disabled)
    }
}

private struct MiniPlayer: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var isHovering = false
    @State private var nextPresses = 0
    @State private var previousPresses = 0
    @State private var tint: Color?

    static let side: CGFloat = 300
    static let cornerRadius: CGFloat = 14
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack(alignment: .bottom) {
            if let track = player.current {
                CoverImage(cover: track.cover, size: Self.side, isBare: true)
                // Always there, so VoiceOver and the keyboard can reach them; shown while the
                // pointer is over the window, or the music is paused.
                controls(track)
                    .opacity(showsControls ? 1 : 0)
                    .allowsHitTesting(showsControls)
            } else {
                nothingPlaying
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(NowPlayingBackdrop(cover: player.current?.cover, tint: tint, isPlaying: player.isPlaying))
        .clipShape(.rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .coverTint(of: player.current?.cover, into: $tint)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .focusable()
        .focusEffectDisabled()
        .contextMenu {
            if let track = player.current {
                Button(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause" : "play") { player.togglePlayPause() }
                Button("Next", systemImage: "forward") { player.skipToNext() }
                Button("Previous", systemImage: "backward") { player.skipToPrevious() }
                    .disabled(player.context?.isStation == true)
                Divider()
                NowPlayingMenuItems(track: track)
            }
            Divider()
            Button("Close Mini Player", systemImage: "xmark") { dismissWindow(id: MiniPlayerWindow.id) }
        }
    }

    private var showsControls: Bool {
        isHovering || !player.isPlaying || voiceOver
    }

    private func controls(_ track: PlayerTrack) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                PlayCountLine(track: track, showsSince: false)
                    .font(.caption)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button {
                    previousPresses += 1
                    player.skipToPrevious()
                } label: {
                    SkipArrows(direction: .backward, height: 14, trigger: previousPresses)
                }
                .buttonStyle(BarIconButtonStyle(diameter: 36))
                .disabled(player.context?.isStation == true)
                .accessibilityLabel("Previous")

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
                .buttonStyle(BarIconButtonStyle(diameter: 44))
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button {
                    nextPresses += 1
                    player.skipToNext()
                } label: {
                    SkipArrows(direction: .forward, height: 14, trigger: nextPresses)
                }
                .buttonStyle(BarIconButtonStyle(diameter: 36))
                .accessibilityLabel("Next")
            }

            if let duration = track.duration, duration > 0 {
                BarScrubber(duration: duration, showsTimes: false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    private var nothingPlaying: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nothing Playing")
                .font(.headline)
            Button("Play Motif Radio", systemImage: "dot.radiowaves.left.and.right") { player.playMotifRadio() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}
