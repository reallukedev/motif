import SwiftUI
import MotifCore

/// The chart itself: every entry in order, with its place, its cover, how it moved, and its
/// plays. A song's place turns into a play button under the pointer, as a track number does
/// in Music; a click anywhere else opens the entry.
struct ChartList: View {
    let entries: [ChartEntry]
    let open: (ChartEntry) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ChartListRow(position: index + 1, entry: entry, isLast: index == entries.count - 1) {
                    open(entry)
                }
            }
        }
    }
}

private struct ChartListRow: View {
    let position: Int
    let entry: ChartEntry
    let isLast: Bool
    let open: () -> Void

    @State private var isHovered = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var cover: CGFloat = Self.coverSide
    @ScaledMetric(relativeTo: .title3) private var placeWidth: CGFloat = 34
    private var playback = ChartPlayback()

    init(position: Int, entry: ChartEntry, isLast: Bool, open: @escaping () -> Void) {
        self.position = position
        self.entry = entry
        self.isLast = isLast
        self.open = open
    }

    #if os(macOS)
    private static let coverSide: CGFloat = 44
    #else
    private static let coverSide: CGFloat = 52
    #endif

    private var playableSong: MixSong? {
        entry.song.flatMap { playback.playable([$0]).isEmpty ? nil : $0 }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                place
                    .frame(width: placeWidth)
                ArtworkView(url: entry.artworkURL, seed: entry.artworkSeed, size: cover, isCircle: entry.isArtist)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                names
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    ChartMovementBadge(movement: entry.movement)
                    Text(PlayCountText.short(entry.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 64, alignment: .trailing)
                        .contentTransition(.numericText(value: Double(entry.count)))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(isHovered ? 0.6 : 0))
            }
            .overlay(alignment: .bottom) {
                if !isLast {
                    Divider()
                        .padding(.leading, 10 + placeWidth + 14 + cover + 14)
                        .opacity(isHovered ? 0 : 1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(PlayMotion.hover) { isHovered = hovering }
        }
        .contextMenu { ChartEntryMenu(entry: entry, openStats: open) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens your stats")
        .accessibilityActions {
            if let song = playableSong {
                Button("Play") { playback.play([song], title: song.title) }
            }
        }
    }

    /// The place, or Play under the pointer for a song that can play.
    @ViewBuilder
    private var place: some View {
        if isHovered, let song = playableSong {
            Button {
                playback.play([song], title: song.title)
            } label: {
                Image(systemName: "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Play \(entry.title)")
            .transition(.opacity)
        } else {
            Text(position.formatted())
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(position <= 3 ? .primary : .secondary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(.body.weight(.medium))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            if let line = entry.detail ?? subtitle {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if typeSize.isAccessibilitySize {
                Text(PlayCountText.short(entry.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A song's artist and album, an album's artist.
    private var subtitle: String? {
        switch (entry.subtitle, entry.album) {
        case (let artist?, let album?) where !album.isEmpty: "\(artist) · \(album)"
        case (let artist?, _): artist
        default: nil
        }
    }

    private var accessibilityLabel: Text {
        Text("Number \(position), \(entry.title), \(subtitle ?? ""), \(PlayCountText.short(entry.count))")
    }
}

/// How an entry moved since the period before: up or down in places, or new. Nothing when it
/// stayed put, or there's no period before to compare with.
struct ChartMovementBadge: View {
    let movement: ChartMovement

    var body: some View {
        Group {
            switch movement {
            case .new:
                Text("New")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.14), in: .capsule)
                    .accessibilityLabel("New entry")
            case .up(let places):
                Label("\(places)", systemImage: "arrow.up")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Up \(places)")
            case .down(let places):
                Label("\(places)", systemImage: "arrow.down")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Down \(places)")
            case .same, .none:
                EmptyView()
            }
        }
        .labelStyle(MovementLabelStyle())
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 40, alignment: .trailing)
    }
}

private struct MovementLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
                .font(.caption2.weight(.bold))
            configuration.title
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}
