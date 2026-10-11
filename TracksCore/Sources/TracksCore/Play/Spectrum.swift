import Foundation
import Accelerate

/// Which bins of a Fourier transform make up each band of a visualizer, low notes to high,
/// spaced as the ear hears them.
///
/// Spaced evenly by pitch, the lowest bands are narrower than one bin, so several would read
/// the same bin and stand as identical bars. Each band here gets at least one bin of its own,
/// the lowest ones nudged up a little where they must be.
public nonisolated struct SpectrumLayout: Equatable, Sendable {
    /// Each band's bins, half open.
    public let bins: [Range<Int>]
    /// Each band's middle, in hertz, by pitch.
    public let centres: [Double]
    /// How much wider each band is in bins than its share of the pitch range, so a band given
    /// two bins where it spans one and a half doesn't read louder than its neighbours.
    public let excess: [Double]

    public init(size: Int, sampleRate: Double, bandCount: Int, low: Double = 40, high: Double = 16_000) {
        let binWidth = sampleRate / Double(size)
        let nyquist = size / 2
        let top = min(high, sampleRate / 2 * 0.95)
        let exact = (0...bandCount).map { index in
            low * pow(top / low, Double(index) / Double(bandCount)) / binWidth
        }
        var edges = exact.map { Int($0.rounded()) }
        // Up from the bottom, every band at least a bin wide; then down from the top, under
        // the highest bin, should a tiny transform have run out of them.
        edges[0] = max(1, edges[0])
        for index in 1...bandCount {
            edges[index] = max(edges[index], edges[index - 1] + 1)
        }
        for index in stride(from: bandCount, through: 0, by: -1) {
            edges[index] = min(edges[index], nyquist - (bandCount - index))
        }
        let bins = (0..<bandCount).map { edges[$0]..<max(edges[$0] + 1, edges[$0 + 1]) }
        self.bins = bins
        centres = bins.map { sqrt(Double($0.lowerBound) * Double($0.upperBound)) * binWidth }
        excess = bins.indices.map { band in
            Double(bins[band].count) / max(0.25, exact[band + 1] - exact[band])
        }
    }

    /// A transform about 85 ms long, a power of two: long enough for a bin of its own in each
    /// low band, short enough that a drum still lands as a hit.
    public static func size(for sampleRate: Double) -> Int {
        var size = 1024
        while Double(size) < sampleRate * 0.085 { size *= 2 }
        return size
    }
}

/// The loudness of each band of a moment of sound, in decibels: a full-scale sine reads 0.
///
/// Each band adds up the power of its bins, rather than taking its loudest, so a band of many
/// bins up high counts all of them; pink noise, as much in each octave as the next, reads level
/// across. Music has less up high than pink noise even so, and a gentle tilt of `tilt` decibels
/// an octave about 1 kHz lets the cymbals show beside the bass.
public nonisolated final class SpectrumAnalyzer {
    public let size: Int
    public let sampleRate: Double
    public let layout: SpectrumLayout
    public let tilt: Float

    private let setup: OpaquePointer
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]
    private var power: [Float]
    /// Turns a bin's squared magnitude into the squared amplitude of the sine behind it, the
    /// window's spreading of each sine over a few bins taken out.
    private let powerScale: Float
    private let weights: [Float]

    public init?(size: Int, sampleRate: Double, bandCount: Int, tilt: Float = 2) {
        guard size >= 256, size & (size - 1) == 0,
              let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { return nil }
        self.size = size
        self.sampleRate = sampleRate
        self.tilt = tilt
        self.setup = setup
        layout = SpectrumLayout(size: size, sampleRate: sampleRate, bandCount: bandCount)
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        outReal = [Float](repeating: 0, count: size / 2)
        outImaginary = [Float](repeating: 0, count: size / 2)
        power = [Float](repeating: 0, count: size / 2)

        // vDSP's real transform comes out at twice the textbook's, so a sine of amplitude A
        // peaks at A times the window's sum. Spread over the window's equivalent noise width
        // in bins, its power adds back up to A squared.
        let sum = window.reduce(0, +)
        let squares = window.reduce(0) { $0 + $1 * $1 }
        let noiseWidth = Float(size) * squares / (sum * sum)
        powerScale = 1 / (sum * sum * noiseWidth)
        weights = zip(layout.centres, layout.excess).map { centre, excess in
            tilt * Float(log2(centre / 1000)) - 10 * Float(log10(excess))
        }
    }

    deinit {
        vDSP_DFT_DestroySetup(setup)
    }

    /// Decibels for each band of `samples`, which are `size` long, oldest first.
    public func decibels(of samples: UnsafeBufferPointer<Float>) -> [Float] {
        precondition(samples.count == size)
        let half = size / 2
        vDSP_vmul(samples.baseAddress!, 1, window, 1, &windowed, 1, vDSP_Length(size))
        // Even samples as the real parts and odd as the imaginary, as the real transform wants.
        windowed.withUnsafeBufferPointer { input in
            input.withMemoryRebound(to: DSPComplex.self) { pairs in
                real.withUnsafeMutableBufferPointer { realOut in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryOut in
                        var split = DSPSplitComplex(realp: realOut.baseAddress!, imagp: imaginaryOut.baseAddress!)
                        vDSP_ctoz(pairs.baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                }
            }
        }
        vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
        // Bin 0 holds the constant and the highest frequency together; no band reads it.
        outReal.withUnsafeMutableBufferPointer { realOut in
            outImaginary.withUnsafeMutableBufferPointer { imaginaryOut in
                var split = DSPSplitComplex(realp: realOut.baseAddress!, imagp: imaginaryOut.baseAddress!)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        return layout.bins.indices.map { band in
            let bins = layout.bins[band]
            var total: Float = 0
            power.withUnsafeBufferPointer { power in
                vDSP_sve(power.baseAddress! + bins.lowerBound, 1, &total, vDSP_Length(bins.count))
            }
            return 10 * log10(max(total * powerScale, 1e-12)) + weights[band]
        }
    }

    public func decibels(of samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { decibels(of: $0) }
    }
}

/// Decibels to bar heights, 0 to 1, with a gain that rides the music the way a recording
/// engineer's hand would: a loud master and a quiet one fill the same height, a quiet passage
/// still looks quiet, and silence stays still.
///
/// The top follows the loudest band: up at once, so nothing pins at the top for long, and down
/// slowly, a few decibels a second, so a quiet bar after a loud chorus reads as quiet.
public nonisolated struct SpectrumGain: Equatable, Sendable {
    /// The decibels a full bar stands for.
    public private(set) var top: Float
    /// How many decibels a bar spans, from nothing to full.
    public var range: Float = 46
    /// Never higher than this, so quiet music isn't blown up into loud bars.
    public var lowestTop: Float = -30
    public var highestTop: Float = 6
    /// Decibels a second the top falls when the music gets quieter.
    public var fall: Float = 4

    public init(top: Float = -12) {
        self.top = top
    }

    /// Heights for `decibels`, `elapsed` seconds after the last.
    public mutating func levels(for decibels: [Float], elapsed: Double) -> [Float] {
        let loudest = (decibels.max() ?? -120) + 3
        let falling = top - fall * Float(min(max(elapsed, 0), 0.5))
        top = min(highestTop, max(lowestTop, loudest, falling))
        let bottom = top - range
        return decibels.map { min(1, max(0, ($0 - bottom) / range)) }
    }
}

/// Bands from one frame to the next, as a meter's needle moves: quick to rise, slower to fall.
/// The same at any frame rate, since each step goes as far as the time it covers.
public nonisolated struct LevelSmoother: Equatable, Sendable {
    public private(set) var values: [Float]
    /// Seconds to rise two thirds of the way to a louder level.
    public var attack: Double
    /// Seconds to fall two thirds of the way to a quieter one.
    public var release: Double

    public init(count: Int, resting: Float = 0, attack: Double = 0.03, release: Double = 0.24) {
        values = [Float](repeating: resting, count: count)
        self.attack = attack
        self.release = release
    }

    @discardableResult
    public mutating func step(toward target: [Float], elapsed: Double) -> [Float] {
        let elapsed = min(max(elapsed, 0), 0.25)
        let rise = Float(1 - exp(-elapsed / max(attack, 0.001)))
        let fall = Float(1 - exp(-elapsed / max(release, 0.001)))
        for index in values.indices where index < target.count {
            let goal = target[index]
            values[index] += (goal - values[index]) * (goal > values[index] ? rise : fall)
        }
        return values
    }
}

/// Bands for music Tracks can't hear, such as Apple Music, which plays in a process of its own.
///
/// It doesn't pretend to hear it: no beat, since the song's tempo isn't known and a made-up one
/// would land between the real beats, and nothing that jumps the way sound would. Just a slow
/// swell that rolls across the bands and breathes, a little quicker and fuller for a lively
/// song, so a screen left showing it still says something's playing.
public nonisolated enum AmbientLevels {
    public static func levels(at time: Double, energy: Double, count: Int) -> [Float] {
        let energy = min(1, max(0, energy))
        // One breath every six seconds for the calmest songs, four for the liveliest.
        let breath = 0.5 + 0.5 * sin(2 * .pi * time / (6 - 2 * energy))
        let reach = 0.42 + 0.18 * energy
        return (0..<count).map { index in
            let place = count > 1 ? Double(index) / Double(count - 1) : 0
            // A long swell rolling across the bands, and a lesser one the other way.
            let first = 0.5 + 0.5 * sin(2 * .pi * (place * 0.8 - time / 8))
            let second = 0.5 + 0.5 * sin(2 * .pi * (place * 1.3 + time / 11) + 1.3)
            let swell = pow(0.65 * first + 0.35 * second, 1.6)
            // Fuller low down, as music is.
            let body = 1 - 0.4 * place
            let level = 0.16 + reach * body * swell * (0.75 + 0.25 * breath)
            return Float(level)
        }
    }
}
