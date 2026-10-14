import Foundation

/// The feel of a song, learned from a short stretch of it: how fast it goes, where in a bar its
/// drums land, how its sound spreads from low notes to high, and how hard it hits. Small enough
/// to keep for every song, and all a visualizer needs to keep time with a song it can't hear.
public nonisolated struct Groove: Codable, Equatable, Sendable {
    /// Sixteenths in a bar of four.
    public static let steps = 16

    /// Beats a minute.
    public var tempo: Double
    /// How sure the beat is, 0 to 1: a drum machine near 1, a rubato piano near 0.
    public var confidence: Double
    /// Where the kick lands.
    public var low: GrooveLane
    /// Where the snare and claps land.
    public var mid: GrooveLane
    /// Where the hats and cymbals land.
    public var high: GrooveLane
    /// How loud the song is on average in each band, 0 to 1, low notes to high.
    public var shape: [Float]
    /// How far its loud bars stand above its quiet ones, 0 to 1.
    public var dynamics: Double
    /// How hard its hits land, 0 to 1: a ballad's brushes low, a dance track's kick high.
    public var punch: Double
    /// Where its sound sits, 0 dark to 1 bright.
    public var brightness: Double

    public init(tempo: Double, confidence: Double, low: GrooveLane, mid: GrooveLane, high: GrooveLane, shape: [Float], dynamics: Double, punch: Double, brightness: Double) {
        self.tempo = tempo
        self.confidence = confidence
        self.low = low
        self.mid = mid
        self.high = high
        self.shape = shape
        self.dynamics = dynamics
        self.punch = punch
        self.brightness = brightness
    }

    /// Nothing to keep time with: silence, or sound with no beat in it.
    public static let calm = Groove(
        tempo: 90, confidence: 0, low: .quiet, mid: .quiet, high: .quiet,
        shape: [Float](repeating: 0.35, count: 24), dynamics: 0, punch: 0, brightness: 0.5
    )

    /// A made-up groove, the same every time for the same `seed`, for sample songs that make
    /// no sound. A few of the bars drummers play most, at the tempos they're played.
    public static func sample(seed: String) -> Groove {
        var random = SeededRandom(seed)
        func lane(_ hits: [Int: Float]) -> GrooveLane {
            GrooveLane(hits: (0..<steps).map { hits[$0] ?? 0 }, lean: [Float](repeating: 0, count: steps))
        }
        let eighths: [Int: Float] = [0: 0.9, 2: 0.6, 4: 0.9, 6: 0.6, 8: 0.9, 10: 0.6, 12: 0.9, 14: 0.6]
        let sixteenths = Dictionary(uniqueKeysWithValues: (0..<steps).map { ($0, $0 % 2 == 0 ? Float(0.85) : 0.45) })
        var groove: Groove
        switch random.next() % 4 {
        case 0:
            // Four on the floor.
            groove = Groove(
                tempo: 118 + Double(random.next() % 11), confidence: 0.9,
                low: lane([0: 1, 4: 1, 8: 1, 12: 1]), mid: lane([4: 0.9, 12: 0.9]),
                high: lane([2: 1, 6: 1, 10: 1, 14: 1, 0: 0.3, 4: 0.3, 8: 0.3, 12: 0.3]),
                shape: [], dynamics: 0.3, punch: 0.9, brightness: 0.6
            )
        case 1:
            // A backbeat, as most pop and rock.
            groove = Groove(
                tempo: 96 + Double(random.next() % 34), confidence: 0.85,
                low: lane([0: 1, 8: 0.9, 10: 0.55]), mid: lane([4: 1, 12: 1]),
                high: lane(eighths), shape: [], dynamics: 0.45, punch: 0.7, brightness: 0.55
            )
        case 2:
            // Hip-hop: a lazy kick, sixteenths on the hats, swung.
            groove = Groove(
                tempo: 84 + Double(random.next() % 14), confidence: 0.85,
                low: lane([0: 1, 3: 0.6, 10: 0.85]), mid: lane([4: 1, 12: 1]),
                high: lane(sixteenths), shape: [], dynamics: 0.35, punch: 0.8, brightness: 0.45
            )
            for step in stride(from: 1, to: steps, by: 2) { groove.high.lean[step] = 0.22 }
        default:
            // Half time, as a ballad: one big snare a bar.
            groove = Groove(
                tempo: 68 + Double(random.next() % 16), confidence: 0.7,
                low: lane([0: 1, 10: 0.5]), mid: lane([8: 1]),
                high: lane(eighths), shape: [], dynamics: 0.6, punch: 0.4, brightness: 0.4
            )
        }
        // Fuller low down, as music is, with a lift in the presence range.
        groove.shape = (0..<24).map { band in
            let place = Double(band) / 23
            return Float(0.75 - 0.4 * place + 0.12 * exp(-pow((place - 0.65) / 0.15, 2)))
        }
        return groove
    }
}

/// One drum's place in a bar: how hard each sixteenth hits, and how early or late it lands.
public nonisolated struct GrooveLane: Codable, Equatable, Sendable {
    /// How hard each sixteenth hits, 0 to 1.
    public var hits: [Float]
    /// How early or late each lands, in sixteenths, -0.5 to 0.5. Swing pushes the off-beats late.
    public var lean: [Float]

    public init(hits: [Float], lean: [Float]) {
        self.hits = hits
        self.lean = lean
    }

    public static let quiet = GrooveLane(hits: [Float](repeating: 0, count: Groove.steps), lean: [Float](repeating: 0, count: Groove.steps))
}

/// Bands for a song Tracks can't hear, played back from what it learned of the song's feel
/// (see ``Groove``) in time with where the song is.
///
/// The beat grid starts at the song's first moment, where most songs' first downbeat is, and
/// stays there: the analysis hears a stretch from the middle of the song, so it knows the
/// tempo and the bar well but not exactly where the song's own beats fall. It's in time, and
/// may sit a little ahead or behind; it never drifts.
public nonisolated enum GrooveLevels {
    /// How each drum is sounding at a moment, 0 to 1.
    public struct Hits: Equatable, Sendable {
        public var kick: Float
        public var snare: Float
        public var hat: Float
        /// The slow rise and fall over a phrase, 0 to 1.
        public var swell: Float
        /// Seconds into the song, for the shimmer between hits.
        public var time: Double
    }

    public static func hits(playbackTime: Double, groove: Groove) -> Hits {
        let time = playbackTime.isFinite ? max(0, playbackTime) : 0
        let tempo = groove.tempo.isFinite ? min(240, max(40, groove.tempo)) : 90
        let beat = 60 / tempo
        let step = beat / 4
        let punch = Float(min(1, max(0, groove.punch)))
        let certainty = Float(0.45 + 0.55 * min(1, max(0, groove.confidence)))
        // A ballad's kick blooms and fades; a dance track's is short and hard.
        let kick = lane(groove.low, at: time, step: step, decay: min(0.5, max(0.08, beat * Double(0.3 + 0.25 * (1 - punch)))))
        let snare = lane(groove.mid, at: time, step: step, decay: min(0.4, max(0.07, beat * Double(0.22 + 0.2 * (1 - punch)))))
        let hat = lane(groove.high, at: time, step: step, decay: min(0.09, step * 0.7))
        // Louder toward the middle of each eight-bar phrase, by as much as the song moves.
        let bars = time / (beat * 4)
        let swell = 1 - Float(min(1, max(0, groove.dynamics))) * 0.45 * Float(0.5 + 0.5 * cos(2 * .pi * bars / 8))
        return Hits(kick: kick * certainty, snare: snare * certainty, hat: hat * certainty, swell: swell, time: time)
    }

    public static func levels(playbackTime: Double, groove: Groove, count: Int) -> [Float] {
        levels(hits: hits(playbackTime: playbackTime, groove: groove), groove: groove, count: count)
    }

    /// Each band: the song's own shape held as a body, and the drums on top of it, the kick
    /// in the low bands, the snare in the middle, the hats up high.
    public static func levels(hits: Hits, groove: Groove, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        let reach = Float(0.55 + 0.4 * min(1, max(0, groove.punch)))
        return (0..<count).map { band in
            let place = count > 1 ? Float(band) / Float(count - 1) : 0
            let shape = sample(groove.shape, at: place)
            // A little life in the held sound, so it isn't still between hits.
            let shimmer = 0.93 + 0.07 * Float(sin(hits.time * (3.1 + Double(band % 5) * 0.7) + Double(band) * 1.7))
            let body = (0.12 + 0.38 * shape * hits.swell) * shimmer
            let drums = hits.kick * bell(place, 0.07, 0.17)
                + hits.snare * (0.85 * bell(place, 0.45, 0.2) + 0.3 * bell(place, 0.2, 0.08))
                + hits.hat * bell(place, 0.87, 0.14)
            let level = body + drums * reach * (0.55 + 0.45 * shape) * (1 - body * 0.4)
            return min(1, max(0, level.isFinite ? level : 0))
        }
    }

    /// The strongest hit still sounding in `lane` at `time`: up in a hundredth of a second,
    /// then falling away by `decay`.
    private static func lane(_ lane: GrooveLane, at time: Double, step: Double, decay: Double) -> Float {
        guard lane.hits.count == Groove.steps, lane.lean.count == Groove.steps, step > 0 else { return 0 }
        let current = Int(time / step)
        var strongest: Float = 0
        // The next step too, for a hit that leans early.
        for index in stride(from: current + 1, through: max(0, current - 8), by: -1) {
            let place = index % Groove.steps
            let strength = lane.hits[place]
            guard strength > 0.05 else { continue }
            let age = time - (Double(index) + Double(lane.lean[place])) * step
            guard age >= 0 else { continue }
            let value = strength * Float(min(1, age / 0.012) * exp(-age / decay))
            strongest = max(strongest, value)
        }
        return strongest
    }

    private static func bell(_ place: Float, _ centre: Float, _ width: Float) -> Float {
        let distance = (place - centre) / width
        return exp(-distance * distance)
    }

    /// `values` at `place`, 0 to 1 across them, eased between neighbours.
    static func sample(_ values: [Float], at place: Float) -> Float {
        guard values.count > 1 else { return values.first ?? 0.4 }
        let position = min(1, max(0, place)) * Float(values.count - 1)
        let index = min(values.count - 2, Int(position))
        let fraction = position - Float(index)
        return values[index] + (values[index + 1] - values[index]) * fraction
    }
}

/// Where a song is, smoothly, from a player that reports it in steps. Follows small wobbles
/// gently, so the beat doesn't stutter, and jumps with a seek.
public nonisolated struct PlaybackClock: Equatable, Sendable {
    /// The song's time less the clock's, as it's been following it.
    private var offset: Double?

    public init() {}

    public mutating func position(reported: Double, at now: Double, isPlaying: Bool) -> Double {
        guard reported.isFinite, now.isFinite else { return 0 }
        let target = reported - now
        guard isPlaying, let current = offset, abs(target - current) < 0.2 else {
            offset = target
            return reported
        }
        let eased = current + (target - current) * 0.05
        offset = eased
        return now + eased
    }

    /// Where the song is now, carried on from the last report, for the moments between them.
    public func position(at now: Double) -> Double? {
        offset.map { now + $0 }
    }
}

/// A beat, felt from bands Tracks can hear: how far the bass has just jumped above where it's
/// been, as a hit that falls away. 0 to 1.
public nonisolated struct OnsetFollower: Equatable, Sendable {
    private var settled: Float = 0
    public private(set) var hit: Float = 0

    public init() {}

    @discardableResult
    public mutating func step(_ value: Float, elapsed: Double) -> Float {
        let elapsed = min(max(elapsed, 0), 0.25)
        let value = value.isFinite ? value : 0
        let jump = min(1, max(0, (value - settled) * 3.5))
        settled += (value - settled) * Float(1 - exp(-elapsed / 0.25))
        hit = max(jump, hit * Float(exp(-elapsed / 0.14)))
        return hit
    }
}

/// The caps over a meter's bars: up with a bar at once, a moment's hang, then a fall that
/// gathers speed, as a hardware meter's do.
public nonisolated struct PeakCaps: Equatable, Sendable {
    public private(set) var peaks: [Float] = []
    private var holds: [Double] = []
    private var speeds: [Float] = []
    /// Seconds a cap hangs before it falls.
    public var hold: Double = 0.35
    /// Heights a second, a second, that a falling cap gathers.
    public var gravity: Float = 3

    public init() {}

    @discardableResult
    public mutating func step(_ levels: [Float], elapsed: Double) -> [Float] {
        let elapsed = min(max(elapsed, 0), 0.25)
        if peaks.count != levels.count {
            peaks = levels
            holds = [Double](repeating: hold, count: levels.count)
            speeds = [Float](repeating: 0, count: levels.count)
            return peaks
        }
        for index in levels.indices {
            let level = levels[index]
            if level >= peaks[index] {
                peaks[index] = level
                holds[index] = hold
                speeds[index] = 0
            } else if holds[index] > 0 {
                holds[index] -= elapsed
            } else {
                speeds[index] += gravity * Float(elapsed)
                peaks[index] = max(level, peaks[index] - speeds[index] * Float(elapsed))
            }
        }
        return peaks
    }
}

/// The same numbers every time for the same words, unlike `hashValue`.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        return mixed ^ (mixed >> 31)
    }
}
