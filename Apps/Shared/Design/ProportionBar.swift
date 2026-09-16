import SwiftUI

/// A capsule filled to `fraction` of its width over a faint track, for one share of a whole.
/// Decorative: the row it sits in says the number out loud.
struct ProportionBar: View {
    let fraction: Double
    var style = AnyShapeStyle(Color.accentColor)
    var height: CGFloat = 8

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let clamped = min(max(fraction, 0), 1)
                    Capsule()
                        .fill(style)
                        // Never narrower than it is tall, so a sliver still reads as a bar.
                        .frame(width: clamped > 0 ? max(height, geometry.size.width * clamped) : 0)
                }
            }
            .accessibilityHidden(true)
    }
}
