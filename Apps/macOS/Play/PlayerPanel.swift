import SwiftUI
import MotifCore

/// Which page the player's panel shows.
enum PlayerPanelPage: String, CaseIterable, Identifiable {
    case upNext, history

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .upNext: "Up Next"
        case .history: "Your History"
        }
    }
}

/// Rising from the bar, as iTunes's Up Next did: what's coming, or the playing song's
/// history. Opened from the bar, the Controls menu, or ⌥⌘U and ⌥⌘Y.
struct PlayerPanel: View {
    @Binding var page: PlayerPanelPage

    static let width: CGFloat = 380

    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $page) {
                ForEach(PlayerPanelPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let track = player.current {
                switch page {
                case .upNext:
                    UpNextList()
                case .history:
                    ScrollView {
                        LinerNotes(track: track) {
                            openPlayRoute(.stats(.song(track.songIdentity)))
                        }
                        .padding(20)
                    }
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "music.note")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// What's playing and what's queued after it. Drag to reorder, Delete to remove, double-click
/// or Return to play a song now.
struct UpNextList: View {
    @Environment(PlayerModel.self) private var player
    @Environment(YourMusic.self) private var music
    @State private var selection: Set<String> = []
    @State private var isDropTarget = false

    var body: some View {
        List(selection: $selection) {
            Section {
                if let track = player.current {
                    NowRow(track: track)
                        .selectionDisabled()
                }
            } header: {
                if let context = player.context {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.isStation ? "Playing from Radio" : "Playing From")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Text(player.isRadioDriving ? "\(Image(systemName: "car.fill")) \(context.title) · Driving" : "\(context.title)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 4)
                }
            }

            Section {
                if player.context?.isStation == true {
                    note("A station picks as it goes, so nothing is queued. Skip to hear the next song.")
                } else if player.upNext.isEmpty {
                    note(player.isLive ? "Picking the next song…" : "Nothing is queued after this song. Choose Play Next on any song to add it here.")
                } else {
                    ForEach(Array(player.upNext.enumerated()), id: \.element.id) { index, upcoming in
                        UpNextRow(track: upcoming, isGettingReady: isGettingReady(upcoming))
                            .tag(upcoming.id)
                            .contextMenu { menu(for: upcoming, at: index) }
                    }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                    .onDelete { player.removeUpNext(at: $0) }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Playing Next")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !player.upNext.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if !player.upNext.isEmpty, !player.isLive, player.context?.isStation != true {
                        Button("Clear") { player.removeUpNext(at: IndexSet(player.upNext.indices)) }
                            .buttonStyle(.link)
                            .font(.subheadline)
                            .help("Remove every song from Up Next")
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            } footer: {
                if player.isLive, !player.upNext.isEmpty {
                    note("\(player.context?.title ?? "") picks each song as the one before starts, so what you skip and what you let play steer what comes next.")
                }
            }

            if player.isLive, !player.playedAndRemoved.isEmpty {
                Section("Played and Removed") {
                    ForEach(player.playedAndRemoved.prefix(4)) { played in
                        HStack(spacing: 10) {
                            CoverImage(cover: played.cover, size: 32)
                            TwoLines(title: played.title, subtitle: played.artistName)
                            Spacer(minLength: 0)
                            Button("Keep", systemImage: "arrow.down.circle") { player.keepPlayed(played) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Download \(played.title) again, to keep it")
                        }
                        .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Clear and the timings stay off the window's edge.
        .contentMargins(.trailing, 8, for: .scrollContent)
        .contextMenu(forSelectionType: String.self) { _ in
        } primaryAction: { ids in
            guard let id = ids.first, let index = player.upNext.firstIndex(where: { $0.id == id }) else { return }
            player.jump(toUpNext: index)
        }
        .onDeleteCommand {
            let offsets = IndexSet(player.upNext.indices.filter { selection.contains(player.upNext[$0].id) })
            guard !offsets.isEmpty else { return }
            player.removeUpNext(at: offsets)
            selection = []
        }
        // Songs dragged here from any list play after everything queued.
        .dropDestination(for: SongDrag.self) { drops, _ in
            playLast(drops)
            return !drops.isEmpty
        } isTargeted: { isDropTarget = $0 }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .animation(PlayMotion.hover, value: isDropTarget)
    }

    private func playLast(_ drops: [SongDrag]) {
        Task {
            for drop in drops {
                guard let request = await drop.request(in: music) else { continue }
                player.enqueue(request, next: false, title: drop.title)
            }
        }
    }

    /// "12 songs, 48 min", while there's a length to add up.
    private var summary: String {
        let count = player.upNext.count
        let seconds = player.upNext.compactMap(\.duration).reduce(0, +)
        let songs = String(AttributedString(localized: "^[\(count) song](inflect: true)").characters)
        guard seconds > 0 else { return songs }
        let length = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(songs), \(length)"
    }

    @ViewBuilder
    private func menu(for upcoming: PlayerTrack, at index: Int) -> some View {
        Button("Play Now", systemImage: "play") { player.jump(toUpNext: index) }
        if index > 0 {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.moveUpNext(from: IndexSet(integer: index), to: 0)
            }
        }
        Divider()
        NowPlayingMenuItems(track: upcoming)
        Divider()
        Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) {
            player.removeUpNext(at: IndexSet(integer: index))
        }
    }

    /// A new find Motif Radio is getting ready: downloading, or waiting for its server.
    private func isGettingReady(_ track: PlayerTrack) -> Bool {
        guard let local = track.local, local.isFromServer else { return false }
        let copy = music.resolved(local)
        return music.downloads.isDownloading(copy.id) || music.servers.isWaitingToKeep(copy)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .selectionDisabled()
    }
}

/// The song playing, at the top of Up Next, with your count.
private struct NowRow: View {
    let track: PlayerTrack

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(cover: track.cover, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(track.artistName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                PlayCountLine(track: track, showsSince: false)
                    .font(.caption)
            }
            Spacer(minLength: 0)
            PlayingWaveform()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct UpNextRow: View {
    let track: PlayerTrack
    let isGettingReady: Bool

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(cover: track.cover, size: 32)
            TwoLines(
                title: track.title,
                subtitle: isGettingReady ? String(localized: "Downloading · \(track.artistName)") : track.artistName
            )
            Spacer(minLength: 0)
            if let local = track.local {
                DownloadStateIcon(track: local)
            } else if let duration = track.duration {
                Text(Scrubber.format(duration))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to play now")
    }
}

/// A title and a line under it, each on one line.
struct TwoLines: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Music's moving bars, in the accent, while the song beside it plays.
struct PlayingWaveform: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying && !reduceMotion)
            .accessibilityLabel("Now Playing")
    }
}
