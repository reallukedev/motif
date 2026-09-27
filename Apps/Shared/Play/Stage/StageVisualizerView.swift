import SwiftUI

/// The sound, drawn: bars that rise with each band of it, a wave, or an orb that breathes
/// around the cover. It hears your own music; for Apple Music, which Motif can't hear, it
/// keeps time by the song's feel, as the Halo background does.
struct StageVisualizerView: View {
    let style: StageVisualizer
    /// The cover's colours, deep to light.
    let palette: [Color]
    /// How lively the song is, 0 to 1, for keeping time when Motif can't hear it.
    let energy: Double
    let isPlaying: Bool
    /// Shared with Stage's background, so both move to the same moment of sound.
    let levels: SmoothedLevels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: style == .off || (!isPlaying && levels.isResting))) { context in
            Canvas { canvas, size in
                let bands = levels.next(
                    heard: AudioLevelMeter.shared.current(),
                    time: context.date.timeIntervalSinceReferenceDate,
                    energy: energy,
                    isPlaying: isPlaying,
                    // Reduce Motion: the bars still say it's playing, gently.
                    calm: reduceMotion
                )
                switch style {
                case .bars: drawBars(bands, in: &canvas, size: size)
                case .wave: drawWave(bands, in: &canvas, size: size)
                case .orb: drawOrb(bands, in: &canvas, size: size)
                case .off: break
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var colors: [Color] { palette.isEmpty ? [.white.opacity(0.6), .white] : palette }

    // MARK: - Bars

    private func drawBars(_ bands: [Float], in context: inout GraphicsContext, size: CGSize) {
        let count = CGFloat(bands.count)
        let pitch = size.width / count
        // Slim bars, so even a short strip reads as bars rather than dots.
        let width = min(pitch * 0.5, 12)
        // Light, whatever the cover: the bars stand on the cover's own colours.
        let gradient = Gradient(colors: [(colors.last ?? .white).mix(with: .white, by: 0.45).opacity(0.85), .white])
        for (index, level) in bands.enumerated() {
            let height = max(4, CGFloat(pow(level, 0.8)) * size.height)
            let rect = CGRect(x: CGFloat(index) * pitch + (pitch - width) / 2, y: size.height - height, width: width, height: height)
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(width, height) / 2),
                with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: 0))
            )
        }
    }

    // MARK: - Wave

    private func drawWave(_ bands: [Float], in context: inout GraphicsContext, size: CGSize) {
        let middle = size.height / 2
        let step = size.width / CGFloat(bands.count - 1)
        let points = bands.enumerated().map { index, level in
            CGPoint(x: CGFloat(index) * step, y: CGFloat(pow(level, 0.75)) * size.height * 0.48)
        }
        func curve(_ sign: CGFloat) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: middle))
            var previous = CGPoint(x: 0, y: middle - sign * points[0].y)
            path.addLine(to: previous)
            for point in points.dropFirst() {
                let current = CGPoint(x: point.x, y: middle - sign * point.y)
                let control = CGPoint(x: (previous.x + current.x) / 2, y: previous.y)
                let control2 = CGPoint(x: (previous.x + current.x) / 2, y: current.y)
                path.addCurve(to: current, control1: control, control2: control2)
                previous = current
            }
            path.addLine(to: CGPoint(x: size.width, y: middle))
            return path
        }
        var shape = curve(1)
        shape.addPath(curve(-1))
        let gradient = Gradient(colors: colors.map { $0.opacity(0.75) })
        context.fill(shape, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        context.stroke(curve(1), with: .color(.white.opacity(0.85)), lineWidth: 2)
        context.stroke(curve(-1), with: .color(.white.opacity(0.35)), lineWidth: 1.5)
    }

    // MARK: - Orb

    /// Spokes around a circle left clear for the cover, over a glow that swells with the bass.
    private func drawOrb(_ bands: [Float], in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.3
        let bass = CGFloat(bands.prefix(4).reduce(0, +) / 4)
        let glow = radius * (1.15 + bass * 0.45)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [(colors.last ?? .white).opacity(0.55), (colors.first ?? .white).opacity(0.2), .clear]),
                center: center, startRadius: radius * 0.8, endRadius: glow
            )
        )
        // Each band twice, mirrored, so the ring is whole and low notes sit at the top.
        let spokes = bands + bands.reversed()
        let lineWidth = max(2, radius * 0.035)
        for (index, level) in spokes.enumerated() {
            let angle = Double(index) / Double(spokes.count) * 2 * .pi - .pi / 2
            let inner = radius + lineWidth * 2
            let outer = inner + max(lineWidth, CGFloat(level) * radius * 0.55)
            var spoke = Path()
            spoke.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            spoke.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(spoke, with: .color(.white.opacity(0.4 + Double(level) * 0.6)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

/// The bands from one frame to the next: quick to rise and slow to fall, as a meter's needle,
/// and made up from the song's feel when there's nothing to hear.
final class SmoothedLevels {
    private var values = [Float](repeating: 0.04, count: AudioLevelMeter.bandCount)
    /// When they were last worked out: asked twice in one frame, by the background and the
    /// visualizer, they answer the same.
    private var lastTime: Double = 0

    /// Settled at rest, so the drawing can stop while paused.
    var isResting: Bool { values.allSatisfy { $0 <= 0.05 } }

    func next(heard: [Float]?, time: Double, energy: Double, isPlaying: Bool, calm: Bool) -> [Float] {
        guard abs(time - lastTime) > 0.004 else { return values }
        lastTime = time
        let target: [Float]
        if !isPlaying {
            target = [Float](repeating: 0.04, count: values.count)
        } else if let heard, heard.count == values.count {
            target = heard
        } else {
            target = Self.felt(at: time, energy: energy, count: values.count)
        }
        for index in values.indices {
            var goal = target[index]
            if calm { goal = 0.1 + goal * 0.25 }
            let rate: Float = goal > values[index] ? 0.45 : 0.1
            values[index] += (goal - values[index]) * rate
        }
        return values
    }

    /// Bands for a song Motif can't hear: a kick on each beat in the low end, a lighter tick
    /// between beats up high, and a slow shimmer through the rest. The tempo follows the
    /// song's energy, calm songs slower.
    static func felt(at time: Double, energy: Double, count: Int) -> [Float] {
        let tempo = 72 + energy * 60
        let beat = time * tempo / 60
        let kick = exp(-(beat - floor(beat)) * 6)
        let half = beat * 2
        let tick = exp(-(half - floor(half)) * 9) * 0.45
        return (0..<count).map { index in
            let place = Double(index) / Double(count - 1)
            let low = max(0, 1 - place * 1.8)
            let high = place * place
            let shimmer = 0.5 + 0.5 * sin(time * (1.1 + place * 2.3) + Double(index) * 1.7) * sin(time * 0.63 + Double(index) * 0.9)
            let level = 0.2 + 0.38 * shimmer * (0.55 + energy * 0.45) + kick * low * 0.75 + tick * high * 0.55
            return Float(min(1, level * (1 - place * 0.25)))
        }
    }
}
