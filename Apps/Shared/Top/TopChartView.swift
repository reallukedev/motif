import SwiftUI
import MotifCore

/// A ranked list of songs, artists or albums for the chosen range.
struct TopChartView: View {
    let kind: ChartKind
    /// When set, a Songs / Artists / Albums switcher sits at the top of the list.
    var kindSelection: Binding<ChartKind>?
    @Environment(AppModel.self) private var model
    @AppStorage("statsRange") private var range: StatsRange = .month
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries: [ChartEntry] = []
    /// The chart and range `entries` were computed for, so only new listening animates.
    @State private var shown: String?

    var body: some View {
        List {
            if let kindSelection {
                Picker("Chart", selection: kindSelection) {
                    ForEach(ChartKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if entries.isEmpty, model.library.isLoaded {
                ContentUnavailableView(
                    "Nothing Played \(Text(range.phrase))",
                    systemImage: "chart.bar",
                    description: Text("Your top \(Text(kind.title).foregroundStyle(.primary)) appear once you've listened to some music.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(entries) { entry in
                NavigationLink(value: entry.route) {
                    RankedRow(entry: entry)
                }
            }
        }
        .navigationTitle(kindSelection == nil ? kind.navigationTitle : "Charts")
        #if os(iOS)
        .listStyle(.plain)
        #endif
        .toolbar {
            #if os(macOS)
            // The same segmented control as Summary. macOS turns a menu in the toolbar into
            // a borderless pop-up, which read as unfinished next to it.
            ToolbarItem(placement: .principal) {
                RangePicker(range: $range)
                    .fixedSize()
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                RangeMenu(range: $range)
            }
            #endif
        }
        .task(id: "\(kind.rawValue)|\(range.rawValue)|\(model.library.revision)") {
            let (kind, range, history) = (kind, range, model.library.history)
            let next = await OffMainActor.run { ChartEntry.chart(kind, range: range, history: history) }
            guard !Task.isCancelled else { return }
            let selection = "\(kind.rawValue)|\(range.rawValue)"
            LiveUpdate.apply(isLive: shown == selection, reduceMotion: reduceMotion) {
                entries = next
            }
            shown = selection
        }
    }
}

/// A chart row in one shape whatever it ranks.
nonisolated struct ChartEntry: Identifiable, Equatable, Sendable {
    let id: String
    let route: Route
    let title: String
    let subtitle: String?
    let artworkURL: String?
    let artworkSeed: String
    let isArtist: Bool
    let count: Int
    let seconds: TimeInterval
    let rank: Int
    let movement: ChartMovement
    /// Plays relative to the top entry, 0...1, for the bar under the name.
    var fraction: Double = 1

    static func chart(_ kind: ChartKind, range: StatsRange, history: ListeningHistory) -> [ChartEntry] {
        var entries = unscaledChart(kind, range: range, history: history)
        let top = Double(max(1, entries.first?.count ?? 1))
        for index in entries.indices {
            entries[index].fraction = Double(entries[index].count) / top
        }
        return entries
    }

    private static func unscaledChart(_ kind: ChartKind, range: StatsRange, history: ListeningHistory) -> [ChartEntry] {
        switch kind {
        case .songs:
            StatsCalculator.songChart(range: range, history: history).map { ranked in
                let song = ranked.item
                return ChartEntry(
                    id: song.id, route: .song(song.id), title: song.title, subtitle: song.artistName,
                    artworkURL: song.artworkURL, artworkSeed: song.albumTitle ?? song.title, isArtist: false,
                    count: song.count, seconds: song.listeningSeconds, rank: ranked.rank,
                    movement: ranked.movement
                )
            }
        case .artists:
            StatsCalculator.artistChart(range: range, history: history).map { ranked in
                let artist = ranked.item
                return ChartEntry(
                    id: artist.id, route: .artist(artist.id), title: artist.name,
                    subtitle: String(AttributedString(localized: "^[\(artist.songCount) song](inflect: true)").characters),
                    artworkURL: artist.artworkURL, artworkSeed: artist.name, isArtist: true,
                    count: artist.count, seconds: artist.listeningSeconds, rank: ranked.rank,
                    movement: ranked.movement
                )
            }
        case .albums:
            StatsCalculator.albumChart(range: range, history: history).map { ranked in
                let album = ranked.item
                return ChartEntry(
                    id: album.id, route: .album(album.id), title: album.title,
                    subtitle: album.artistName, artworkURL: album.artworkURL, artworkSeed: album.title,
                    isArtist: false, count: album.count, seconds: album.listeningSeconds, rank: ranked.rank,
                    movement: ranked.movement
                )
            }
        }
    }
}

struct RankedRow: View {
    let entry: ChartEntry
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Room for the rank and the movement badge under it, which grow with the text.
    @ScaledMetric(relativeTo: .caption2) private var rankColumnWidth: CGFloat = 32

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.rank.formatted())
                        .font(.headline)
                    MovementIndicator(movement: entry.movement)
                }
                Text(entry.title)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Text("^[\(entry.count) play](inflect: true), \(Format.listening(entry.seconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(entry.rank.formatted())
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(entry.rank)))
                MovementIndicator(movement: entry.movement)
            }
            .frame(width: rankColumnWidth)

            ArtworkView(url: entry.artworkURL, seed: entry.artworkSeed, size: 48, isCircle: entry.isArtist)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ShareBar(fraction: entry.fraction)
                    .frame(maxWidth: 360)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("^[\(entry.count) play](inflect: true)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(entry.count)))
                Text(Format.listening(entry.seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: entry.seconds))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A thin bar showing how an entry compares with the top of its chart, as in Screen Time.
struct ShareBar: View {
    let fraction: Double

    var body: some View {
        FractionalWidthLayout(fraction: fraction, minimumWidth: 4) {
            Capsule()
                .fill(Color.accentColor.gradient)
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Takes all the width it's offered and gives its content `fraction` of it, from the
/// leading edge. What a `GeometryReader` was doing for ``ShareBar``, without the reader.
private struct FractionalWidthLayout: Layout {
    let fraction: Double
    let minimumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(minimumWidth, bounds.width * fraction)
        for subview in subviews {
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}

/// ▲3 in green, ▼1 in red, NEW, or a dash for no change.
///
/// In text styles, so the badges grow with Dynamic Type. On iPhone `.caption2` never goes
/// below 11 points; the fixed 6 to 10 point sizes these replaced were hard to read at any
/// setting.
struct MovementIndicator: View {
    let movement: ChartMovement
    /// The arrow and the equals sign, which are drawn smaller than the number beside them.
    @ScaledMetric(relativeTo: .caption2) private var glyphSize: CGFloat = Self.baseGlyphSize

    var body: some View {
        Group {
            switch movement {
            case .new:
                Text("NEW")
                    .font(.caption2.weight(.heavy))
                    .fontDesign(.rounded)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("New entry")
            case .up(let places):
                Label("\(places)", systemImage: "arrowtriangle.up.fill")
                    .labelStyle(CompactMovementStyle(glyphSize: glyphSize))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Up \(places)")
            case .down(let places):
                Label("\(places)", systemImage: "arrowtriangle.down.fill")
                    .labelStyle(CompactMovementStyle(glyphSize: glyphSize))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Down \(places)")
            case .same:
                Image(systemName: "equal")
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("No change")
            case .none:
                EmptyView()
            }
        }
        // One line in the rank column; the column widens with the text instead.
        .lineLimit(1)
        .fixedSize()
    }

    /// Glyphs at the default text size. Larger on iPhone, where `.caption2` is 11 points
    /// rather than the Mac's 10.
    #if os(iOS)
    private static let baseGlyphSize: CGFloat = 8
    #else
    private static let baseGlyphSize: CGFloat = 7
    #endif
}

private struct CompactMovementStyle: LabelStyle {
    let glyphSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.font(.system(size: glyphSize))
            configuration.title
                .font(.caption2.weight(.semibold))
                .fontDesign(.rounded)
        }
        .monospacedDigit()
    }
}

/// The Week / Month / Year / All Time menu that sits in a toolbar.
struct RangeMenu: View {
    @Binding var range: StatsRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(StatsRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.menu)
    }
}

/// The same choice as a segmented control, for the top of Summary.
struct RangePicker: View {
    @Binding var range: StatsRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(StatsRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
