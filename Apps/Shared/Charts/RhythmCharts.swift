import SwiftUI
import Charts
import MotifCore

/// Plays per day of the week, weekends in a lighter shade.
struct WeekdayChart: View {
    let weekdays: [WeekdayCount]
    var height: CGFloat = 140

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        Chart(weekdays) { day in
            BarMark(
                x: .value("Day", String(day.weekday)),
                y: .value("Plays", day.count)
            )
            .foregroundStyle(day.isWeekend ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(Color.accentColor.gradient))
            .cornerRadius(4)
            .accessibilityLabel(Calendar.current.weekdaySymbols[day.weekday - 1])
            .accessibilityValue(Text("\(day.count) plays"))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let weekday = value.as(String.self).flatMap(Int.init) {
                        Text(symbols[weekday - 1])
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}

/// On demand vs radio vs recovered, as a ring with a legend.
struct SourcesDonut: View {
    let sources: [SourceCount]

    var body: some View {
        let total = max(1, sources.reduce(0) { $0 + $1.count })
        AdaptiveStack(spacing: 20) {
            Chart(sources) { source in
                SectorMark(
                    angle: .value("Plays", source.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(source.kind.tint)
                .accessibilityLabel(Text(source.kind.label))
                .accessibilityValue(Text("\(source.count) plays"))
            }
            .chartLegend(.hidden)
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources) { source in
                    HStack(spacing: 8) {
                        Circle().fill(source.kind.tint).frame(width: 8, height: 8)
                        Text(source.kind.label)
                        Spacer(minLength: 8)
                        Text((Double(source.count) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Weekday × hour grid, for the wider Mac layout.
struct HeatMapChart: View {
    let cells: [HeatCell]
    var rowHeight: CGFloat = 30
    private let calendar = Calendar.current

    var body: some View {
        Chart(cells) { cell in
            // The span form with a fixed height. Giving the x axis an array domain crashed
            // Charts during layout (see docs/PlatformNotes.md).
            RectangleMark(
                xStart: .value("Hour", cell.hour),
                xEnd: .value("Hour", cell.hour + 1),
                y: .value("Day", label(for: cell.weekday)),
                height: .fixed(rowHeight - 4)
            )
            .foregroundStyle(by: .value("Plays", cell.count))
            .cornerRadius(3)
            .accessibilityLabel("\(label(for: cell.weekday)), \(Format.hour(cell.hour))")
            .accessibilityValue(Text("\(cell.count) plays"))
        }
        .chartForegroundStyleScale(range: Gradient(colors: [Color.accentColor.opacity(0.07), .accentColor]))
        .chartLegend(.hidden)
        .chartYScale(domain: orderedDays)
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel(anchor: .topLeading) {
                    if let hour = value.as(Int.self) { Text(Format.hour(hour)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel()
            }
        }
        .frame(height: rowHeight * 7 + 24)
    }

    private var orderedDays: [String] {
        (0..<7).map { label(for: (calendar.firstWeekday - 1 + $0) % 7 + 1) }
    }

    private func label(for weekday: Int) -> String {
        calendar.shortWeekdaySymbols[weekday - 1]
    }
}
