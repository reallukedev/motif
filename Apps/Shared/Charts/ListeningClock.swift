import SwiftUI
import MotifCore

/// A 24-hour dial: one wedge per hour, reaching further out where there was more listening.
/// Midnight is at the top and the day runs clockwise.
///
/// Drawn by hand rather than with `SectorMark`. Charts sizes each sector's radius against the
/// others, so varying the outer radius per hour pushed the wedges off-centre.
struct ListeningClock: View {
    let hourly: [HourCount]
    var tint: Color = .accentColor

    var body: some View {
        let peak = max(1, hourly.map(\.count).max() ?? 1)
        ZStack {
            ForEach(hourly) { entry in
                let fraction = Double(entry.count) / Double(peak)
                HourWedge(hour: entry.hour, fraction: max(fraction, 0.05))
                    .fill(entry.count == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(tint.opacity(0.3 + 0.7 * fraction)))
            }
            HourTicks()
                .stroke(.secondary.opacity(0.5), lineWidth: 1)
            centreLabel
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening by hour of the day")
        .accessibilityValue(accessibilitySummary)
    }

    @ViewBuilder
    private var centreLabel: some View {
        if let busiest = hourly.max(by: { $0.count < $1.count }), busiest.count > 0 {
            VStack(spacing: 0) {
                Text("Peak")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Format.hour(busiest.hour))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var accessibilitySummary: String {
        let top = hourly.filter { $0.count > 0 }.sorted { $0.count > $1.count }.prefix(3)
        return top.map { Format.hour($0.hour) }.formatted(.list(type: .and))
    }
}

/// One hour's wedge, from the inner ring outward by `fraction` of the remaining radius.
nonisolated private struct HourWedge: Shape {
    let hour: Int
    let fraction: Double
    static let innerRatio = 0.36

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let inner = radius * Self.innerRatio
        let outer = inner + (radius - inner) * fraction
        // Midnight at twelve o'clock, with a small gap either side of each wedge.
        let gap = 0.9
        let start = Angle.degrees(Double(hour) * 15 - 90 + gap)
        let end = Angle.degrees(Double(hour + 1) * 15 - 90 - gap)

        var path = Path()
        path.addArc(center: centre, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: centre, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Small marks inside the ring at midnight, 6, noon and 6, so the dial reads as a clock.
nonisolated private struct HourTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for quarter in 0..<4 {
            let angle = Double(quarter) * .pi / 2 - .pi / 2
            let from = CGPoint(x: centre.x + cos(angle) * radius * HourWedge.innerRatio * 0.82,
                               y: centre.y + sin(angle) * radius * HourWedge.innerRatio * 0.82)
            let to = CGPoint(x: centre.x + cos(angle) * radius * HourWedge.innerRatio * 0.92,
                             y: centre.y + sin(angle) * radius * HourWedge.innerRatio * 0.92)
            path.move(to: from)
            path.addLine(to: to)
        }
        return path
    }
}

/// The clock with a label and a key for which way round it goes.
struct ListeningClockCard: View {
    let hourly: [HourCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(title: "Listening Clock", systemImage: "clock")
            ZStack {
                ListeningClock(hourly: hourly)
                    .padding(28)
                clockLabels
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
        }
    }

    /// 12 AM at the top, 6 AM right, 12 PM bottom, 6 PM left, in the margin around the dial.
    private var clockLabels: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = side / 2 - 9
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let angle = Double(hour) / 24 * 2 * .pi - .pi / 2
                Text(Format.hour(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
