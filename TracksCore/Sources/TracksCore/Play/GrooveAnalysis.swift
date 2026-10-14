import Foundation
import Accelerate

/// Learns a song's ``Groove`` from a stretch of its sound, such as Apple Music's half-minute
/// preview: its tempo, where in a bar each drum lands, how its sound is spread, and how hard
/// it hits.
///
/// It listens as a drummer counting in would: it marks each moment the sound jumps, finds the
/// gap those jumps repeat at most, and then, bar by bar, where in the bar the low, middle and
/// high jumps fall. Slow work, a fraction of a second for a preview, so it runs once a song
/// and away from the main thread.
public nonisolated enum GrooveAnalysis {
    /// The slowest and fastest beat it settles on. Faster or slower, a song is felt at half or
    /// twice its count, and that's how the drawing should move.
    public static let tempoRange = 70.0...180.0

    /// `samples`, one channel, at `sampleRate`.
    public static func groove(of samples: [Float], sampleRate: Double, bandCount: Int = 24) -> Groove {
        guard sampleRate.isFinite, sampleRate >= 8_000, bandCount >= 8,
              Double(samples.count) >= sampleRate * 4 else { return .calm }
        let size = max(1024, SpectrumLayout.size(for: sampleRate) / 2)
        let hop = size / 4
        guard let analyzer = SpectrumAnalyzer(size: size, sampleRate: sampleRate, bandCount: bandCount) else { return .calm }
        let rate = sampleRate / Double(hop)

        // Each moment's bands in decibels, and how loud it is overall.
        var clean = samples
        for index in clean.indices where !clean[index].isFinite { clean[index] = 0 }
        let frames = (clean.count - size) / hop + 1
        var decibels = [Float](repeating: -120, count: frames * bandCount)
        var loudness = [Float](repeating: -120, count: frames)
        clean.withUnsafeBufferPointer { buffer in
            for frame in 0..<frames {
                let window = UnsafeBufferPointer(rebasing: buffer[frame * hop ..< frame * hop + size])
                let bands = analyzer.decibels(of: window)
                for band in 0..<bandCount { decibels[frame * bandCount + band] = bands[band] }
                var rms: Float = 0
                vDSP_rmsqv(window.baseAddress!, 1, &rms, vDSP_Length(size))
                loudness[frame] = 20 * log10(max(rms, 1e-6))
            }
        }
        let loudest = decibels.max() ?? -120
        guard loudest.isFinite, loudest > -70 else { return .calm }
        // Anything far below the loudest is the room, not the music.
        let floor = loudest - 60
        for index in decibels.indices { decibels[index] = max(floor, decibels[index]) }

        // How far each group of bands jumped since the moment before.
        let groups = Groups(bandCount: bandCount)
        var low = [Float](repeating: 0, count: frames)
        var mid = low, high = low, all = low
        for frame in 1..<frames {
            var sums: (low: Float, mid: Float, high: Float, all: Float) = (0, 0, 0, 0)
            for band in 0..<bandCount {
                let rise = max(0, decibels[frame * bandCount + band] - decibels[(frame - 1) * bandCount + band])
                sums.all += rise
                if groups.low.contains(band) { sums.low += rise }
                if groups.mid.contains(band) { sums.mid += rise }
                if groups.high.contains(band) { sums.high += rise }
            }
            low[frame] = sums.low / Float(groups.low.count)
            mid[frame] = sums.mid / Float(groups.mid.count)
            high[frame] = sums.high / Float(groups.high.count)
            all[frame] = sums.all / Float(bandCount)
        }
        let span = max(2, Int(rate * 0.25))
        low = standingOut(low, span: span)
        mid = standingOut(mid, span: span)
        high = standingOut(high, span: span)
        all = standingOut(all, span: span)

        let (period, confidence) = beatPeriod(all, rate: rate)
        guard let period, confidence > 0.04 else {
            var calm = Groove.calm
            calm.shape = shape(decibels, frames: frames, bandCount: bandCount)
            return calm
        }
        let phase = beatPhase(all, period: period)
        var lanes = [low, mid, high].map { lane($0, period: period, phase: phase) }

        // The bar starts where the kick is strongest on a beat, ahead of the snare.
        let downbeat = stride(from: 0, to: Groove.steps, by: 4).max { first, second in
            lanes[0].hits[first] - 0.5 * lanes[1].hits[first] < lanes[0].hits[second] - 0.5 * lanes[1].hits[second]
        } ?? 0
        let strongest = max(1e-6, lanes.map { $0.hits.max() ?? 0 }.max() ?? 0)
        lanes = lanes.map { finished($0, rotatedBy: downbeat, strongest: strongest) }

        let sorted = all.sorted()
        let peaks = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.97))]

        return Groove(
            tempo: 60 * rate / period,
            confidence: Double(min(1, confidence * 1.6)),
            low: lanes[0], mid: lanes[1], high: lanes[2],
            shape: shape(decibels, frames: frames, bandCount: bandCount),
            dynamics: dynamics(loudness, framesPerBar: Int(period * 4)),
            punch: Double(min(1, max(0, peaks / 6))),
            brightness: brightness(decibels, frames: frames, bandCount: bandCount)
        )
    }

    /// The bands each drum sounds loudest in, out of `bandCount` from 40 Hz to 16 kHz: the
    /// kick under 140 Hz, the snare's body and crack from 300 Hz to 3 kHz, the hats over 6 kHz.
    private struct Groups {
        let low: Range<Int>
        let mid: Range<Int>
        let high: Range<Int>

        init(bandCount: Int) {
            func band(_ hertz: Double) -> Int {
                Int((log(hertz / 40) / log(16_000.0 / 40) * Double(bandCount)).rounded())
            }
            low = 0..<max(1, band(140))
            mid = band(300)..<max(band(300) + 1, band(3_000))
            high = band(6_000)..<bandCount
        }
    }

    /// `values` less their average over `span` either side, never below nothing: the jumps
    /// that stand out from what's around them.
    private static func standingOut(_ values: [Float], span: Int) -> [Float] {
        var prefix = [Float](repeating: 0, count: values.count + 1)
        for index in values.indices { prefix[index + 1] = prefix[index] + values[index] }
        return values.indices.map { index in
            let start = max(0, index - span), end = min(values.count, index + span + 1)
            let average = (prefix[end] - prefix[start]) / Float(end - start)
            return max(0, values[index] - average)
        }
    }

    /// The beat's length in frames, to a fraction of one, and how clearly it repeats, 0 to 1.
    ///
    /// Each candidate in the tempo range is scored by how well the jumps line up with
    /// themselves one, two and four beats on. A beat whose half also lines up well is the
    /// song's bar, or its half-time feel, and the faster count is taken instead, so a 170 BPM
    /// song isn't read as 85.
    static func beatPeriod(_ onsets: [Float], rate: Double) -> (period: Double?, confidence: Float) {
        let count = onsets.count
        let shortest = rate * 60 / tempoRange.upperBound
        let longest = rate * 60 / tempoRange.lowerBound
        let maxLag = min(count - 1, Int(rate * 12))
        guard Double(maxLag) > longest * 2 else { return (nil, 0) }
        var mean: Float = 0
        vDSP_meanv(onsets, 1, &mean, vDSP_Length(count))
        let centred = onsets.map { $0 - mean }
        var match = [Float](repeating: 0, count: maxLag + 1)
        centred.withUnsafeBufferPointer { values in
            for lag in 0...maxLag {
                var sum: Float = 0
                vDSP_dotpr(values.baseAddress!, 1, values.baseAddress! + lag, 1, &sum, vDSP_Length(count - lag))
                match[lag] = sum / Float(count)
            }
        }
        guard match[0] > 1e-9 else { return (nil, 0) }
        func at(_ lag: Double) -> Float {
            guard lag >= 0, lag < Double(maxLag) else { return 0 }
            let index = Int(lag), fraction = Float(lag - Double(index))
            return match[index] + (match[index + 1] - match[index]) * fraction
        }
        func score(_ lag: Double) -> Float {
            let along = at(lag) + 0.5 * at(lag * 2) + 0.25 * at(lag * 4)
            // A good match half a beat on means this is two beats, not one.
            let between = lag / 2 >= shortest * 0.98 ? 0.6 * max(0, at(lag / 2)) : 0
            // Gently toward the tempos most songs are felt at.
            let bpm = rate * 60 / lag
            let prior = Float(exp(-0.5 * pow(log2(bpm / 120) / 1.2, 2)))
            return (along - between) * (0.8 + 0.2 * prior)
        }
        let candidates = stride(from: shortest.rounded(.down), through: longest.rounded(.up), by: 1)
        guard var best = candidates.max(by: { score($0) < score($1) }) else { return (nil, 0) }
        // Finer, by how well the jumps line up as many beats on as the stretch allows.
        func lined(_ lag: Double) -> Float {
            var total: Float = 0
            var beats = 1.0
            while lag * beats < Double(maxLag) {
                total += at(lag * beats)
                beats += 1
            }
            return total / Float(beats - 1)
        }
        var fine = best
        var bestLined = lined(best)
        for offset in stride(from: -1.0, through: 1.0, by: 0.02) {
            let lag = best + offset
            guard lag >= shortest * 0.97, lag <= longest * 1.03 else { continue }
            let value = lined(lag)
            if value > bestLined { (fine, bestLined) = (lag, value) }
        }
        best = fine
        return (best, max(0, min(1, at(best) / match[0])))
    }

    /// Where the beats fall, in frames from the start: the offset the jumps line up with best.
    private static func beatPhase(_ onsets: [Float], period: Double) -> Double {
        var best = (phase: 0.0, total: -Float.infinity)
        for phase in stride(from: 0, to: period, by: 0.5) {
            var total: Float = 0
            var place = phase
            while Int(place) + 1 < onsets.count {
                total += onsets[Int(place.rounded())]
                place += period
            }
            if total > best.total { best = (phase, total) }
        }
        return best.phase
    }

    /// Bar by bar, how hard the jumps land around each sixteenth, and how far off it.
    private static func lane(_ onsets: [Float], period: Double, phase: Double) -> GrooveLane {
        let step = period / 4
        let reach = max(1, Int(step / 2))
        var hits = [Float](repeating: 0, count: Groove.steps)
        var lean = [Float](repeating: 0, count: Groove.steps)
        var bars = 0
        var start = phase
        while Int(start + period * 4) + reach < onsets.count {
            for place in 0..<Groove.steps {
                let centre = Int((start + Double(place) * step).rounded())
                var strongest: Float = 0
                var at = 0
                for offset in -reach...reach where centre + offset >= 0 && onsets[centre + offset] > strongest {
                    strongest = onsets[centre + offset]
                    at = offset
                }
                hits[place] += strongest
                lean[place] += strongest * Float(at) / Float(step)
            }
            bars += 1
            start += period * 4
        }
        guard bars > 0 else { return .quiet }
        for place in 0..<Groove.steps {
            lean[place] = hits[place] > 0 ? lean[place] / hits[place] : 0
            hits[place] /= Float(bars)
        }
        return GrooveLane(hits: hits, lean: lean)
    }

    /// The lane turned so the bar starts at `rotation`, its hits 0 to 1, and quieter than the
    /// other drums by as much as it is.
    private static func finished(_ lane: GrooveLane, rotatedBy rotation: Int, strongest: Float) -> GrooveLane {
        let turn = { (values: [Float]) in (0..<Groove.steps).map { values[($0 + rotation) % Groove.steps] } }
        let hits = turn(lane.hits), lean = turn(lane.lean)
        let top = hits.max() ?? 0
        guard top > 1e-6 else { return .quiet }
        let mean = hits.reduce(0, +) / Float(hits.count)
        let base = 0.5 * mean
        let scale = min(1, max(0.25, top / strongest * 1.3))
        let shaped = hits.map { top - base > 1e-6 ? min(1, max(0, ($0 - base) / (top - base))) * scale : scale }
        return GrooveLane(
            hits: shaped,
            lean: zip(shaped, lean).map { $0 > 0.15 ? min(0.5, max(-0.5, $1)) : 0 }
        )
    }

    /// Each band's average loudness, 0 to 1, as the meter would show it.
    private static func shape(_ decibels: [Float], frames: Int, bandCount: Int) -> [Float] {
        var average = [Float](repeating: 0, count: bandCount)
        for frame in 0..<frames {
            for band in 0..<bandCount { average[band] += decibels[frame * bandCount + band] }
        }
        average = average.map { $0 / Float(max(1, frames)) }
        let top = (average.max() ?? 0) + 3
        return average.map { min(1, max(0, ($0 - (top - 40)) / 40)) }
    }

    /// How far the loud bars stand above the quiet ones, 0 to 1, a twelve-decibel spread full.
    private static func dynamics(_ loudness: [Float], framesPerBar: Int) -> Double {
        guard framesPerBar > 0, loudness.count >= framesPerBar * 2 else { return 0 }
        let bars = stride(from: 0, to: loudness.count - framesPerBar + 1, by: framesPerBar).map { start in
            loudness[start ..< start + framesPerBar].reduce(0, +) / Float(framesPerBar)
        }.sorted()
        let quiet = bars[bars.count / 10], loud = bars[bars.count * 9 / 10]
        return Double(min(1, max(0, (loud - quiet) / 12)))
    }

    /// Where the sound's power sits across the bands, 0 at the lowest to 1 at the highest.
    private static func brightness(_ decibels: [Float], frames: Int, bandCount: Int) -> Double {
        var power = [Double](repeating: 0, count: bandCount)
        for frame in 0..<frames {
            for band in 0..<bandCount { power[band] += pow(10, Double(decibels[frame * bandCount + band]) / 10) }
        }
        let total = power.reduce(0, +)
        guard total > 0, total.isFinite else { return 0.5 }
        let centre = power.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } / total
        return min(1, max(0, centre / Double(bandCount - 1)))
    }
}
