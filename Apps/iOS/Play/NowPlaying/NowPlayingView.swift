import SwiftUI
import MusicKit
import MotifCore

/// The full player: one song, huge, on a field of its own colour, with the transport where the
/// thumb is. Music's Now Playing, plus what only Motif knows: how many times you've heard this,
/// counting up the moment it's kept, and, a double tap on the cover or the history button away,
/// the back of its sleeve with your whole history with it.
struct NowPlayingView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showsQueue = LaunchScene.opensQueue
    @State private var showsBack = LaunchScene.opensSleeve
    /// Turns of the sleeve, for the haptic: only the person turns it.
    @State private var turns = 0
    @State private var tint: Color?
    /// The heights of what stands above and below the cover, which grow with the text.
    @State private var topBarHeight: CGFloat = 0
    @State private var detailsHeight: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    /// Where to go once the cover has closed: Go to Album and the like.
    let onNavigate: (NowPlayingDestination) -> Void

    var body: some View {
        ZStack {
            background
            if let track = player.current {
                content(track)
                    .environment(\.colorScheme, .dark)
                    .foregroundStyle(.white)
                    // Music stops growing its player here too: past it, the song's own name
                    // no longer fits beside the cover and the controls.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .coverTint(of: player.current?.cover, into: $tint)
        .onChange(of: player.hasQueue) { _, hasQueue in
            if !hasQueue { dismiss() }
        }
        // A new song starts face up.
        .onChange(of: player.current?.songIdentity) { showsBack = false }
        .sensoryFeedback(.selection, trigger: turns)
        .playerFeedback()
    }

    // MARK: - Layout

    private func content(_ track: PlayerTrack) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { topBarHeight = $0 }
                if showsQueue {
                    QueueView(track: track)
                        .transition(.opacity)
                } else {
                    Spacer(minLength: 12)
                    sleeve(track, in: proxy)
                    Spacer(minLength: 20)
                    details(track)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { detailsHeight = $0 }
                }
                Spacer(minLength: 16)
                controls(track)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                if let context = player.context {
                    Text(context.isStation ? "Playing from Radio" : "Playing From")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(player.isRadioDriving ? "\(Image(systemName: "car.fill")) \(context.title) · Driving" : "\(context.title)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 56)
            .accessibilityElement(children: .combine)

            HStack {
                Button("Close", systemImage: "chevron.down") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    /// The cover, which turns over to your history with the song.
    private func sleeve(_ track: PlayerTrack, in proxy: GeometryProxy) -> some View {
        let available = proxy.size
        // Laid out once at no size at all as the player opens, then at the screen's. At the
        // larger text sizes the title and controls grow, and the cover gives them the room
        // rather than push the bottom row off the screen: what's left once they and the
        // spaces between them (12, 20, 16 and the 8 below) have theirs. The bottom row may sit
        // down by the home indicator, as it does at the default size, but no lower.
        let share = verticalSizeClass == .compact ? 0.5 : 0.44
        let room = available.height + proxy.safeAreaInsets.bottom
            - topBarHeight - detailsHeight - controlsHeight - 56
        let side = max(0, min(available.width - 56, available.height * share, room, 420))
        // Music's gesture: the cover sinks back while paused. Not while its back is up, which
        // is being read.
        let sinks = !player.isPlaying && !reduceMotion && !showsBack
        let shape = RoundedRectangle(cornerRadius: CoverImage.radius(for: side), style: .continuous)
        // A single tap on either side does nothing: the cover is where a thumb lands to swipe
        // Now Playing closed, and a short swipe mustn't read as a tap and turn it instead. A
        // double tap turns it, which no swipe can be; the history button below always does.
        return SleeveFlip(showsBack: showsBack) {
            CoverImage(cover: track.cover, size: side)
                .contentShape(shape)
                .onTapGesture(count: 2, perform: turnSleeve)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Artwork")
                .accessibilityAction(named: "Your History", turnSleeve)
        } back: {
            LinerNotes(track: track, isCompact: true, fillsCard: true) {
                navigate(.stats(.song(track.songIdentity)))
            }
            .padding(22)
            .frame(width: side, height: side, alignment: .topLeading)
            .background(.white.opacity(0.1), in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.14), lineWidth: 1) }
            .contentShape(shape)
            .onTapGesture(count: 2, perform: turnSleeve)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Show the Cover", turnSleeve)
        }
        .shadow(color: .black.opacity(sinks ? 0.2 : 0.4), radius: sinks ? 14 : 30, y: sinks ? 6 : 16)
        .scaleEffect(sinks ? 0.82 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.2), value: sinks)
        .frame(maxWidth: .infinity)
    }

    private func turnSleeve() {
        turns += 1
        showsBack.toggle()
    }

    private func details(_ track: PlayerTrack) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(track.artistName)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                PlayCountLine(track: track)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NowPlayingMenu(track: track, onNavigate: navigate)
        }
    }

    private func controls(_ track: PlayerTrack) -> some View {
        VStack(spacing: 22) {
            if let duration = track.duration, duration > 0 {
                Scrubber(duration: duration, isPlaying: player.isPlaying, time: { player.playbackTime }, format: track.local?.format) { time in
                    player.seek(to: time)
                }
            } else {
                LiveScrubber()
            }

            PlayerTransport()

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
                VolumeSlider()
                    .frame(height: 34)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            }

            HStack {
                SleepTimerButton()
                Spacer()
                pageToggle(isOn: showsBack && !showsQueue, systemImage: "clock.arrow.circlepath", label: showsBack ? "Show the Cover" : "Your History") {
                    if showsQueue {
                        withAnimation(reduceMotion ? nil : PlayMotion.panel) { showsQueue = false }
                        if !showsBack { turnSleeve() }
                    } else {
                        turnSleeve()
                    }
                }
                Spacer()
                RoutePicker()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
                Spacer()
                pageToggle(isOn: showsQueue, systemImage: "list.bullet", label: showsQueue ? "Hide Up Next" : "Up Next") {
                    withAnimation(reduceMotion ? nil : PlayMotion.panel) { showsQueue.toggle() }
                }
            }
        }
    }

    /// One of the bottom row's page buttons: lit white while its page is up, as Music's
    /// Lyrics and Up Next buttons are.
    private func pageToggle(isOn: Bool, systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isOn ? .black : .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Background

    private var background: some View {
        NowPlayingBackdrop(cover: player.current?.cover, tint: tint, isPlaying: player.isPlaying)
            .ignoresSafeArea()
    }

    private func navigate(_ destination: NowPlayingDestination) {
        dismiss()
        onNavigate(destination)
    }
}
