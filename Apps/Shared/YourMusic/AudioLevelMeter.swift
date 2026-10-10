import AVFoundation
import MediaToolbox
import Accelerate
import os

/// How loud each part of the sound is right now, low notes to high, for Stage's visualizer.
///
/// Your own music plays through AVFoundation, so each song gets a tap that hands its audio
/// here on its way out. Only while someone's watching (``startListening()``) does it do any
/// work: a Fourier transform of the latest moment of sound, grouped into bands a visualizer
/// can draw. Apple Music plays in a process Tracks can't hear, so for it there are no levels,
/// and the visualizer keeps time by the song's feel instead.
nonisolated final class AudioLevelMeter: @unchecked Sendable {
    static let shared = AudioLevelMeter()
    static let bandCount = 24

    private struct Levels {
        var bands = [Float](repeating: 0, count: AudioLevelMeter.bandCount)
        var measuredAt: CFAbsoluteTime = 0
        var listeners = 0
        var sampleRate: Double = 44_100
    }

    private let levels = OSAllocatedUnfairLock(initialState: Levels())
    /// Held while a moment of sound is being measured. Two songs crossing over both hand in
    /// sound; the second waits its turn by skipping, since the next moment is only a few
    /// milliseconds away.
    private let measuring = OSAllocatedUnfairLock()

    private static let size = 1024
    private let transform = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
    private var window = [Float](repeating: 0, count: size)
    private var samples = [Float](repeating: 0, count: size)
    private var real = [Float](repeating: 0, count: size / 2)
    private var imaginary = [Float](repeating: 0, count: size / 2)
    private var outReal = [Float](repeating: 0, count: size / 2)
    private var outImaginary = [Float](repeating: 0, count: size / 2)
    private var magnitudes = [Float](repeating: 0, count: size / 2)

    private init() {
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
    }

    // MARK: - Watching

    func startListening() {
        levels.withLock { $0.listeners += 1 }
    }

    func stopListening() {
        levels.withLock { $0.listeners = max(0, $0.listeners - 1) }
    }

    private var isListening: Bool { levels.withLock { $0.listeners > 0 } }

    /// The bands, 0 to 1, low to high, if something has been heard in the last moment. Nil
    /// when nothing Tracks can hear is playing.
    func current(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> [Float]? {
        levels.withLock { state in
            now - state.measuredAt < 0.3 ? state.bands : nil
        }
    }

    // MARK: - Hearing a song

    /// Gives a song's player item a tap that hands its sound to the meter. The item plays just
    /// as before; the tap only listens.
    @MainActor
    static func attach(to item: AVPlayerItem, asset: AVAsset) {
        Task { @MainActor in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let tap = makeTap() else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    private static func makeTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: nil,
            finalize: nil,
            prepare: { _, _, format in
                let rate = format.pointee.mSampleRate
                AudioLevelMeter.shared.levels.withLock { $0.sampleRate = rate > 0 ? rate : 44_100 }
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                AudioLevelMeter.shared.hear(buffers, frames: Int(framesOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }

    /// Measures the latest moment of sound, on the audio thread. Cheap when no one's watching:
    /// it returns at once.
    private func hear(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0, isListening else { return }
        _ = measuring.withLockIfAvailableUnchecked {
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let first = list.first, let data = first.mData else { return }
            // The tap hands over 32-bit floats, one buffer per channel, or both channels
            // woven together in one.
            let channels = list.count == 1 ? max(1, Int(first.mNumberChannels)) : 1
            let pointer = data.assumingMemoryBound(to: Float.self)
            let count = min(frames, Self.size)
            let start = frames - count
            samples.withUnsafeMutableBufferPointer { out in
                for index in 0..<Self.size { out[index] = 0 }
                for index in 0..<count {
                    out[index] = pointer[(start + index) * channels]
                }
            }
            measure(sampleRate: levels.withLock { $0.sampleRate })
        }
    }

    private func measure(sampleRate: Double) {
        guard let transform else { return }
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(Self.size))
        // Even samples as the real parts and odd as the imaginary, as the real transform wants.
        for index in 0..<(Self.size / 2) {
            real[index] = samples[2 * index]
            imaginary[index] = samples[2 * index + 1]
        }
        vDSP_DFT_Execute(transform, real, imaginary, &outReal, &outImaginary)
        outReal.withUnsafeMutableBufferPointer { realOut in
            outImaginary.withUnsafeMutableBufferPointer { imaginaryOut in
                var split = DSPSplitComplex(realp: realOut.baseAddress!, imagp: imaginaryOut.baseAddress!)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(Self.size / 2))
            }
        }

        // Bands spaced as the ear hears them, 40 Hz to 16 kHz.
        let binWidth = sampleRate / Double(Self.size)
        let (low, high) = (40.0, min(16_000, sampleRate / 2))
        var bands = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            let from = low * pow(high / low, Double(band) / Double(Self.bandCount))
            let to = low * pow(high / low, Double(band + 1) / Double(Self.bandCount))
            let first = max(1, Int(from / binWidth))
            let last = max(first, min(Self.size / 2 - 1, Int(to / binWidth)))
            var peak: Float = 0
            for bin in first...last { peak = max(peak, magnitudes[bin]) }
            // To decibels, then -64 dB to -4 dB spread over 0 to 1.
            let decibels = 20 * log10(max(peak / Float(Self.size / 4), 1e-7))
            bands[band] = min(1, max(0, (decibels + 64) / 60))
        }
        let measured = bands
        levels.withLock { state in
            state.bands = measured
            state.measuredAt = CFAbsoluteTimeGetCurrent()
        }
    }
}
