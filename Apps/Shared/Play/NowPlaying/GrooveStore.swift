import AVFoundation
import Foundation
import MusicKit
import Observation
import TracksCore

/// The groove of the song playing (see ``Groove``), for the drawing that moves with music
/// Tracks can't hear.
///
/// Apple Music plays in a process of its own, so Tracks never hears the song itself. Each
/// catalog song has a half-minute preview, though, plain sound anyone may fetch. Tracks
/// fetches it once, listens to it for the song's tempo, its drums and its shape, keeps what it
/// learned (a few hundred bytes) and lets the sound go. Nothing about you goes with the request.
///
/// Only while something that moves with the music is showing; never on an expensive or Low
/// Data connection, or in Low Power Mode, when the drawing keeps a gentle beat by the song's
/// feel instead. Sample songs make no sound, so each gets a groove made up from its name.
@MainActor
@Observable
final class GrooveStore {
    static let shared = GrooveStore()

    /// The groove of the song with ``key``, once it's known.
    private(set) var groove: Groove?
    private(set) var key: String?
    @ObservationIgnored private var work: Task<Void, Never>?

    private init() {}

    /// The groove of `track`, if it's the song this has learned.
    func groove(for track: PlayerTrack?) -> Groove? {
        guard let track, let groove, key == Self.key(for: track) else { return nil }
        return groove
    }

    /// Learns `track`'s groove, if it isn't known yet, and stops learning the last one's.
    func follow(_ track: PlayerTrack?, isDemo: Bool) {
        let key = track.flatMap(Self.key(for:))
        guard key != self.key else { return }
        work?.cancel()
        work = nil
        self.key = key
        groove = nil
        // Your own music is heard as it plays; it needs no groove.
        guard let track, let key, track.local == nil else { return }
        if isDemo {
            groove = .sample(seed: key)
            return
        }
        guard let preview = track.song?.previewAssets?.first?.url else { return }
        let mayDownload = !LowPowerMode.shared.isOn
        work = Task { [weak self] in
            let found = await GrooveFiles.groove(for: key, preview: preview, mayDownload: mayDownload)
            guard !Task.isCancelled, let self, self.key == key else { return }
            self.groove = found
        }
    }

    /// A catalog song by its id, and a sample song by its name.
    private static func key(for track: PlayerTrack) -> String? {
        if let song = track.song { return song.id.rawValue }
        return track.local == nil ? "sample.\(track.songIdentity)" : nil
    }
}

/// Fetching, hearing and keeping grooves, away from the main thread.
private nonisolated enum GrooveFiles {
    /// Kept in Caches, where the system may clear them; one is soon learned again.
    static let folder = URL.cachesDirectory.appending(path: "Grooves", directoryHint: .isDirectory)
    /// About a megabyte at most.
    static let kept = 400

    /// Only on a connection that costs nothing, and not under Low Data Mode.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    @concurrent
    static func groove(for key: String, preview: URL, mayDownload: Bool) async -> Groove? {
        let file = folder.appending(path: "\(fileName(for: key)).json")
        if let data = try? Data(contentsOf: file), let groove = try? JSONDecoder().decode(Groove.self, from: data) {
            // Marked as used, so it's among the last let go.
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
            return groove
        }
        guard mayDownload, let heard = try? await hear(preview), !Task.isCancelled else { return nil }
        let groove = GrooveAnalysis.groove(of: heard.samples, sampleRate: heard.rate, bandCount: AudioLevelMeter.bandCount)
        keep(groove, at: file)
        return groove
    }

    /// The preview's sound, its channels mixed to one.
    private static func hear(_ preview: URL) async throws -> (samples: [Float], rate: Double) {
        let (download, response) = try await session.download(from: preview)
        // AVAudioFile goes by the name's extension to know what it's reading.
        let local = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: download)
            try? FileManager.default.removeItem(at: local)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: download, to: local)
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: local)
        let format = file.processingFormat
        // A preview is half a minute; anything longer isn't one.
        let length = AVAudioFrameCount(min(file.length, Int64(format.sampleRate * 40)))
        guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length) else { throw URLError(.cannotDecodeContentData) }
        try file.read(into: buffer, frameCount: length)
        guard let channels = buffer.floatChannelData else { throw URLError(.cannotDecodeContentData) }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        // Reading always gives one buffer a channel.
        var mono = [Float](repeating: 0, count: count)
        let share = 1 / Float(max(1, channelCount))
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<count { mono[frame] += data[frame] * share }
        }
        return (mono, format.sampleRate)
    }

    private static func keep(_ groove: Groove, at file: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(groove) else { return }
        try? data.write(to: file, options: .atomic)
        // The least lately used go first, once there are too many.
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys), files.count > kept else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (old, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - kept) {
            try? manager.removeItem(at: old)
        }
    }

    /// A key as a file name: letters, digits and dots only.
    private static func fileName(for key: String) -> String {
        String(key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." ? Character($0) : "_" })
    }
}
