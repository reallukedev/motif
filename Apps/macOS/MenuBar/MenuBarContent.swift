import SwiftUI
import SwiftData
import MotifCore

/// The window that drops down from the menu bar: what's playing, today at a glance, and the
/// last few songs.
///
/// The width is fixed and the scrolling part has a definite height. A `ScrollView` has no
/// intrinsic height and a `.window` MenuBarExtra sizes itself to its content, so without one
/// the list collapsed to nothing (see docs/PlatformNotes.md).
struct MenuBarContent: View {
    let model: AppModel
    let monitor: NowPlayingMonitor

    static let width: CGFloat = 340

    var body: some View {
        if let store = model.store, let capture = model.capture, let playback = model.playback {
            MenuBarBody(monitor: monitor)
                .frame(width: Self.width)
                .modelContainer(store.container)
                .environment(model)
                .environment(capture)
                .environment(playback)
        } else {
            ContentUnavailableView {
                Label("Motif Can't Open Your History", systemImage: "exclamationmark.triangle")
            } description: {
                Text(model.startupError ?? "The database couldn't be opened.")
            }
            .frame(width: Self.width)
            .padding(.vertical)
        }
    }
}

private struct MenuBarBody: View {
    let monitor: NowPlayingMonitor
    @Environment(CaptureService.self) private var capture
    @Query(sort: \Capture.capturedAt, order: .reverse) private var captures: [Capture]
    @State private var today = TodayStats()

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(monitor: monitor, latest: captures.first)
                .padding(14)

            Divider().padding(.horizontal, 14)

            TodayStrip(stats: today)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider().padding(.horizontal, 14)

            RecentList(captures: Array(captures.prefix(12)))

            Divider()

            MenuBarFooter()
        }
        // Polling Music costs an Apple event, so only while the window is open.
        .task { await monitor.follow() }
        .task(id: captures.first?.capturedAt) { today = TodayStats(captures) }
    }
}

// MARK: - Now playing

private struct NowPlayingHeader: View {
    let monitor: NowPlayingMonitor
    let latest: Capture?
    @Environment(CaptureService.self) private var capture

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artwork
                    .opacity(isStale ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    sourceLine
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(isStale ? 0.7 : 1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            TransportControls(monitor: monitor)
        }
    }

    // What to show, in order of preference: Spotify when it's the one making noise, what
    // Music is playing (captured or not yet), then the last song Motif kept.
    private var isShowingSpotify: Bool { monitor.target == .spotify }

    /// Nothing is audible, as far as we know. Before the first read we don't claim either way.
    private var isStale: Bool {
        monitor.hasRead && !monitor.music.isPlaying && !monitor.spotifyPresence.isPlaying
    }

    private var title: String {
        if isShowingSpotify, let track = monitor.spotify { return track.title }
        if let song = capture.nowPlaying { return song.title }
        return latest?.title ?? String(localized: "Nothing Played Yet")
    }

    private var subtitle: String {
        if isShowingSpotify, let track = monitor.spotify { return track.artistName }
        if let song = capture.nowPlaying {
            return [song.artistName, song.albumTitle].compactMap { $0 }.joined(separator: " · ")
        }
        guard let latest else { return String(localized: "Play something in Music") }
        return [latest.artistName, latest.albumTitle].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var artwork: some View {
        if isShowingSpotify, let track = monitor.spotify {
            ArtworkView(url: track.artworkURL, seed: track.title, size: 58)
        } else if let song = capture.nowPlaying {
            ArtworkView(url: song.artworkURL, seed: song.albumTitle ?? song.title, size: 58)
        } else if let latest {
            ArtworkView(url: latest.artworkURL, seed: latest.albumTitle ?? latest.title, size: 58)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary)
                .frame(width: 58, height: 58)
                .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
        }
    }

    /// "Radio · Chill Station", "Now Playing", "Spotify · Not Recorded", or why nothing is.
    @ViewBuilder
    private var sourceLine: some View {
        Group {
            if !capture.isRunning {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else if isStale {
                Label("Last Played", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else if isShowingSpotify {
                // Shown so the window isn't wrong while Spotify plays, but never kept.
                Label("Spotify · Not Recorded", systemImage: "waveform")
                    .foregroundStyle(.secondary)
            } else if monitor.music.isRadio {
                Label(radioLine, systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.pink)
            } else {
                Label {
                    Text("Now Playing")
                } icon: {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: monitor.music.isPlaying)
                }
                .foregroundStyle(.tint)
            }
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    private var radioLine: String {
        let station = capture.currentStation ?? String(localized: "Radio")
        if let session = capture.openSession, let count = session.captures?.count, count > 0 {
            return String(AttributedString(localized: "\(station) · ^[\(count) song](inflect: true)").characters)
        }
        return station
    }
}

// MARK: - Today

private struct TodayStats: Equatable {
    var songs = 0
    var seconds: TimeInterval = 0
    var streak = 0

    init() {}

    init(_ captures: [Capture], calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: .now)
        let todays = captures.prefix { $0.capturedAt >= start }.reversed().map(\.stat)
        songs = todays.count
        seconds = ListeningEstimate.seconds(for: Array(todays)).reduce(0, +)
        // A streak only needs the days, so the most recent rows are plenty.
        let recent = captures.prefix(20_000).map(\.stat)
        streak = StatsCalculator.streak(in: ListeningHistory(recent), calendar: calendar).current
    }
}

private struct TodayStrip: View {
    let stats: TodayStats

    var body: some View {
        HStack(spacing: 0) {
            stat(value: stats.songs.formatted(), label: "Songs Today", symbol: "music.note", tint: .accentColor)
            stat(value: Format.listening(stats.seconds), label: "Listening", symbol: "headphones", tint: .blue)
            stat(
                value: String(AttributedString(localized: "^[\(stats.streak) day](inflect: true)").characters),
                label: "Streak",
                symbol: "flame.fill",
                tint: .orange
            )
        }
    }

    private func stat(value: String, label: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent

private struct RecentList: View {
    let captures: [Capture]
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recently Played")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Show All") {
                    model.sidebarSelection = .history
                    MenuBarFooter.bringMainWindowForward(openWindow: openWindow)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            if captures.isEmpty {
                Text("Songs you play in Music show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(captures) { item in
                            RecentRow(capture: item)
                                .contextMenu {
                                    if !item.songID.isEmpty {
                                        Button("Play", systemImage: "play") {
                                            Task { await playback.play(item) }
                                        }
                                        // No API can take a song back out of a playlist, so
                                        // point at the app that can.
                                        Button("Show in Music", systemImage: "arrow.up.forward.app") {
                                            if let url = URL(string: "https://music.apple.com/song/\(item.songID)") {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(height: 300)
    }
}

/// A compact history row that highlights on hover, like a menu item.
private struct RecentRow: View {
    let capture: Capture
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: capture.artworkURL, seed: capture.albumTitle ?? capture.title, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(capture.title)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if capture.kind == .radio {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.pink)
                    }
                    Text(capture.artistName)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Format.relativeTime(capture.capturedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

private struct MenuBarFooter: View {
    @Environment(CaptureService.self) private var capture
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    /// Closes the menu bar window. Anything that brings up another window calls it, so the
    /// menu doesn't stay open over what it just opened.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 6) {
            Button("Open Motif") {
                Self.bringMainWindowForward(openWindow: openWindow)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()

            Button(capture.isRunning ? "Pause Listening" : "Resume Listening",
                   systemImage: capture.isRunning ? "pause.circle" : "play.circle") {
                capture.isRunning ? capture.stop() : capture.start()
            }
            .help(capture.isRunning ? "Stop noticing what's playing for now" : "Start noticing what's playing again")
            Button("Settings", systemImage: "gearshape") {
                openSettings()
                dismiss()
            }
            .help("Settings")
            Button("Quit Motif", systemImage: "power") { NSApp.terminate(nil) }
                .help("Quit Motif")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .imageScale(.large)
        .padding(12)
    }

    /// `NSApp.activate()` doesn't bring an accessory app forward on macOS 27; the deprecated
    /// form still does, so it's used on purpose.
    static func bringMainWindowForward(openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
