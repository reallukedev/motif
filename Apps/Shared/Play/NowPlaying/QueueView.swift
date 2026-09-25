import SwiftUI
import MotifCore

/// Up Next, in place of the cover: the song playing, then what's queued, which can be
/// reordered and trimmed. Shuffle and repeat live here, as in Music.
struct QueueView: View {
    let track: PlayerTrack
    @Environment(PlayerModel.self) private var player
    @Environment(YourMusic.self) private var music

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CoverImage(cover: track.cover, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artistName).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 20)

            HStack {
                Text("Playing Next")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // A station or a live mix picks as it goes: there's no order to shuffle or
                // end to repeat.
                if player.context?.isStation != true, !player.isLive {
                    toggle("Shuffle", "shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
                    toggle(repeatTitle, player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off) {
                        player.cycleRepeat()
                    }
                }
            }

            if player.context?.isStation == true {
                note("A station picks as it goes, so there's nothing queued. Skip to hear the next song.")
            } else if player.upNext.isEmpty {
                if player.isLive {
                    note("Picking the next song…")
                } else {
                    note("Nothing's queued after this song. Use Play Next on any song to add it here.")
                }
            } else {
                // Long-press to move and swipe to remove, as in Music, rather than edit mode's
                // delete buttons.
                List {
                    ForEach(Array(player.upNext.enumerated()), id: \.element.id) { index, upcoming in
                        Button {
                            player.jump(toUpNext: index)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(cover: upcoming.cover, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(upcoming.title).lineLimit(1)
                                    Text(isGettingReady(upcoming) ? "Downloading · \(upcoming.artistName)" : "\(upcoming.artistName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if let local = upcoming.local {
                                    DownloadStateIcon(track: local)
                                        .tint(.white)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Plays this song now")
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.white.opacity(0.15))
                        .listRowSeparator(index == player.upNext.count - 1 ? .hidden : .automatic, edges: .bottom)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
                    }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                    .onDelete { player.removeUpNext(at: $0) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: player.isLive ? liveListHeight : .infinity)

                if player.isLive, !player.playedAndRemoved.isEmpty {
                    playedAndRemoved
                }

                if player.isLive {
                    if player.upNext.contains(where: isGettingReady) {
                        note("Songs on this iPhone play first. New finds download behind them and play once they're here: swipe one away if it's not for you.")
                    } else {
                        note("\(player.context?.title ?? "") picks each song as the one before starts, so what you skip and what you let play steer what comes next. Skip as much as you like.")
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Finds Motif Radio played and removed after, to keep one you liked.
    private var playedAndRemoved: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Played and Removed")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(player.playedAndRemoved.prefix(4)) { played in
                HStack(spacing: 12) {
                    CoverImage(cover: played.cover, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(played.title).lineLimit(1)
                        Text(played.artistName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("Keep", systemImage: "arrow.down.circle") { player.keepPlayed(played) }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Keep \(played.title)")
                }
                .accessibilityElement(children: .combine)
            }
            note("With Delete After Playing on, new finds leave this iPhone once they've played. Keep one to download it again.")
        }
    }

    /// Room for what's queued on a live mix, usually just the next song, so the note sits
    /// right under it.
    @ScaledMetric(relativeTo: .body) private var liveRowHeight: CGFloat = 57
    private var liveListHeight: CGFloat { liveRowHeight * CGFloat(min(player.upNext.count, 4)) }

    /// A new find Motif Radio is getting ready: downloading, or waiting for its server.
    private func isGettingReady(_ track: PlayerTrack) -> Bool {
        guard let local = track.local, local.isFromServer else { return false }
        let copy = music.resolved(local)
        return music.downloads.isDownloading(copy.id) || music.servers.isWaitingToKeep(copy)
    }

    private var repeatTitle: LocalizedStringKey {
        switch player.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.black : .white.opacity(0.8))
                .frame(width: 40, height: 30)
                .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)), in: .capsule)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}
