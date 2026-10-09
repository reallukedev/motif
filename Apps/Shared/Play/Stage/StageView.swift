import SwiftUI
import TracksCore
#if os(macOS)
import AppKit
#endif

/// Stage: the song on a screen of its own, for a desk, a TV or a party. The cover, the song's
/// name and a visualizer over one of Now Playing's backgrounds, laid out one of four ways, and
/// nothing else until you want it: a tap, or a click on the Mac, brings up the controls, and
/// another puts them away. They stay until then, so they never go while you reach for them.
struct StageView: View {
    let onClose: () -> Void
    @Environment(PlayerModel.self) private var player
    @AppStorage(StageLayout.storageKey) private var layout = StageLayout.cover
    @AppStorage(StageVisualizer.storageKey) private var visualizer = StageVisualizer.bars
    @AppStorage(StageOption.background) private var background = StageBackground.flow
    @AppStorage(StageOption.showsAlbum) private var showsAlbum = true
    @AppStorage(StageOption.showsProgress) private var showsProgress = true
    @AppStorage(StageOption.showsNext) private var showsNext = true
    @AppStorage(StageOption.showsClock) private var showsClock = false
    @AppStorage(StageOption.keepsScreenOn) private var keepsScreenOn = true
    @AppStorage(StageOrientation.storageKey) private var orientation = StageOrientation.landscape
    @AppStorage(StageOption.hintsShown) private var hintsShown = 0
    @State private var showsHint = false
    @State private var tint: Color?
    @State private var levels = SmoothedLevels()
    @State private var palette: [Color] = []
    @State private var showsControls = LaunchScene.opensStageControls
    @State private var customizing = LaunchScene.opensStageCustomizer
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            StageBackdrop(
                style: background,
                cover: player.current?.cover,
                tint: tint,
                palette: palette,
                levels: levels,
                energy: songEnergy(player.current),
                isPlaying: player.isPlaying
            )
                .overlay(Color.black.opacity(player.isPlaying ? 0 : 0.3))
                .animation(.easeInOut(duration: 0.8), value: player.isPlaying)
                .ignoresSafeArea()
            Group {
                if let track = player.current {
                    GeometryReader { proxy in
                        // Each song blurs into the next.
                        stage(track, in: proxy.size)
                            .id(track.id)
                            .transition(.blurReplace)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .modifier(PixelShift(isOn: keepsScreenOn))
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note", description: Text("Play something, and it shows here."))
                }
            }
            .foregroundStyle(.white)
            controls
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
            if showsHint {
                hint.transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .coverTint(of: player.current?.cover, into: $tint)
        .task(id: player.current?.cover) {
            guard let cover = player.current?.cover else { return }
            let found = await CoverTint.palette(for: cover)
            if !Task.isCancelled { palette = found }
        }
        .animation(.easeInOut(duration: 0.3), value: showsControls)
        .animation(.smooth(duration: 0.5), value: layout)
        .animation(.smooth(duration: 0.5), value: player.current?.id)
        .contentShape(.rect)
        .onTapGesture(perform: toggleControls)
        #if os(iOS)
        .statusBarHidden(!showsControls)
        .persistentSystemOverlays(.hidden)
        .onChange(of: keepsScreenOn, initial: true) { _, isOn in
            UIApplication.shared.isIdleTimerDisabled = isOn
        }
        .onChange(of: orientation) { StagePresenter.shared.updateOrientation() }
        .onAppear { StagePresenter.shared.updateOrientation() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            StagePresenter.shared.updateOrientation()
        }
        .sheet(isPresented: $customizing) {
            StageCustomizer()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        #else
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space) { player.togglePlayPause(); return .handled }
        .onKeyPress(.rightArrow) { player.skipToNext(); return .handled }
        .onKeyPress(.leftArrow) { player.skipToPrevious(); return .handled }
        .onExitCommand(perform: onClose)
        #endif
        .onAppear {
            AudioLevelMeter.shared.startListening()
            if !showsControls { showHintIfNew() }
        }
        .onDisappear { AudioLevelMeter.shared.stopListening() }
    }

    // MARK: - The four layouts

    @ViewBuilder
    private func stage(_ track: PlayerTrack, in size: CGSize) -> some View {
        switch layout {
        case .cover: coverLayout(track, in: size)
        case .poster: posterLayout(track, in: size)
        case .visualizer: visualizerLayout(track, in: size)
        case .clock: clockLayout(track, in: size)
        }
    }

    /// The cover beside the song's name when there's width for it, above it when there isn't.
    private func coverLayout(_ track: PlayerTrack, in size: CGSize) -> some View {
        let wide = size.width > size.height * 1.1
        let side = wide ? min(size.height * 0.6, size.width * 0.4) : min(size.width * 0.82, size.height * 0.46)
        let layout = wide ? AnyLayout(HStackLayout(spacing: side * 0.14)) : AnyLayout(VStackLayout(spacing: 28))
        return VStack(spacing: 0) {
            topCorner
            Spacer(minLength: 0)
            layout {
                ZStack {
                    if visualizer == .orb {
                        visualizerView(track).frame(width: side * 1.7, height: side * 1.7)
                    }
                    CoverImage(cover: track.cover, size: side)
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
                }
                .frame(width: side, height: side)
                details(track, alignment: wide ? .leading : .center, size: min(size.width * (wide ? 0.045 : 0.09), 64), eyebrow: player.context?.title)
                    .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
            }
            Spacer(minLength: 0)
            if visualizer == .bars || visualizer == .wave {
                visualizerView(track).frame(height: max(size.height * 0.16, 64))
                    .padding(.bottom, 20)
            }
            footer(track)
        }
    }

    /// The song's name set huge, bottom left, over the background: a gig poster.
    private func posterLayout(_ track: PlayerTrack, in size: CGSize) -> some View {
        let wide = size.width > size.height
        let type = min(size.width * (wide ? 0.11 : 0.15), size.height * (wide ? 0.2 : 0.15))
        return VStack(alignment: .leading, spacing: 0) {
            // Upright, the cover sits at the top; on its side there's no height to spare, so
            // it goes beside the name instead.
            HStack(alignment: .top) {
                if !wide {
                    CoverImage(cover: track.cover, size: min(96, size.width * 0.18))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                }
                Spacer()
                if showsClock { clock(size: 28) }
            }
            Spacer(minLength: 0)
            if visualizer != .off {
                visualizerView(track)
                    .frame(height: size.height * (visualizer == .orb ? 0.34 : wide ? 0.2 : 0.26))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
            HStack(spacing: 12) {
                if wide {
                    CoverImage(cover: track.cover, size: max(28, type * 0.5))
                }
                Text(track.artistName.uppercased())
                    .font(.system(size: max(15, type * 0.28), weight: .semibold))
                    .tracking(2)
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Text(track.title)
                .font(.system(size: type, weight: .heavy))
                .tracking(-type * 0.02)
                .lineLimit(3)
                .minimumScaleFactor(0.4)
                .padding(.top, 2)
            if showsAlbum, let album = track.albumTitle {
                Text(album)
                    .font(.system(size: max(15, type * 0.26), weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
            footer(track)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The visualizer at the centre: an orb around the cover, or the bars or wave large, with
    /// the song under it.
    private func visualizerLayout(_ track: PlayerTrack, in size: CGSize) -> some View {
        let side = min(size.width, size.height * 0.62)
        return VStack(spacing: 0) {
            topCorner
            Spacer(minLength: 0)
            switch visualizer {
            case .orb:
                ZStack {
                    visualizerView(track)
                    CoverImage(cover: track.cover, size: side * 0.54, isCircle: true)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                }
                .frame(width: side, height: side)
            case .bars, .wave:
                visualizerView(track).frame(height: size.height * 0.42)
            case .off:
                CoverImage(cover: track.cover, size: side * 0.8)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            }
            Spacer(minLength: 0)
            details(track, alignment: .center, size: min(size.width * (size.width > size.height ? 0.05 : 0.085), 48))
            footer(track)
                .padding(.top, 24)
        }
    }

    /// The time, as StandBy shows it, with the song and a small visualizer under it.
    private func clockLayout(_ track: PlayerTrack, in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: min(size.width * 0.24, size.height * 0.34), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title2.weight(.semibold))
                        .opacity(0.7)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                CoverImage(cover: track.cover, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(track.artistName).font(.body).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 12)
                if visualizer != .off {
                    visualizerView(track, style: visualizer == .orb ? .bars : visualizer)
                        .frame(width: min(220, size.width * 0.3), height: 48)
                }
            }
            footer(track)
                .padding(.top, 20)
        }
    }

    // MARK: - Pieces

    private func details(_ track: PlayerTrack, alignment: HorizontalAlignment, size: CGFloat, eyebrow: String? = nil) -> some View {
        let textAlignment: TextAlignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: size * 0.14) {
            // Where it's playing from, as Now Playing says it.
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: max(12, size * 0.3), weight: .semibold))
                    .tracking(1.5)
                    .opacity(0.6)
                    .lineLimit(1)
            }
            Text(track.title)
                .font(.system(size: size, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(track.artistName)
                .font(.system(size: size * 0.6, weight: .medium))
                .opacity(0.8)
                .lineLimit(1)
            if showsAlbum, let album = track.albumTitle {
                Text(album)
                    .font(.system(size: size * 0.45))
                    .opacity(0.6)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(textAlignment)
    }

    /// The clock in the top corner, for the layouts that aren't one.
    @ViewBuilder
    private var topCorner: some View {
        if showsClock {
            HStack {
                Spacer()
                clock(size: 24)
            }
        }
    }

    private func clock(size: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(0.85)
        }
    }

    /// How far into the song, and what's next, along the bottom.
    @ViewBuilder
    private func footer(_ track: PlayerTrack) -> some View {
        let next = showsNext ? player.upNext.first : nil
        if showsProgress || next != nil || !player.isPlaying {
            VStack(alignment: .leading, spacing: 10) {
                if showsProgress, let duration = track.duration, duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let fraction = min(1, max(0, player.playbackTime / duration))
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.2))
                                Capsule().fill(.white.opacity(0.75)).frame(width: proxy.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                HStack(spacing: 10) {
                    if !player.isPlaying {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: .capsule)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    if let next {
                        Text("Next: \(next.title) · \(next.artistName)")
                            .font(.callout.weight(.medium))
                            .opacity(0.7)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.3), value: player.isPlaying)
            }
        }
    }

    private func visualizerView(_ track: PlayerTrack, style: StageVisualizer? = nil) -> some View {
        StageVisualizerView(style: style ?? visualizer, palette: palette, energy: songEnergy(track), isPlaying: player.isPlaying, levels: levels)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                controlButton("Close Stage", symbol: "xmark", action: onClose)
                Spacer()
                #if os(iOS)
                controlButton(orientation == .portrait ? "Turn to Landscape" : "Turn to Portrait", symbol: "rectangle.portrait.rotate") {
                    orientation = orientation == .portrait ? .landscape : .portrait
                }
                RoutePicker()
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                #endif
                controlButton("Customize", symbol: "slider.horizontal.3") { customizing.toggle() }
                    #if os(macOS)
                    .popover(isPresented: $customizing, arrowEdge: .bottom) {
                        StageCustomizer().frame(width: 360, height: 520)
                    }
                    #endif
            }
            Spacer()
            if let track = player.current {
                VStack(spacing: 18) {
                    if let duration = track.duration, duration > 0, !player.isLive, player.context?.isStation != true {
                        Scrubber(duration: duration, isPlaying: player.isPlaying, time: { player.playbackTime }, track: track) { time in
                            player.seek(to: time)
                        }
                    } else {
                        LiveScrubber()
                    }
                    PlayerTransport()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 560)
                .glassEffect(.regular, in: .rect(cornerRadius: 34))
                // A tap that just misses a button stays on the panel, rather than putting
                // the controls away from under the finger.
                .contentShape(.rect(cornerRadius: 34))
                .onTapGesture {}
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background {
            // A little shade top and bottom, so the controls read over any cover.
            LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func controlButton(_ label: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    /// A word about the controls the first few times Stage opens, since at first it shows none.
    private var hint: some View {
        Group {
            #if os(iOS)
            Text("Tap to show controls")
            #else
            Text("Click to show controls")
            #endif
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Around the words alone: around the whole height, it was a pillar of glass.
        .glassEffect(.regular, in: .capsule)
        // At the top, where the system says how to leave full screen, and clear of the
        // progress and what's next along the foot.
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func showHintIfNew() {
        guard hintsShown < 3 else { return }
        hintsShown += 1
        showsHint = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.6)) { showsHint = false }
        }
    }

    /// A tap or click anywhere but on a control shows the controls, or puts them away. Not
    /// while Stage is being customized, which keeps them up behind it.
    private func toggleControls() {
        guard !customizing else { return }
        showsHint = false
        showsControls.toggle()
        #if os(macOS)
        // Put away, they take the pointer with them until it's moved.
        if !showsControls { NSCursor.setHiddenUntilMouseMoves(true) }
        #endif
    }
}

/// Moves what's on Stage a few points over the minutes, too slowly to see, so a screen kept on
/// for hours doesn't keep the same picture burned in one place.
private struct PixelShift: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content
                .offset(x: isOn ? 8 * sin(time / 311) : 0, y: isOn ? 6 * cos(time / 409) : 0)
                .animation(.easeInOut(duration: 20), value: time)
        }
    }
}
