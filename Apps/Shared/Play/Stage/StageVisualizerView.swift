import SwiftUI
import TracksCore

/// The sound, drawn: bars that rise with each band of it, low notes to high; a wave of light
/// shaped by them; or an orb of rays around the cover. It hears your own music. Apple Music
/// plays where Tracks can't hear it, so for it the drawing only swells gently by the song's
/// feel, and never pretends to keep a beat it can't hear.
struct StageVisualizerView: View {
    let style: StageVisualizer
    /// The cover's colours, deep to light.
    let palette: [Color]
    /// How lively the song is, 0 to 1, for the gentle swell when Tracks can't hear it.
    let energy: Double
    let isPlaying: Bool
    /// Shared with Stage's background, so both move to the same moment of sound.
    let levels: SmoothedLevels
    /// Behind a square cover, the orb is light alone: rays around a square read as a clock face.
    var isBehindCover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOnScreen) private var isOnScreen
    /// Set a moment after the music pauses, once the bars have fallen, so the drawing stops.
    @State private var isSettled = false

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.interval(reduceMotion: reduceMotion), paused: style == .off || isSettled || !isOnScreen)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let bands = levels.next(
                    heard: AudioLevelMeter.shared.current(),
                    time: time,
                    energy: energy,
                    isPlaying: isPlaying,
                    // Reduce Motion: it still says it's playing, gently.
                    calm: reduceMotion
                )
                switch style {
                case .bars: drawBars(bands, in: &canvas, size: size)
                case .wave: drawWave(bands, time: reduceMotion ? 0 : time, in: &canvas, size: size)
                case .orb: drawOrb(bands, in: &canvas, size: size)
                case .off: break
                }
            }
        }
        .accessibilityHidden(true)
        // Again on coming back on screen, so bars caught mid-fall finish falling.
        .task(id: [isPlaying, isOnScreen]) {
            isSettled = false
            guard !isPlaying else { return }
            // The bars fall to rest in about a second.
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isSettled = true
        }
    }

    /// Every frame on iPhone, where a drum should land the moment it's heard. On the Mac each
    /// frame lays out the window too, so it draws every other one there, as the backgrounds
    /// do (see ``BackdropFrameRate``); the levels move by time, so the motion is the same.
    private static func interval(reduceMotion: Bool) -> Double {
        #if os(macOS)
        return reduceMotion || LowPowerMode.shared.isOn ? 1 / 20 : 1 / 30
        #else
        return reduceMotion || LowPowerMode.shared.isOn ? 1 / 30 : 1 / 60
        #endif
    }

    /// The cover's colours, deep to light, at least three.
    private var colors: [Color] {
        var found = palette.isEmpty ? [Color(white: 0.55), Color(white: 0.75), .white] : palette
        while found.count < 3 { found.append((found.last ?? .white).mix(with: .white, by: 0.35)) }
        return found
    }

    /// The cover's lightest colour lifted toward white: light, whatever the cover, so it reads
    /// on any background.
    private var light: Color { (colors.last ?? .white).mix(with: .white, by: 0.5) }

    // MARK: - Bars

    private func drawBars(_ bands: [Float], in context: inout GraphicsContext, size: CGSize) {
        // Fewer, wider bars where there's little room, each the average of the bands it
        // stands for, so a small strip still reads as bars rather than a picket fence.
        let groups = size.width / CGFloat(bands.count) >= 14 ? 1 : size.width / CGFloat(bands.count) >= 7 ? 2 : 3
        let levels = stride(from: 0, to: bands.count, by: groups).map { start in
            bands[start..<min(bands.count, start + groups)].reduce(0, +) / Float(min(groups, bands.count - start))
        }
        let pitch = size.width / CGFloat(levels.count)
        let width = min(pitch * 0.46, 16)
        let gradient = Gradient(colors: [light.opacity(0.8), .white])
        let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: CGPoint(x: 0, y: size.height), endPoint: .zero)
        var path = Path()
        for (index, level) in levels.enumerated() {
            let height = max(width, CGFloat(level) * size.height)
            let rect = CGRect(x: CGFloat(index) * pitch + (pitch - width) / 2, y: size.height - height, width: width, height: height)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: width / 2, height: width / 2), style: .continuous)
        }
        context.fill(path, with: shading)
    }

    // MARK: - Wave

    /// Three ribbons of light in the cover's colours, laid over one another, each as tall at
    /// each point as the sound at that pitch: low notes on the left, high on the right, and
    /// tapering to nothing at both ends, as Siri's wave does.
    private func drawWave(_ bands: [Float], time: Double, in context: inout GraphicsContext, size: CGSize) {
        let middle = size.height / 2
        let steps = 72
        let layers: [(color: Color, speed: Double, ripples: Double, offset: Double)] = [
            (colors[0].mix(with: .white, by: 0.25), 0.9, 1.3, 0),
            (colors[1].mix(with: .white, by: 0.3), -1.25, 1.9, 2.1),
            (colors[2].mix(with: .white, by: 0.35), 1.6, 2.6, 4.2),
        ]
        context.blendMode = .plusLighter
        for layer in layers {
            var top: [CGPoint] = []
            top.reserveCapacity(steps + 1)
            for step in 0...steps {
                let x = Double(step) / Double(steps)
                let taper = pow(sin(.pi * x), 2)
                let ripple = 0.72 + 0.28 * sin(2 * .pi * x * layer.ripples - time * layer.speed + layer.offset)
                let height = pow(Double(Self.level(bands, at: x)), 0.75) * taper * ripple * middle * 0.94
                top.append(CGPoint(x: x * size.width, y: middle - height))
            }
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: 0, y: middle))
            for point in top { ribbon.addLine(to: point) }
            for point in top.reversed() { ribbon.addLine(to: CGPoint(x: point.x, y: 2 * middle - point.y)) }
            ribbon.closeSubpath()
            context.fill(ribbon, with: .color(layer.color.opacity(0.42)))
        }
        // A fine line of light along the middle, where the ribbons meet.
        context.blendMode = .normal
        context.fill(
            Path(CGRect(x: 0, y: middle - 0.75, width: size.width, height: 1.5)),
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.7), .white.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
            )
        )
    }

    /// The level at `x`, 0 to 1 across the bands, eased between them.
    private static func level(_ bands: [Float], at x: Double) -> Float {
        let position = x * Double(bands.count - 1)
        let index = min(bands.count - 2, Int(position))
        let fraction = Float(position - Double(index))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return bands[index] + (bands[index + 1] - bands[index]) * eased
    }

    // MARK: - Orb

    /// A glow that swells with the bass and, around a round cover, a ring of rays, each as
    /// long as the sound at its pitch: low notes at the top, high at the foot, mirrored so the
    /// ring is whole.
    private func drawOrb(_ bands: [Float], in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // The cover takes a little over half the orb; see StageView's layouts.
        let radius = min(size.width, size.height) * (isBehindCover ? 0.3 : 0.28)
        let bass = CGFloat(bands.prefix(5).reduce(0, +) / 5)
        let glow = radius * (isBehindCover ? 1.5 + bass * 0.45 : 1.3 + bass * 0.5)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [light.opacity(0.22 + 0.4 * bass), colors[1].opacity(0.2 * (0.5 + bass)), .clear]),
                center: center, startRadius: radius * 0.6, endRadius: glow
            )
        )
        guard !isBehindCover else { return }
        let half = bands + [bands.last ?? 0]
        let rays = 72
        let inner = radius + max(4, radius * 0.07)
        let lineWidth = max(2, 2 * .pi * inner / CGFloat(rays) * 0.42)
        for ray in 0..<rays {
            let around = (Double(ray) + 0.5) / Double(rays)
            // Down one side and back up the other, so both halves read low to high from the top.
            let pitch = around < 0.5 ? around * 2 : (1 - around) * 2
            let level = CGFloat(Self.level(half, at: pitch))
            let angle = around * 2 * .pi - .pi / 2
            let outer = inner + max(lineWidth * 0.2, pow(level, 0.85) * radius * 0.72)
            var spoke = Path()
            spoke.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            spoke.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(
                spoke,
                with: .color(light.mix(with: .white, by: Double(level) * 0.7).opacity(0.5 + Double(level) * 0.5)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }
}

/// The bands from one frame to the next: quick to rise and slower to fall, as a meter's needle,
/// at the same pace whatever the frame rate. When there's nothing to hear, a gentle swell by the
/// song's feel (see ``AmbientLevels``), never a made-up beat.
final class SmoothedLevels {
    static let resting: Float = 0.04
    private var smoother = LevelSmoother(count: AudioLevelMeter.bandCount, resting: SmoothedLevels.resting)
    /// When they were last worked out: asked twice in one frame, by the background and the
    /// visualizer, they answer the same.
    private var lastTime: Double?

    func next(heard: [Float]?, time: Double, energy: Double, isPlaying: Bool, calm: Bool) -> [Float] {
        if let lastTime, abs(time - lastTime) < 0.004 { return smoother.values }
        let elapsed = lastTime.map { time - $0 } ?? 0
        lastTime = time
        let isHeard = isPlaying && heard?.count == AudioLevelMeter.bandCount
        var target: [Float] = if !isPlaying {
            [Float](repeating: Self.resting, count: AudioLevelMeter.bandCount)
        } else if isHeard, let heard {
            heard
        } else {
            AmbientLevels.levels(at: time, energy: energy, count: AudioLevelMeter.bandCount)
        }
        if calm {
            // Reduce Motion: still says it's playing, in a narrow, slow range.
            target = target.map { 0.1 + $0 * 0.25 }
        }
        // Heard, they follow the sound closely; otherwise they ease, into a pause or out of it.
        (smoother.attack, smoother.release) = switch (isHeard, calm) {
        case (true, false): (0.03, 0.24)
        case (true, true): (0.25, 0.6)
        default: (0.35, 0.45)
        }
        return smoother.step(toward: target, elapsed: elapsed)
    }
}
