import SwiftUI
import MotifCore

/// Music's full-screen player, over the whole window: the cover large on a field of its own
/// colour, the song and your count beside it, and the transport under them. Click the cover,
/// or Your History, and the sleeve turns over to your history with the song. Escape, or the
/// chevron, goes back to the window.
struct FullPlayer: View {
    let close: () -> Void
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openPlayRoute) private var openPlayRoute
    @State private var showsBack = LaunchScene.opensSleeve
    @State private var showsUpNext = false
    @State private var tint: Color?

    var body: some View {
        ZStack {
            NowPlayingBackdrop(cover: player.current?.cover, tint: tint, isPlaying: player.isPlaying)
                .ignoresSafeArea()
            if let track = player.current {
                content(track)
                    .environment(\.colorScheme, .dark)
                    .foregroundStyle(.white)
                    // What's on lights white on the cover's colour, as on the iPhone's.
                    .tint(.white)
            }
        }
        .coverTint(of: player.current?.cover, into: $tint)
        .onChange(of: player.current?.songIdentity) { showsBack = false }
        .onExitCommand(perform: close)
    }

    private func content(_ track: PlayerTrack) -> some View {
        VStack(spacing: 0) {
            topBar(track)
            GeometryReader { proxy in
                // The cover as big as the window allows, leaving the column beside it its
                // width and the top bar its height.
                let side = max(220, min(480, proxy.size.height - 40, proxy.size.width - Self.column - Self.gap - 96))
                HStack(alignment: .center, spacing: Self.gap) {
                    sleeve(track, side: side)
                    Group {
                        if showsUpNext {
                            upNext
                        } else {
                            details(track)
                        }
                    }
                    .frame(width: Self.column)
                    .frame(minHeight: side)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    private static let column: CGFloat = 380
    private static let gap: CGFloat = 56

    // MARK: - Top bar

    private func topBar(_ track: PlayerTrack) -> some View {
        ZStack {
            if let context = player.context {
                VStack(spacing: 1) {
                    Text(context.isStation ? "Playing from Radio" : "Playing From")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(player.isRadioDriving ? "\(Image(systemName: "car.fill")) \(context.title) · Driving" : "\(context.title)")
                        .font(.headline)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Button("Exit Full Player", systemImage: "chevron.down", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(BarIconButtonStyle(diameter: 34))
                    .keyboardShortcut(.cancelAction)
                    .help("Exit Full Player (Esc)")
                Spacer()
                Menu("More", systemImage: "ellipsis") {
                    NowPlayingMenuItems(track: track) { destination in
                        close()
                        switch destination {
                        case .play(let route): openPlayRoute(route)
                        case .stats(let route): openPlayRoute(.stats(route))
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.button)
                .buttonStyle(BarIconButtonStyle(diameter: 34))
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - The sleeve

    private func sleeve(_ track: PlayerTrack, side: CGFloat) -> some View {
        // Music's gesture: the cover sinks back while paused.
        let sinks = !player.isPlaying && !reduceMotion && !showsBack
        return SleeveFlip(showsBack: showsBack) {
            Button {
                showsBack = true
            } label: {
                CoverImage(cover: track.cover, size: side)
            }
            .buttonStyle(.plain)
            .help("Your History with This Song")
            .accessibilityLabel("Your history with this song")
        } back: {
            LinerNotes(track: track, fillsCard: true) {
                close()
                openPlayRoute(.stats(.song(track.songIdentity)))
            }
            .padding(32)
            .frame(width: side, height: side, alignment: .topLeading)
            .background(.white.opacity(0.1), in: .rect(cornerRadius: CoverImage.radius(for: side), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoverImage.radius(for: side), style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            // A click anywhere on the back but its button turns it face up again.
            .contentShape(.rect(cornerRadius: CoverImage.radius(for: side), style: .continuous))
            .onTapGesture { showsBack = false }
            .help("Show the Cover")
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Show the Cover") { showsBack = false }
        }
        .shadow(color: .black.opacity(sinks ? 0.2 : 0.4), radius: sinks ? 14 : 30, y: sinks ? 6 : 16)
        .scaleEffect(sinks ? 0.88 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.2), value: sinks)
    }

    // MARK: - Details

    private func details(_ track: PlayerTrack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)
                    if track.isExplicit {
                        ExplicitBadge()
                    }
                }
                Text(track.artistName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                PlayCountLine(track: track)
                    .font(.title3)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 24)

            if let duration = track.duration, duration > 0 {
                Scrubber(duration: duration, isPlaying: player.isPlaying, time: { player.playbackTime }, format: track.local?.format) { time in
                    player.seek(to: time)
                }
            } else {
                LiveScrubber()
            }

            PlayerTransport()
                .padding(.top, 20)

            secondaryControls
                .padding(.top, 24)
            Spacer(minLength: 0)
        }
    }

    private var secondaryControls: some View {
        HStack(spacing: 6) {
            if player.context?.isStation != true, !player.isLive {
                Button("Shuffle", systemImage: "shuffle") { player.toggleShuffle() }
                    .buttonStyle(BarIconButtonStyle(diameter: 36, isOn: player.isShuffled))
                    .help("Shuffle")
                Button("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat") { player.cycleRepeat() }
                    .buttonStyle(BarIconButtonStyle(diameter: 36, isOn: player.repeatMode != .off))
                    .help("Repeat")
            }
            Menu("Sleep Timer", systemImage: player.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill") {
                SleepTimerItems(player: player)
            }
            .labelStyle(.iconOnly)
            .menuStyle(.button)
            .buttonStyle(BarIconButtonStyle(diameter: 36, isOn: player.sleepTimer != nil))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sleep Timer")
            Spacer()
            Button("Your History", systemImage: "clock.arrow.circlepath") { showsBack.toggle() }
                .buttonStyle(BarIconButtonStyle(diameter: 36, isOn: showsBack))
                .help("Your History (⌥⌘Y)")
            RoutePickerButton()
                .frame(width: 36, height: 36)
                .help("AirPlay")
            Button("Up Next", systemImage: "list.bullet") {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showsUpNext.toggle() }
            }
            .buttonStyle(BarIconButtonStyle(diameter: 36, isOn: showsUpNext))
            .help("Up Next")
        }
        .labelStyle(.iconOnly)
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up Next")
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showsUpNext = false }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            UpNextList()
                // Go to Album and the like leave the full player for the page they open.
                .environment(\.openPlayRoute, OpenPlayRouteAction(stack: "fullPlayer") { route in
                    close()
                    openPlayRoute(route)
                })
        }
    }
}
