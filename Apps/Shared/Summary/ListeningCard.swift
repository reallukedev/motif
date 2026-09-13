import SwiftUI
import MotifCore

/// The top card: how much you listened in the range, how that compares, and the bars.
struct ListeningCard: View {
    let summary: StatsSummary
    var chartHeight: CGFloat = 170
    @State private var selected: TimeBucket?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                AdaptiveStack(verticalAlignment: .firstTextBaseline) {
                    CardLabel(title: "Listening", systemImage: "headphones", tint: .accentColor)
                    Spacer(minLength: 0)
                    Text(rangeTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ListeningTotal(seconds: selected?.seconds ?? summary.listeningSeconds)
                    if let selected {
                        Text(ActivityChart.dateLabel(selected.start, unit: summary.timelineUnit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        comparison
                    }
                }
                .animation(.snappy(duration: 0.2), value: selected?.start)
                .accessibilityElement(children: .combine)

                if summary.timelineIsInformative {
                    ActivityChart(
                        buckets: summary.timeline,
                        unit: summary.timelineUnit,
                        average: averagePerBucket,
                        height: chartHeight,
                        selected: $selected
                    )
                }

                AdaptiveStack(spacing: 8) {
                    footnote(title: "Daily Average", value: Format.listening(summary.dailyAverageSeconds))
                    Spacer(minLength: 0)
                    footnote(title: "Songs", value: summary.captureCount.formatted())
                    Spacer(minLength: 0)
                    footnote(title: "Active Days", value: summary.activeDays.formatted())
                }
            }
        }
    }

    private var rangeTitle: String {
        guard let interval = summary.interval else { return String(localized: "All Time") }
        let end = interval.end.addingTimeInterval(-1)
        switch summary.range {
        case .week:
            return (interval.start..<end).formatted(.interval.day().month(.abbreviated))
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        case .allTime:
            return String(localized: "All Time")
        }
    }

    @ViewBuilder
    private var comparison: some View {
        if let change = summary.listeningChange, abs(change) < 0.03, summary.range != .allTime {
            Label {
                Text("About the same as \(Text(summary.range.previousPhrase))")
            } icon: {
                Image(systemName: "equal")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if let change = summary.listeningChange, summary.range != .allTime {
            let symbol = change >= 0 ? "arrow.up.right" : "arrow.down.right"
            Label {
                Text("\(Format.percentChange(change)) from \(Text(summary.range.previousPhrase))")
            } icon: {
                Image(systemName: symbol)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
            Text("^[\(summary.captureCount) song](inflect: true) from ^[\(summary.uniqueArtistCount) artist](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The dashed line: average per elapsed bucket, in minutes.
    private var averagePerBucket: Double? {
        let elapsed = summary.timeline.filter { $0.start <= summary.generatedAt }
        guard elapsed.count > 1 else { return nil }
        return elapsed.reduce(0) { $0 + $1.seconds } / Double(elapsed.count) / 60
    }

    private func footnote(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// "18 hr 20 min" with big numbers and small units.
struct ListeningTotal: View {
    let seconds: TimeInterval
    var numberFont: Font = .system(.largeTitle, design: .rounded, weight: .bold)

    var body: some View {
        let parts = Format.listeningParts(seconds)
        Group {
            if parts.hours > 0, parts.minutes == 0 {
                Text("\(number(parts.hours)) hr")
            } else if parts.hours > 0 {
                Text("\(number(parts.hours)) hr \(number(parts.minutes)) min")
            } else {
                Text("\(number(parts.minutes)) min")
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.secondary)
        .contentTransition(.numericText())
        .accessibilityLabel(Format.listening(seconds))
    }

    private func number(_ value: Int) -> Text {
        Text(value.formatted())
            .font(numberFont)
            .foregroundStyle(.primary)
    }
}
