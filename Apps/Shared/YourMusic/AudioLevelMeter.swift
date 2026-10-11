import AVFoundation
import MediaToolbox
import Synchronization
import TracksCore
import os

/// How loud each part of the sound is right now, low notes to high, for Stage's visualizer and
/// the backgrounds that move with the music.
///
/// Your own music plays through AVFoundation, so each song gets a tap that copies its sound,
/// both channels mixed to one, into a few seconds of buffer on its way out. That's all the
/// audio thread does. The measuring happens when a frame is drawn: the moment of sound around
/// what's being heard right then, by the song's own clock, which already allows for the delay
/// through the speakers, AirPlay included. The tap hands sound over well before it's heard, so
/// the picture lands with the sound rather than ahead of it.
///
/// Apple Music plays in a process Tracks can't hear, so for it there are no levels, and the
/// visualizer moves gently by the song's feel instead (see ``AmbientLevels``).
nonisolated final class AudioLevelMeter: @unchecked Sendable {
    static let shared = AudioLevelMeter()
    static let bandCount = 24

    /// How many views want levels. Read on the audio thread, so it's an atomic, not a lock.
    private let listeners = Atomic<Int>(0)

    private init() {}

    // MARK: - Watching

    func startListening() {
        _ = listeners.add(1, ordering: .relaxed)
    }

    func stopListening() {
        _ = listeners.subtract(1, ordering: .relaxed)
    }

    fileprivate var isListening: Bool { listeners.load(ordering: .relaxed) > 0 }

    // MARK: - Measuring

    /// The songs being heard: each one's sound and the item that plays it.
    @MainActor private var songs: [Song] = []
    @MainActor private var analyzers: [Int: SpectrumAnalyzer] = [:]
    @MainActor private var window: [Float] = []
    @MainActor private var gain = SpectrumGain()
    @MainActor private var last: (time: CFAbsoluteTime, bands: [Float]?) = (0, nil)

    @MainActor private struct Song {
        weak var item: AVPlayerItem?
        let sound: Sound
    }

    /// The bands, 0 to 1, low to high, for what's being heard now. Nil when nothing Tracks can
    /// hear is playing. Asked twice in a frame, by a background and the visualizer, it measures
    /// once.
    @MainActor
    func current(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> [Float]? {
        if abs(now - last.time) < 0.004 { return last.bands }
        let elapsed = now - last.time
        songs.removeAll { $0.item == nil }
        var total: [Float]?
        #if DEBUG
        total = rehearsal(at: now)
        #endif
        for song in songs {
            guard let item = song.item, let heard = heardTime(of: item),
                  let decibels = measure(song.sound, at: heard) else { continue }
            // Two songs meeting, gaplessly, add up as sound does.
            total = total.map { zip($0, decibels).map { 10 * log10(pow(10, $0 / 10) + pow(10, $1 / 10)) } } ?? decibels
        }
        let bands = total.map { gain.levels(for: $0, elapsed: elapsed) }
        last = (now, bands)
        return bands
    }

    #if DEBUG
    /// `-TracksVisualizerRehearsal /path/to/song.m4a` in a Debug build: that file, heard as if
    /// it were playing, over and over, without a sound, so the visualizer can be seen moving
    /// with real music in the demo, whose songs make no sound.
    @MainActor private var rehearsalSound: (samples: [Float], rate: Double, start: CFAbsoluteTime)?
    @MainActor private var rehearsalLoaded = false

    @MainActor
    private func rehearsal(at now: CFAbsoluteTime) -> [Float]? {
        if !rehearsalLoaded {
            rehearsalLoaded = true
            if let path = UserDefaults.standard.string(forKey: "TracksVisualizerRehearsal"),
               let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
               let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: file.processingFormat.channelCount),
               let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(min(file.length, Int64(format.sampleRate * 120)))),
               (try? file.read(into: buffer)) != nil, let channels = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                var mono = [Float](repeating: 0, count: count)
                for channel in 0..<Int(format.channelCount) {
                    for index in 0..<count { mono[index] += channels[channel][index] / Float(format.channelCount) }
                }
                rehearsalSound = (mono, format.sampleRate, now)
            }
        }
        guard let sound = rehearsalSound, let analyzer = analyzer(for: sound.rate) else { return nil }
        let size = analyzer.size
        guard sound.samples.count > size * 2 else { return nil }
        if window.count != size { window = [Float](repeating: 0, count: size) }
        let span = sound.samples.count - size
        let first = Int((now - sound.start) * sound.rate) % span
        for index in 0..<size { window[index] = sound.samples[first + index] }
        return analyzer.decibels(of: window)
    }
    #endif

    @MainActor
    private func analyzer(for rate: Double) -> SpectrumAnalyzer? {
        if let found = analyzers[Int(rate)] { return found }
        let made = SpectrumAnalyzer(size: SpectrumLayout.size(for: rate), sampleRate: rate, bandCount: Self.bandCount)
        analyzers[Int(rate)] = made
        return made
    }

    /// Where the item is in its song as it's heard, if it's playing.
    @MainActor
    private func heardTime(of item: AVPlayerItem) -> Double? {
        guard let timebase = item.timebase, CMTimebaseGetRate(timebase) != 0 else { return nil }
        let time = CMTimebaseGetTime(timebase)
        return time.isNumeric ? time.seconds : nil
    }

    @MainActor
    private func measure(_ sound: Sound, at time: Double) -> [Float]? {
        guard let rate = sound.sampleRate, let analyzer = analyzer(for: rate) else { return nil }
        let size = analyzer.size
        if window.count != size { window = [Float](repeating: 0, count: size) }
        // Centred on the moment heard, so the picture is neither early nor late.
        guard sound.copy(around: time, into: &window) else { return nil }
        return analyzer.decibels(of: window)
    }

    // MARK: - Hearing a song

    /// Gives a song's player item a tap that hands its sound to the meter. The item plays just
    /// as before; the tap only listens.
    @MainActor
    static func attach(to item: AVPlayerItem, asset: AVAsset) {
        Task { @MainActor in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return }
            let sound = Sound()
            guard let tap = makeTap(for: sound) else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
            shared.songs.append(Song(item: item, sound: sound))
        }
    }

    private static func makeTap(for sound: Sound) -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(sound).toOpaque(),
            init: { _, clientInfo, storage in
                storage.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<Sound>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<Sound>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                var range = CMTimeRange.invalid
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, &range, framesOut) == noErr,
                      AudioLevelMeter.shared.isListening else { return }
                let sound = Unmanaged<Sound>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                sound.hear(buffers, frames: Int(framesOut.pointee), at: range.start)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }
}

/// One song's sound: the last few seconds of it, both channels mixed to one, and where in the
/// song they are. Written on the audio thread, without allocating; read when a frame's drawn.
private nonisolated final class Sound: @unchecked Sendable {
    private struct Ring {
        var samples: [Float] = []
        var sampleRate: Double = 0
        var channels = 1
        var isInterleaved = false
        var isFloat = false
        /// Samples written, all told; the newest is at `written - 1`.
        var written = 0
        /// The song's time just after the newest sample.
        var end: Double = 0
        /// The first sample of the current run: before it, the song was somewhere else.
        var runStart = 0
    }

    private let ring = OSAllocatedUnfairLock(initialState: Ring())

    var sampleRate: Double? {
        ring.withLock { $0.sampleRate > 0 && !$0.samples.isEmpty ? $0.sampleRate : nil }
    }

    /// Sets aside about three seconds: enough for what AVFoundation hands over ahead of the
    /// speakers, and AirPlay's longer wait.
    func prepare(_ format: AudioStreamBasicDescription) {
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        var capacity = 1 << 16
        while Double(capacity) < rate * 3 { capacity <<= 1 }
        ring.withLockUnchecked { ring in
            ring = Ring()
            ring.samples = [Float](repeating: 0, count: capacity)
            ring.sampleRate = rate
            ring.channels = max(1, Int(format.mChannelsPerFrame))
            ring.isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            ring.isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        }
    }

    /// Copies a moment of sound in, its channels mixed to one. On the audio thread.
    func hear(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int, at start: CMTime) {
        guard frames > 0 else { return }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        ring.withLockUnchecked { ring in
            guard ring.isFloat, !ring.samples.isEmpty else { return }
            let time = start.isNumeric ? start.seconds : ring.end
            // A seek, or the first sound after a while unheard: a new run.
            if abs(time - ring.end) * ring.sampleRate > 2 {
                ring.runStart = ring.written
            }
            let capacity = ring.samples.count
            let mask = capacity - 1
            let channels = ring.channels
            let isInterleaved = ring.isInterleaved
            let written = ring.written
            ring.samples.withUnsafeMutableBufferPointer { out in
                if isInterleaved, let data = list.first?.mData {
                    let input = data.assumingMemoryBound(to: Float.self)
                    let share = 1 / Float(channels)
                    for frame in 0..<frames {
                        var sum: Float = 0
                        for channel in 0..<channels { sum += input[frame * channels + channel] }
                        out[(written + frame) & mask] = sum * share
                    }
                } else {
                    let present = list.reduce(0) { $0 + ($1.mData == nil ? 0 : 1) }
                    let share = 1 / Float(max(1, present))
                    for frame in 0..<frames { out[(written + frame) & mask] = 0 }
                    for buffer in list {
                        guard let data = buffer.mData else { continue }
                        let input = data.assumingMemoryBound(to: Float.self)
                        for frame in 0..<frames { out[(written + frame) & mask] += input[frame] * share }
                    }
                }
            }
            ring.written += frames
            ring.end = time + Double(frames) / ring.sampleRate
        }
    }

    /// Fills `window` with the sound around `time` in the song. False if that moment isn't
    /// here: not yet handed over, long gone, or from before a seek.
    func copy(around time: Double, into window: inout [Float]) -> Bool {
        ring.withLockUnchecked { ring in
            guard ring.sampleRate > 0, ring.written > 0 else { return false }
            let size = window.count
            let capacity = ring.samples.count
            let oldest = max(ring.runStart, ring.written - capacity)
            // The sample being heard, then the window around it, slid back to what's arrived.
            let heard = ring.written - Int(((ring.end - time) * ring.sampleRate).rounded())
            var first = min(heard - size / 2, ring.written - size)
            if first < oldest {
                // Over a quarter of a second off, it's not this moment any more.
                guard oldest - first < Int(ring.sampleRate / 4), ring.written - oldest >= size else { return false }
                first = oldest
            }
            guard heard > oldest - Int(ring.sampleRate / 4), heard < ring.written + Int(ring.sampleRate / 4) else { return false }
            let mask = capacity - 1
            ring.samples.withUnsafeBufferPointer { samples in
                window.withUnsafeMutableBufferPointer { out in
                    for index in 0..<size { out[index] = samples[(first + index) & mask] }
                }
            }
            return true
        }
    }
}
