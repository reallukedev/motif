import SwiftUI

/// One entry in a chart's key: a swatch drawn like the marks it stands for, and a name.
struct ChartKey: View {
    enum Swatch {
        case bar(AnyShapeStyle)
        case line(dashed: Bool)
    }

    let title: LocalizedStringKey
    let swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatchView
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var swatchView: some View {
        switch swatch {
        case .bar(let style):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(style)
                .frame(width: 10, height: 10)
        case .line(let dashed):
            KeyLine()
                .stroke(
                    dashed ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.accentColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 3] : [])
                )
                .frame(width: 16, height: 10)
        }
    }
}

/// A horizontal line through the middle of its frame.
nonisolated private struct KeyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        return path
    }
}
