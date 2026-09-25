import SwiftUI
import MusicKit
import MotifCore

/// Where Now Playing can send the person, after it has closed.
enum NowPlayingDestination {
    case play(PlayRoute)
    case stats(Route)
}

/// Previous, play or pause, and next, big enough for a thumb. They answer the moment they're
/// touched, as Music's do: the glyph sinks under the finger with a soft circle behind it, play
/// and pause turn into each other straight away, and the skip arrows slide on.
struct PlayerTransport: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previousTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        HStack {
            Button {
                previousTaps += 1
                player.skipToPrevious()
            } label: {
                SkipArrows(direction: .backward, height: 26, trigger: previousTaps)
            }
            .buttonStyle(PlayerButtonStyle(diameter: 76))
            .disabled(player.context?.isStation == true)
            .accessibilityLabel("Previous")

            Spacer()

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.magic(fallback: .replace.downUp)))
            }
            .buttonStyle(PlayerButtonStyle(diameter: 88))
            .overlay {
                if player.isPlaying, player.status == .loading {
                    TurningRing(diameter: 84, lineWidth: 2.5, style: AnyShapeStyle(.primary.opacity(0.5)))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: player.status == .loading)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .accessibilityValue(player.isPlaying && player.status == .loading ? Text("Loading") : Text(""))

            Spacer()

            Button {
                nextTaps += 1
                player.skipToNext()
            } label: {
                SkipArrows(direction: .forward, height: 26, trigger: nextTaps)
            }
            .buttonStyle(PlayerButtonStyle(diameter: 76))
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, 16)
    }
}

/// Press in fast, spring back out: a finger on the glass should feel the button give at once,
/// and let go with a little life.
struct PlayerButtonStyle: ButtonStyle {
    var diameter: CGFloat = 76
    var highlight: Color = .white
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(highlight.opacity(isEnabled ? 1 : 0.35))
            .scaleEffect(pressed && !reduceMotion ? 0.84 : 1)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(highlight.opacity(0.14))
                    .scaleEffect(pressed ? 1 : 0.55)
                    .opacity(pressed ? 1 : 0)
            }
            .contentShape(.circle)
            .animation(pressed ? .easeOut(duration: 0.07) : .spring(duration: 0.42, bounce: 0.42), value: pressed)
    }
}

/// Music's skip arrows. On a press the front arrow shrinks away into its point, the one
/// behind slides into its place, and a new one grows in behind it, in one quick spring, so the
/// glyph steps the way it skips and settles looking as it did. Back is the same, mirrored.
/// Each arrow is the system's play triangle, so the weight matches the play button beside it.
/// Still under Reduce Motion.
struct SkipArrows: View {
    enum Direction { case forward, backward }

    let direction: Direction
    /// The arrows' height. Two of them side by side are a little wider than this.
    let height: CGFloat
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arrow = height * 0.86
        Group {
            if reduceMotion {
                arrows(step: 1, arrow: arrow)
            } else {
                KeyframeAnimator(initialValue: 1.0, trigger: trigger) { step in
                    arrows(step: step, arrow: arrow)
                } keyframes: { _ in
                    KeyframeTrack {
                        // From the resting pose, one step, springing into place.
                        MoveKeyframe(0)
                        SpringKeyframe(1, duration: 0.38, spring: .init(response: 0.34, dampingRatio: 0.78))
                    }
                }
            }
        }
        .frame(width: arrow * 2, height: height, alignment: .leading)
        .scaleEffect(x: direction == .forward ? 1 : -1)
        .accessibilityHidden(true)
    }

    /// The glyph part way through its step: 0 and 1 are both the resting pose.
    private func arrows(step: Double, arrow: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Growing in behind, from its base.
            triangle(arrow)
                .scaleEffect(max(step, 0.001), anchor: .leading)
                .opacity(step)
            // Sliding up into the front.
            triangle(arrow)
                .offset(x: arrow * step)
            // Shrinking away into its point.
            triangle(arrow)
                .scaleEffect(max(1 - step, 0.001), anchor: .trailing)
                .opacity(1 - step)
                .offset(x: arrow)
        }
    }

    private func triangle(_ width: CGFloat) -> some View {
        Image(systemName: "play.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }
}

/// Motif's line under the song: how often you've heard it, rolling up the moment it's kept.
struct PlayCountLine: View {
    let track: PlayerTrack
    /// "since August" after the count. Left off where there's only room for the count.
    var showsSince = true
    @Environment(PlayFeed.self) private var feed
    @Environment(PlayerModel.self) private var player
    @Environment(CaptureService.self) private var capture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let facts = feed.facts(for: track)
        let plays = facts?.plays ?? 0
        HStack(spacing: 6) {
            if willBeKept, !isPassedOver {
                KeepIndicator(track: track, isKept: isKept)
            }
            if plays == 0 {
                Text("First listen")
            } else {
                Text("^[\(plays) play](inflect: true)")
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(plays)))
                if showsSince, let first = facts?.firstHeard {
                    Text(verbatim: "·")
                    Text(Self.since(first))
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: plays)
        .accessibilityElement(children: .combine)
    }

    /// Whether Motif will keep this song at all: on-demand plays can be switched off in
    /// Settings, which leaves stations only.
    private var willBeKept: Bool {
        !capture.isPaused && (player.context?.isStation == true || CaptureSettings().capturesOnDemand)
    }

    /// Whether Motif has kept this playing of it: the last capture is this song, made since it
    /// started. With sample data nothing is really kept, so the ring filling stands in.
    private var isKept: Bool {
        guard let last = capture.lastCapture,
              HistoryImport.key(title: last.title, artistName: last.artistName) == track.songIdentity,
              let started = player.trackStartedAt
        else { return false }
        // With no minimum, the capture can land a moment before the player reports the song.
        let slack: TimeInterval = CaptureSettings().minimumListenSeconds > 0 ? 0 : 5
        return last.capturedAt >= started.addingTimeInterval(-slack)
    }

    /// Whether Motif has already decided not to keep this playing: it heard the song moments
    /// ago, so this counts as the same play, or its station is excluded. The ring would fill
    /// and never turn into a check, so it isn't shown.
    private var isPassedOver: Bool {
        guard !isKept,
              let heard = capture.nowPlaying,
              HistoryImport.key(title: heard.title, artistName: heard.artistName) == track.songIdentity,
              case .ignore(let reason) = capture.lastDecision
        else { return false }
        switch reason {
        case .duplicate, .excludedStation, .onDemand: return true
        default: return false
        }
    }

    /// "since March 2024", or "since today".
    private static func since(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "since today") }
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let when = sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.abbreviated).year())
        return String(localized: "since \(when)")
    }
}

/// The song's menu: where it's from, what to do with it, and the sleep timer.
struct NowPlayingMenu: View {
    let track: PlayerTrack
    let onNavigate: (NowPlayingDestination) -> Void

    var body: some View {
        Menu {
            NowPlayingMenuItems(track: track, onNavigate: onNavigate)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.15), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .accessibilityLabel("More")
    }
}

/// The playing song's actions, for its menu on iPhone and its context menu on the Mac.
struct NowPlayingMenuItems: View {
    let track: PlayerTrack
    /// Where Go to Album and the like lead. Nil pushes onto the stack the view is in.
    var onNavigate: ((NowPlayingDestination) -> Void)?
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        if let local = track.local {
            LocalTrackMenu(track: local, onNavigate: { navigate(.play($0)) })
            Divider()
        }
        if let song = track.song {
            Button("Add to Library", systemImage: "plus") { player.addToLibrary(song) }
            FavoriteMenuItem(song: song)
            Button("Create Station", systemImage: "dot.radiowaves.left.and.right") { player.playStation(from: song) }
            Divider()
            Button("Go to Album", systemImage: "square.stack") {
                Task { if let album = await SongLinks.album(of: song) { navigate(.play(.album(album))) } }
            }
            Button("Go to Artist", systemImage: "music.microphone") {
                Task { if let artist = await SongLinks.artist(of: song) { navigate(.play(.artist(artist))) } }
            }
        }
        Button("Your Stats", systemImage: "chart.bar.xaxis") {
            navigate(.stats(.song(track.songIdentity)))
        }
        if let url = track.song?.url {
            ShareLink(item: url) { Label("Share Song", systemImage: "square.and.arrow.up") }
        }
        Divider()
        SuggestLessButton(songIdentity: track.songIdentity)
    }

    private func navigate(_ destination: NowPlayingDestination) {
        if let onNavigate {
            onNavigate(destination)
            return
        }
        switch destination {
        case .play(let route): openPlayRoute(route)
        case .stats(let route): openPlayRoute(.stats(route))
        }
    }
}

/// Stop playing after a while, or at the end of the song. Shows the time left while it runs.
struct SleepTimerButton: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Menu {
            SleepTimerItems(player: player)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
                    .font(.title3)
                if player.sleepTimer != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(label(at: context.date))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            .foregroundStyle(.white.opacity(player.sleepTimer == nil ? 0.7 : 1))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel(player.sleepTimer == nil ? "Sleep Timer" : "Sleep Timer On")
    }

    private func label(at date: Date) -> String {
        if player.sleepTimer == .endOfSong { return String(localized: "End of Song") }
        guard let remaining = player.sleepRemaining(at: date) else { return "" }
        return Scrubber.format(remaining)
    }
}

/// The sleep timer's choices: the end of the song, or a quarter of an hour to an hour. Given
/// the player, since the Mac's menu bar has no environment to read it from.
struct SleepTimerItems: View {
    let player: PlayerModel

    var body: some View {
        if player.sleepTimer != nil {
            Button("Turn Off Timer", systemImage: "xmark") { player.setSleepTimer(nil) }
            Divider()
        }
        Button("End of Song") { player.setSleepTimer(.endOfSong) }
        ForEach(SleepTimer.durations, id: \.self) { duration in
            Button(duration.formatted(.units(allowed: [.hours, .minutes], width: .wide))) {
                player.setSleepTimer(.at(.now.addingTimeInterval(TimeInterval(duration.components.seconds))))
            }
        }
    }
}

/// A ring that fills as a song plays, until it has played long enough for Motif to keep it,
/// then turns into a check. Shows how close a song is to counting without a number to read.
struct KeepIndicator: View {
    let track: PlayerTrack
    let isKept: Bool
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settings' minimum listening time, 30 seconds unless changed.
    private let minimum = CaptureSettings().minimumListenSeconds
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 15

    var body: some View {
        // Still while the song loads: it counts once it's really playing.
        TimelineView(.animation(minimumInterval: 0.25, paused: isKept || player.status != .playing)) { context in
            let progress = progress(at: context.date)
            // With sample data nothing is kept, so a full ring stands in for it.
            let kept = isKept || (player.isDemo && progress >= 1)
            ZStack {
                if kept {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    Circle()
                        .stroke(.tertiary, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side, height: side)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: kept)
            .accessibilityElement()
            .accessibilityLabel(kept ? Text("Kept in your history") : Text("Counting toward your history"))
        }
    }

    /// How far through the minimum listening time the song is. Counted as the capture counts
    /// it, from when the song first played, so neither loading nor scrubbing fills the ring
    /// ahead of the check.
    private func progress(at date: Date) -> Double {
        guard minimum > 0 else { return 1 }
        let elapsed = player.trackStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return min(1, max(0, elapsed / minimum))
    }
}
