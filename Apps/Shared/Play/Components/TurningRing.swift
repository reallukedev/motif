import SwiftUI

/// A ring with a gap, turning: something's on its way, but how far along can't be told. Round a
/// play button while a song buffers, or where a download will show its progress once it starts.
/// Still, with Reduce Motion.
struct TurningRing: View {
    var diameter: CGFloat = 15
    var lineWidth: CGFloat = 2
    var style: AnyShapeStyle = AnyShapeStyle(.secondary)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(isTurning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: isTurning)
            .onAppear { isTurning = true }
    }
}
