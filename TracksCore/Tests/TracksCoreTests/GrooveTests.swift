import Testing
import Foundation
@testable import TracksCore

/// Made-up drums, the same every run.
private enum Drums {
    static let rate = 44_100.0

    /// A burst of noise at each beat, falling away in a few milliseconds.
    static func clicks(bpm: Double, seconds: Double = 30) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        var random = SeededRandom("clicks")
        var beat = 0.0
        while beat < seconds {
            add(noiseBurst(decay: 0.004, amplitude: 0.8, using: &random), at: beat, to: &samples)
            beat += 60 / bpm
        }
        return samples
    }

    /// A kick on one and three and a snare on two and four, over and over.
    static func backbeat(bpm: Double, seconds: Double = 30) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        var random = SeededRandom("backbeat")
        let kick = (0..<Int(rate * 0.3)).map { index -> Float in
            let time = Double(index) / rate
            return Float(0.9 * min(1, time / 0.004) * exp(-time / 0.12) * sin(2 * .pi * 55 * time))
        }
        var beat = 0
        while Double(beat) * 60 / bpm < seconds {
            let time = Double(beat) * 60 / bpm
            if beat % 2 == 0 {
                add(kick, at: time, to: &samples)
            } else {
                add(noiseBurst(decay: 0.05, amplitude: 0.5, using: &random), at: time, to: &samples)
            }
            beat += 1
        }
        return samples
    }

    private static func noiseBurst(decay: Double, amplitude: Double, using random: inout SeededRandom) -> [Float] {
        (0..<Int(rate * decay * 8)).map { index in
            let noise = Double(random.next() % 20_000) / 10_000 - 1
            return Float(amplitude * noise * exp(-Double(index) / rate / decay))
        }
    }

    private static func add(_ sound: [Float], at time: Double, to samples: inout [Float]) {
        let start = Int(time * rate)
        for (offset, value) in sound.enumerated() where start + offset < samples.count {
            samples[start + offset] += value
        }
    }
}

@Suite("Groove analysis")
struct GrooveAnalysisTests {
    @Test("Finds the tempo of a click track, not half or twice it", arguments: [90.0, 120, 128, 170])
    func tempo(bpm: Double) {
        let groove = GrooveAnalysis.groove(of: Drums.clicks(bpm: bpm), sampleRate: Drums.rate)
        #expect(abs(groove.tempo - bpm) < 2, "heard \(groove.tempo) BPM")
        #expect(groove.confidence > 0.3)
    }

    @Test("A kick on one and three and a snare on two and four show where they land")
    func backbeat() {
        let groove = GrooveAnalysis.groove(of: Drums.backbeat(bpm: 120), sampleRate: Drums.rate)
        #expect(abs(groove.tempo - 120) < 2, "heard \(groove.tempo) BPM")
        let low = groove.low.hits, mid = groove.mid.hits
        // The kick's beats, and the snare's, by the bar the analysis settled on.
        #expect(min(low[0], low[8]) > max(low[4], low[12]) + 0.2, "low \(low)")
        #expect(min(mid[4], mid[12]) > max(mid[0], mid[8]) + 0.2, "mid \(mid)")
        #expect(groove.punch > 0.3)
    }

    @Test("Silence is calm")
    func silence() {
        let groove = GrooveAnalysis.groove(of: [Float](repeating: 0, count: Int(Drums.rate * 30)), sampleRate: Drums.rate)
        #expect(groove.confidence == 0)
        #expect(groove.punch == 0)
        #expect(groove.low.hits.allSatisfy { $0 == 0 })
    }

    /// Sound that's no use, by name, so a failure says which.
    enum Unusable: String, CaseIterable, CustomTestStringConvertible {
        case nothing, tooShort, allNaN, allInfinite, nanRate, zeroRate

        var testDescription: String { rawValue }

        var input: (samples: [Float], rate: Double) {
            let long = Int(Drums.rate * 6)
            return switch self {
            case .nothing: ([], Drums.rate)
            case .tooShort: ([Float](repeating: 0.5, count: 1_000), Drums.rate)
            case .allNaN: ([Float](repeating: .nan, count: long), Drums.rate)
            case .allInfinite: ([Float](repeating: .infinity, count: long), Drums.rate)
            case .nanRate: ([Float](repeating: 0.1, count: long), .nan)
            case .zeroRate: ([Float](repeating: 0.1, count: long), 0)
            }
        }
    }

    @Test("Nothing, too little, NaN or a nonsense rate is safe", arguments: Unusable.allCases)
    func safe(_ unusable: Unusable) {
        let (samples, rate) = unusable.input
        let groove = GrooveAnalysis.groove(of: samples, sampleRate: rate)
        #expect(groove.tempo.isFinite)
        #expect(groove.confidence == 0)
    }

    @Test("Half NaN among the clicks still finds the beat")
    func nanAmongClicks() {
        var samples = Drums.clicks(bpm: 120)
        for index in stride(from: 0, to: samples.count, by: 7) { samples[index] = .nan }
        let groove = GrooveAnalysis.groove(of: samples, sampleRate: Drums.rate)
        #expect(abs(groove.tempo - 120) < 2)
    }
}

@Suite("Groove levels")
struct GrooveLevelsTests {
    static let floor: Groove = {
        var groove = Groove.calm
        groove.tempo = 124
        groove.confidence = 1
        groove.punch = 0.8
        groove.low.hits = (0..<16).map { $0 % 4 == 0 ? 1 : 0 }
        return groove
    }()

    @Test("The low bands pulse once a beat")
    func pulsesAtTempo() throws {
        let tick = 0.002
        let lows = (0..<2_000).map { GrooveLevels.levels(playbackTime: Double($0) * tick, groove: Self.floor, count: 24)[0] }
        let peaks = lows.indices.dropFirst().dropLast().filter { lows[$0] > lows[$0 - 1] && lows[$0] >= lows[$0 + 1] && lows[$0] > 0.5 }
        try #require(peaks.count >= 6)
        for (first, second) in zip(peaks, peaks.dropFirst()) {
            #expect(abs(Double(second - first) * tick - 60 / 124) < 0.01)
        }
        // And falls well away between them.
        #expect((lows.min() ?? 1) < (lows.max() ?? 0) - 0.3)
    }

    @Test("Swing pushes a hit late")
    func swing() {
        var groove = Self.floor
        groove.low.lean[4] = 0.4
        let step = 60 / 124.0 / 4
        let onTime = GrooveLevels.hits(playbackTime: 4 * step + 0.02, groove: Self.floor).kick
        let late = GrooveLevels.hits(playbackTime: 4 * step + 0.02, groove: groove).kick
        #expect(late < onTime * 0.3)
    }

    @Test("Stays between 0 and 1, for any time", arguments: [Groove.calm, GrooveLevelsTests.floor, Groove.sample(seed: "a"), Groove.sample(seed: "b")])
    func bounded(groove: Groove) {
        for time in [-5, 0, 0.001, 1.5, 61.25, 3_600, 1e9, .nan, .infinity] {
            let levels = GrooveLevels.levels(playbackTime: time, groove: groove, count: 24)
            #expect(levels.count == 24)
            #expect(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }

    @Test("The same moment of the same song looks the same")
    func deterministic() {
        #expect(Groove.sample(seed: "Night Drive") == Groove.sample(seed: "Night Drive"))
        let groove = Groove.sample(seed: "Night Drive")
        #expect(GrooveLevels.levels(playbackTime: 42.3, groove: groove, count: 24) == GrooveLevels.levels(playbackTime: 42.3, groove: groove, count: 24))
    }

    @Test("Sample songs keep a tempo drummers play at")
    func sampleTempos() {
        for seed in ["a", "b", "c", "d", "e", "f", "g", "h"] {
            #expect((66...132).contains(Groove.sample(seed: seed).tempo))
        }
    }
}

@Suite("Ambient pulse")
struct AmbientPulseTests {
    @Test("Beats faster for a livelier song")
    func tempo() {
        #expect(AmbientLevels.tempo(energy: 1) > AmbientLevels.tempo(energy: 0) + 30)
    }

    @Test("Stays gentle, and in range", arguments: [0.0, 0.5, 1])
    func bounded(energy: Double) {
        for step in 0..<1_200 {
            let levels = AmbientLevels.pulsing(at: Double(step) / 60, energy: energy, count: 24)
            #expect(levels.allSatisfy { $0 >= 0.15 && $0 <= 1 })
        }
    }
}

@Suite("Playback clock")
struct PlaybackClockTests {
    @Test("Smooths a position reported in steps")
    func smooths() {
        var clock = PlaybackClock()
        var previous = clock.position(reported: 10, at: 100, isPlaying: true)
        for frame in 1...120 {
            let now = 100 + Double(frame) / 60
            // Reported a tenth of a second at a time.
            let reported = 10 + (Double(frame) / 60 * 10).rounded(.down) / 10
            let position = clock.position(reported: reported, at: now, isPlaying: true)
            #expect(position >= previous)
            #expect(position - previous < 0.04)
            previous = position
        }
    }

    @Test("Jumps with a seek")
    func seek() {
        var clock = PlaybackClock()
        _ = clock.position(reported: 10, at: 100, isPlaying: true)
        #expect(clock.position(reported: 95, at: 100.02, isPlaying: true) == 95)
    }
}

@Suite("Meter motion")
struct MeterMotionTests {
    @Test("A cap hangs, then falls faster and faster")
    func caps() {
        var caps = PeakCaps()
        caps.step([1], elapsed: 0)
        caps.step([0], elapsed: 0.2)
        #expect(caps.peaks[0] == 1)
        var drops: [Float] = []
        var last: Float = 1
        for _ in 0..<12 {
            caps.step([0], elapsed: 1 / 30)
            drops.append(last - caps.peaks[0])
            last = caps.peaks[0]
        }
        #expect(caps.peaks[0] < 1)
        #expect(drops.last! > drops.first!)
    }

    @Test("A jump in the bass is a hit that falls away")
    func onset() {
        var follower = OnsetFollower()
        for _ in 0..<60 { follower.step(0.2, elapsed: 1 / 60) }
        #expect(follower.hit < 0.05)
        follower.step(0.6, elapsed: 1 / 60)
        #expect(follower.hit > 0.9)
        for _ in 0..<30 { follower.step(0.2, elapsed: 1 / 60) }
        #expect(follower.hit < 0.1)
    }

    @Test("A quiet master is stretched over more of the height")
    func contrastStretches() {
        var contrast = LevelContrast()
        var levels: [Float] = []
        for frame in 0..<600 {
            let swing = Float(frame % 30) / 30
            levels = contrast.apply([0.25 + 0.2 * swing, 0.25, 0.3], elapsed: 1 / 60)
        }
        #expect((levels.max() ?? 0) > 0.55)
    }

    @Test("A squashed master's bars are spread apart, its loudest still near the top")
    func contrastSpreads() {
        var contrast = LevelContrast()
        var levels: [Float] = []
        for _ in 0..<600 { levels = contrast.apply([0.62, 0.93, 0.8, 0.7], elapsed: 1 / 60) }
        #expect(levels[0] < 0.5)
        #expect(levels[1] > 0.9)
    }

    @Test("Silence stays still")
    func contrastLeavesSilence() {
        var contrast = LevelContrast()
        var levels: [Float] = []
        for _ in 0..<600 { levels = contrast.apply([0.04, 0.03, 0.05], elapsed: 1 / 60) }
        #expect(levels.allSatisfy { $0 < 0.08 })
    }
}
