import SwiftUI
import TracksCore

/// The sound, drawn: bars that rise with each band of it, low notes to high, under caps that
/// hang and drop as a hardware meter's; a wave of light shaped by them; or an orb of rays
/// around the cover. Each kick lands as a bloom on the orb and a flash along the wave.
///
/// It hears your own music. Apple Music plays where Tracks can't hear it, so for it the drawing
/// follows each song's beat and feel, learned from its preview (see ``GrooveStore``): its
/// tempo, where its drums fall, how hard it hits. A ballad breathes; a dance track punches.
struct StageVisualizerView: View {
    let style: StageVisualizer
    /// The cover's colours, deep to light.
    let palette: [Color]
    /// How lively the song is, 0 to 1, for its pace when its groove isn't known.
    let energy: Double
    let isPlaying: Bool
    /// Shared with Stage's background, so both move to the same moment of sound.
    let levels: SmoothedLevels
    /// Behind a square cover, the orb is light alone: rays around a square read as a clock face.
    var isBehindCover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOnScreen) private var isOnScreen
    @Environment(PlayerModel.self) private var player: PlayerModel?
    @State private var caps = BarCaps()
    /// Set a moment after the music pauses, once the bars have fallen, so the drawing stops.
    @State private var isSettled = false

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.interval(reduceMotion: reduceMotion), paused: style == .off || isSettled || !isOnScreen)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let pulse = levels.next(
                    heard: AudioLevelMeter.shared.current(),
                    time: time,
                    song: SongMoment(player: player, energy: energy),
                    isPlaying: isPlaying,
                    // Reduce Motion: it still says it's playing, gently.
                    calm: reduceMotion
                )
                switch style {
                case .bars: drawBars(pulse, time: time, in: &canvas, size: size)
                case .wave: drawWave(pulse, in: &canvas, size: size)
                case .orb: drawOrb(pulse, in: &canvas, size: size)
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

    private func drawBars(_ pulse: StagePulse, time: Double, in context: inout GraphicsContext, size: CGSize) {
        let bands = pulse.bands
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
        // Room at the top for the caps.
        let reach = size.height - width * 0.9
        let peaks = caps.step(levels, time: time)
        var path = Path()
        var tops = Path()
        let capHeight = max(2, width * 0.32)
        for (index, level) in levels.enumerated() {
            let x = CGFloat(index) * pitch + (pitch - width) / 2
            let height = max(width, CGFloat(level) * reach)
            path.addRoundedRect(in: CGRect(x: x, y: size.height - height, width: width, height: height), cornerSize: CGSize(width: width / 2, height: width / 2), style: .continuous)
            // Each cap rides just over its bar, then hangs and drops on its own.
            let peak = max(height, CGFloat(peaks[index]) * reach) + capHeight * 1.6
            tops.addRoundedRect(in: CGRect(x: x, y: size.height - peak, width: width, height: capHeight), cornerSize: CGSize(width: capHeight / 2, height: capHeight / 2), style: .continuous)
        }
        context.fill(path, with: shading)
        context.fill(tops, with: .color(.white.opacity(0.75 + 0.25 * Double(pulse.kick))))
    }

    // MARK: - Wave

    /// Three ribbons of light in the cover's colours, laid over one another, each as tall at
    /// each point as the sound at that pitch: low notes on the left, high on the right, and
    /// tapering to nothing at both ends, as Siri's wave does.
    private func drawWave(_ pulse: StagePulse, in context: inout GraphicsContext, size: CGSize) {
        let bands = pulse.bands
        let time = pulse.motion
        let kick = Double(pulse.kick)
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
                let height = min(1, pow(Double(Self.level(bands, at: x)), 0.75) * (1 + 0.1 * kick)) * taper * ripple * middle * 0.94
                top.append(CGPoint(x: x * size.width, y: middle - height))
            }
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: 0, y: middle))
            for point in top { ribbon.addLine(to: point) }
            for point in top.reversed() { ribbon.addLine(to: CGPoint(x: point.x, y: 2 * middle - point.y)) }
            ribbon.closeSubpath()
            // Each kick lights the ribbons up.
            context.fill(ribbon, with: .color(layer.color.opacity(0.42 + 0.22 * kick)))
        }
        // A fine line of light along the middle, where the ribbons meet.
        context.blendMode = .normal
        context.fill(
            Path(CGRect(x: 0, y: middle - 0.75 - kick, width: size.width, height: 1.5 + 2 * kick)),
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.7 + 0.3 * kick), .white.opacity(0)]),
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

    /// A glow that swells with the bass and blooms on each kick, a ring of light thrown out by
    /// the kick, and, around a round cover, a ring of rays, each as long as the sound at its
    /// pitch: low notes at the top, high at the foot, mirrored so the ring is whole.
    private func drawOrb(_ pulse: StagePulse, in context: inout GraphicsContext, size: CGSize) {
        let bands = pulse.bands
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // The cover takes a little over half the orb; see StageView's layouts.
        let radius = min(size.width, size.height) * (isBehindCover ? 0.3 : 0.28)
        let bass = CGFloat(pulse.bass)
        let kick = CGFloat(pulse.kick)
        let glow = radius * (isBehindCover ? 1.5 + bass * 0.45 : 1.3 + bass * 0.5) * (1 + 0.12 * kick)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [light.opacity(0.22 + 0.4 * bass + 0.2 * kick), colors[1].opacity(0.2 * (0.5 + bass)), .clear]),
                center: center, startRadius: radius * 0.6, endRadius: glow
            )
        )
        // As the kick falls away its ring spreads out and fades, quick at first, then slower.
        if kick > 0.04 {
            let ring = radius * (isBehindCover ? 1.02 : 1.1) + radius * 0.55 * (1 - kick)
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                with: .color(light.opacity(0.4 * kick)),
                lineWidth: max(1.5, radius * 0.02)
            )
        }
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
            let outer = inner + max(lineWidth * 0.2, pow(level, 0.85) * radius * 0.72 * (1 + 0.08 * kick))
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

/// One frame of the music, for anything that moves with it.
struct StagePulse {
    /// Each band, 0 to 1, low notes to high.
    var bands: [Float]
    /// The kick, 0 to 1: full as it lands, then falling away. Nothing under Reduce Motion.
    var kick: Float
    /// Seconds of motion so far, gathering quicker for a faster, livelier song, and stopped
    /// while paused: for what ripples and drifts, so a ballad breathes and a dance track hurries.
    var motion: Double

    /// The low bands, where the bass and the kick are.
    var bass: Float { bands.prefix(5).reduce(0, +) / 5 }
}

/// What the drawing knows of the song playing: its groove, once learned (see ``GrooveStore``),
/// where it is, and its feel.
struct SongMoment {
    var groove: Groove?
    var energy: Double
    private let player: PlayerModel?

    init(player: PlayerModel?, energy: Double) {
        groove = GrooveStore.shared.groove(for: player?.current)
        self.energy = energy
        self.player = player
    }

    /// Where the song is. Asked a few times a second rather than every frame, since asking
    /// Apple Music isn't free.
    func position() -> Double {
        player?.playbackTime ?? 0
    }
}

/// The music from one frame to the next, at the same pace whatever the frame rate.
///
/// Your own music is heard, band by band, and its kick felt from the bass. A song Tracks can't
/// hear plays back from its learned groove, in time with where the song is: kick, snare and
/// hats where the song has them, at its tempo. Until that's learned, or when it can't be, a
/// gentle swell with a soft beat at the tempo the song's feel suggests (see ``AmbientLevels``).
final class SmoothedLevels {
    static let resting: Float = 0.04
    private var smoother = LevelSmoother(count: AudioLevelMeter.bandCount, resting: SmoothedLevels.resting)
    private var clock = PlaybackClock()
    private var askedAt: Double?
    private var onsets = OnsetFollower()
    private var kick: Float = 0
    private var motion: Double = 0
    /// When they were last worked out: asked twice in one frame, by the background and the
    /// visualizer, they answer the same.
    private var lastTime: Double?
    private var last = StagePulse(bands: [Float](repeating: SmoothedLevels.resting, count: AudioLevelMeter.bandCount), kick: 0, motion: 0)

    private enum Source { case resting, heard, groove, feel }

    func next(heard: [Float]?, time: Double, song: SongMoment, isPlaying: Bool, calm: Bool) -> StagePulse {
        if let lastTime, abs(time - lastTime) < 0.004 { return last }
        let elapsed = min(max(lastTime.map { time - $0 } ?? 0, 0), 0.25)
        lastTime = time
        let count = AudioLevelMeter.bandCount
        let source: Source = if !isPlaying {
            .resting
        } else if heard?.count == count {
            .heard
        } else if song.groove != nil {
            .groove
        } else {
            .feel
        }
        var hit: Float = 0
        var target: [Float]
        switch source {
        case .resting:
            target = [Float](repeating: Self.resting, count: count)
            askedAt = nil
        case .heard:
            target = heard ?? []
            hit = onsets.step(target.prefix(5).reduce(0, +) / 5, elapsed: elapsed)
        case .groove:
            let groove = song.groove ?? .calm
            let position: Double
            if let askedAt, time - askedAt < 0.25, let carried = clock.position(at: time) {
                position = carried
            } else {
                askedAt = time
                position = clock.position(reported: song.position(), at: time, isPlaying: true)
            }
            let hits = GrooveLevels.hits(playbackTime: position, groove: groove)
            target = GrooveLevels.levels(hits: hits, groove: groove, count: count)
            hit = hits.kick
        case .feel:
            target = AmbientLevels.pulsing(at: time, energy: song.energy, count: count)
            hit = AmbientLevels.beat(at: time, energy: song.energy) * 0.4
        }
        if calm {
            // Reduce Motion: still says it's playing, in a narrow, slow range, with no hits.
            target = target.map { 0.1 + $0 * 0.25 }
            hit = 0
        }
        // Heard, they follow the sound closely, quick up and a natural fall; from a groove,
        // closer still, since the hits already have their own shape; otherwise they ease.
        (smoother.attack, smoother.release) = switch (source, calm) {
        case (.heard, false): (0.02, 0.18)
        case (.groove, false): (0.012, 0.08)
        case (.feel, false): (0.1, 0.3)
        case (.heard, true), (.groove, true): (0.25, 0.6)
        default: (0.35, 0.45)
        }
        let bands = smoother.step(toward: target, elapsed: elapsed)
        // Up at once on a hit, then away quickly, so a pause never cuts one off.
        kick = max(hit, kick * Float(exp(-elapsed / 0.08)))
        // A song at 120 beats a minute moves at one second a second; paused, nothing does.
        let tempo = song.groove?.tempo ?? AmbientLevels.tempo(energy: song.energy)
        let pace = calm || !isPlaying ? 0 : min(1.6, max(0.55, tempo / 120)) * (0.8 + 0.4 * song.energy)
        motion = (motion + elapsed * pace).truncatingRemainder(dividingBy: 100_000)
        last = StagePulse(bands: bands, kick: kick, motion: motion)
        return last
    }
}

/// The caps over the bars, kept from one frame to the next. Not observed: a frame redraws nothing.
final class BarCaps {
    private var caps = PeakCaps()
    private var lastTime: Double?

    func step(_ levels: [Float], time: Double) -> [Float] {
        let elapsed = lastTime.map { time - $0 } ?? 0
        lastTime = time
        return caps.step(levels, elapsed: elapsed)
    }
}
