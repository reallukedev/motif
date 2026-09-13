import SwiftUI
import MotifCore

/// A ranked list of songs, artists or albums for the chosen range.
struct TopChartView: View {
    let kind: ChartKind
    /// When set, a Songs / Artists / Albums switcher sits at the top of the list.
    var kindSelection: Binding<ChartKind>?
    @Environment(AppModel.self) private var model
    @AppStorage("statsRange") private var range: StatsRange = .month
    @State private var entries: [ChartEntry] = []

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
            ToolbarItem(placement: .primaryAction) {
                RangeMenu(range: $range)
            }
        }
        .task(id: "\(kind.rawValue)|\(range.rawValue)|\(model.library.revision)") {
            entries = ChartEntry.chart(kind, range: range, history: model.library.history)
        }
    }
}

/// A chart row in one shape whatever it ranks.
struct ChartEntry: Identifiable, Equatable {
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
                    id: album.id, route: .artist(StatsCalculator.folded(album.artistName)), title: album.title,
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
                MovementIndicator(movement: entry.movement)
            }
            .frame(width: 32)

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
                Text(Format.listening(entry.seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
        GeometryReader { geometry in
            Capsule()
                .fill(Color.accentColor.gradient)
                .frame(width: max(4, geometry.size.width * fraction))
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// ▲3 in green, ▼1 in red, NEW, or a dash for no change.
struct MovementIndicator: View {
    let movement: ChartMovement

    var body: some View {
        switch movement {
        case .new:
            Text("NEW")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.tint)
                .accessibilityLabel("New entry")
        case .up(let places):
            Label("\(places)", systemImage: "arrowtriangle.up.fill")
                .labelStyle(CompactMovementStyle())
                .foregroundStyle(.green)
                .accessibilityLabel("Up \(places)")
        case .down(let places):
            Label("\(places)", systemImage: "arrowtriangle.down.fill")
                .labelStyle(CompactMovementStyle())
                .foregroundStyle(.red)
                .accessibilityLabel("Down \(places)")
        case .same:
            Image(systemName: "equal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityLabel("No change")
        case .none:
            EmptyView()
        }
    }
}

private struct CompactMovementStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.font(.system(size: 6))
            configuration.title.font(.system(size: 10, weight: .semibold, design: .rounded))
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
