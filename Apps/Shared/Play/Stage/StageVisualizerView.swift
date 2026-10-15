import SwiftUI
import TracksCore

/// The sound, drawn, one of three ways: a glow of the cover's colours that swells with the
/// music, a halo of light blooming from behind the cover on each beat, or a waveform of the
/// last few seconds passing by. See ``GlowVisual``, ``HaloVisual`` and ``WaveformVisual``.
///
/// It hears your own music. Apple Music plays where Tracks can't hear it, so for it the drawing
/// follows each song's beat, feel and loudness, learned from its preview (see
/// ``GrooveStore``): a quiet ballad moves gently, a loud dance track hits hard.
///
/// Paused, it settles and stops drawing, and off screen it doesn't draw at all. Under Reduce
/// Motion it's still.
struct StageVisualizerView: View {
    let style: StageVisualizer
    /// The cover's colours, deep to light.
    let palette: [Color]
    /// How lively the song is, 0 to 1, for its pace when its groove isn't known.
    let energy: Double
    let isPlaying: Bool
    /// Shared with Stage's background, so both move to the same moment of sound.
    let levels: SmoothedLevels
    /// The side of the cover centred in this view, for the glow and the halo around it.
    var cover: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOnScreen) private var isOnScreen
    @Environment(PlayerModel.self) private var player: PlayerModel?
    /// The glow swells slowly and never flashes; the halo breathes on each beat.
    @State private var glow = SoftPulse(bloomAttack: 0.12, bloomRelease: 0.7)
    @State private var halo = SoftPulse(bloomAttack: 0.03, bloomRelease: 0.25)
    @State private var history = WaveHistory()
    /// The slow drift and turn, which glide to a stop on pause and go on from there.
    @State private var drift = BackdropClock(speed: 0, at: Date.now.timeIntervalSinceReferenceDate)
    /// Set once the music has paused and the light has settled, so the drawing stops.
    @State private var isSettled = false

    var body: some View {
        let lights = Self.lights(palette, whiteness: style == .glow ? 0.06 : 0.18)
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: interval, paused: style == .off || reduceMotion || isSettled || !isOnScreen)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let pulse = reduceMotion ? .still(isPlaying: isPlaying) : levels.next(
                    heard: AudioLevelMeter.shared.current(),
                    time: time,
                    song: SongMoment(player: player, energy: energy),
                    isPlaying: isPlaying
                )
                let phase = reduceMotion ? 0 : drift.phase(at: time)
                switch style {
                case .glow:
                    let (level, bloom) = eased(glow, pulse, time: time)
                    GlowVisual(colors: lights, level: level, bloom: bloom, phase: phase)
                case .halo:
                    let (level, bloom) = eased(halo, pulse, time: time)
                    HaloVisual(colors: lights, level: level, bloom: bloom, phase: phase, cover: cover, radius: CoverImage.radius(for: cover))
                case .waveform:
                    let capacity = WaveformVisual.capacity(for: proxy.size.width)
                    if reduceMotion {
                        WaveformVisual(samples: Self.stillWave(capacity: capacity, isPlaying: isPlaying), shift: 0)
                    } else {
                        let drawn = history.step(WaveHistory.loudness(bands: pulse.bands, kick: pulse.kick), time: time, isPlaying: isPlaying, capacity: capacity)
                        WaveformVisual(samples: drawn.samples, shift: drawn.shift)
                    }
                case .off:
                    Color.clear
                }
            }
        }
        .accessibilityHidden(true)
        // Again on coming back on screen, so light caught mid-fall finishes settling.
        .task(id: [isPlaying, isOnScreen]) {
            let now = Date.now.timeIntervalSinceReferenceDate
            drift.setSpeed(isPlaying ? 1 : 0, at: now)
            isSettled = false
            guard !isPlaying else { return }
            // The glow's light takes a few seconds to settle.
            try? await Task.sleep(for: .seconds(max(3, drift.secondsToRest(from: now) ?? 0)))
            guard !Task.isCancelled else { return }
            isSettled = true
        }
    }

    /// The waveform scrolls, so every frame on iPhone, where a drum should land the moment
    /// it's heard. On the Mac each frame lays out the window too, so it draws every other one
    /// there, as the backgrounds do (see ``BackdropFrameRate``). The glow and the halo are
    /// soft light, which looks the same at thirty.
    private var interval: Double {
        if LowPowerMode.shared.isOn { return 1 / 20 }
        #if os(macOS)
        return 1 / 30
        #else
        return style == .waveform ? 1 / 60 : 1 / 30
        #endif
    }

    private func eased(_ soft: SoftPulse, _ pulse: StagePulse, time: Double) -> (level: Double, bloom: Double) {
        if reduceMotion { return (isPlaying ? 0.5 : 0.2, 0) }
        soft.step(bands: pulse.bands, kick: pulse.kick, time: time)
        return (soft.level, soft.bloom)
    }

    /// The cover's colours as light, four at least.
    private static func lights(_ palette: [Color], whiteness: Double) -> [Color] {
        var found = palette.isEmpty ? [Color(white: 0.6), Color(white: 0.8)] : palette
        while found.count < 4 { found.append(found[found.count % max(1, palette.count)]) }
        return found.map { $0.asLight(whiteness: whiteness) }
    }

    /// A waveform that doesn't move, for Reduce Motion: a gentle, even rhythm while playing,
    /// a line of dots otherwise.
    private static func stillWave(capacity: Int, isPlaying: Bool) -> [Float] {
        guard isPlaying else { return [Float](repeating: 0, count: capacity) }
        return (0..<capacity).map { index in
            let beat = Float(index % 6) / 6
            return 0.18 + 0.22 * (1 - beat) * (index % 24 < 6 ? 1 : 0.7)
        }
    }
}

/// One frame of the music, for anything that moves with it.
struct StagePulse {
    /// Each band, 0 to 1, low notes to high.
    var bands: [Float]
    /// The kick, 0 to 1: full as it lands, then falling away.
    var kick: Float
    /// Seconds of motion so far, gathering quicker for a faster, livelier song, and stopped
    /// while paused: for what ripples and drifts, so a ballad breathes and a dance track hurries.
    var motion: Double

    /// The low bands, where the bass and the kick are.
    var bass: Float { bands.prefix(5).reduce(0, +) / 5 }

    /// A frame that doesn't move, for Reduce Motion: a gentle, fuller-low shape while playing,
    /// resting otherwise.
    static func still(isPlaying: Bool) -> StagePulse {
        let count = AudioLevelMeter.bandCount
        let bands = isPlaying
            ? (0..<count).map { 0.32 - 0.14 * Float($0) / Float(count - 1) }
            : [Float](repeating: SmoothedLevels.resting, count: count)
        return StagePulse(bands: bands, kick: 0, motion: 0)
    }
}

/// What the drawing knows of the song playing: its groove, once learned (see ``GrooveStore``),
/// where it is, how long it is, and its feel.
struct SongMoment {
    var groove: Groove?
    var energy: Double
    /// Nil for a radio stream, which has no ends to ease.
    var duration: Double?
    private let player: PlayerModel?

    init(player: PlayerModel?, energy: Double) {
        groove = GrooveStore.shared.groove(for: player?.current)
        self.energy = energy
        duration = player?.current?.duration
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
/// hear plays back from its learned groove, in time with where the song is: a hit on every
/// beat at its tempo, with its kick, snare and hats lighter on top, all as strong as the song
/// is loud. Until that's learned, or
/// when it can't be, or its beat is too unsure to show, a slow breath with no beat at all
/// (see ``AmbientLevels``): a made-up beat against the real one looks like random flashing.
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

    func next(heard: [Float]?, time: Double, song: SongMoment, isPlaying: Bool) -> StagePulse {
        if let lastTime, abs(time - lastTime) < 0.004 { return last }
        let elapsed = min(max(lastTime.map { time - $0 } ?? 0, 0), 0.25)
        lastTime = time
        let count = AudioLevelMeter.bandCount
        let source: Source = if !isPlaying {
            .resting
        } else if heard?.count == count {
            .heard
        } else if let groove = song.groove, groove.confidence >= GrooveLevels.leastConfidence {
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
            let hits = GrooveLevels.hits(playbackTime: position, groove: groove, duration: song.duration)
            target = GrooveLevels.levels(hits: hits, groove: groove, count: count)
            hit = hits.kick
        case .feel:
            target = AmbientLevels.levels(at: time, energy: song.energy, count: count)
            // A song heard too unsure of its beat to show one still breathes as loud as it is.
            if let groove = song.groove {
                let intensity = Float(groove.intensity)
                target = target.map { Self.resting + ($0 - Self.resting) * intensity }
            }
        }
        // Heard, they follow the sound closely, quick up and a natural fall; from a groove,
        // closer still, since the hits already have their own shape; breathing, they ease.
        (smoother.attack, smoother.release) = switch source {
        case .heard: (0.02, 0.18)
        case .groove: (0.012, 0.08)
        case .feel: (0.3, 0.5)
        case .resting: (0.35, 0.45)
        }
        let bands = smoother.step(toward: target, elapsed: elapsed)
        // Up at once on a hit, then away quickly, so a pause never cuts one off.
        kick = max(hit, kick * Float(exp(-elapsed / 0.08)))
        // A song at 120 beats a minute moves at one second a second; paused, nothing does.
        let tempo = source == .groove ? song.groove?.tempo ?? 90 : AmbientLevels.tempo(energy: song.energy)
        let pace = !isPlaying ? 0 : min(1.6, max(0.55, tempo / 120)) * (0.8 + 0.4 * song.energy)
        motion = (motion + elapsed * pace).truncatingRemainder(dividingBy: 100_000)
        last = StagePulse(bands: bands, kick: kick, motion: motion)
        return last
    }
}
