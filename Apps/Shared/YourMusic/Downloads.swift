import Foundation
import Observation
import TracksCore

/// Songs downloaded from your servers to play without a connection: the original files, FLAC
/// and all, or a smaller copy the server makes, as Download Quality asks. Downloads carry on
/// in the background, and with the app closed.
@MainActor
@Observable
final class Downloads {
    /// A song kept on this iPhone.
    struct Item: Codable, Sendable {
        let track: LocalTrack
        /// Its name in the downloads folder.
        let fileName: String
        let bytes: Int64
        let downloadedAt: Date
        /// The bit rate the download asked the server for. Nil asked for the original file, as
        /// every download did before Download Quality.
        var requestedBitRate: Int?
        /// What the file turned out to be, read once it landed. Nil for downloads from before
        /// that was read, which are the original files.
        var format: AudioFormat?

        /// The song as it is on this iPhone: its format the file's, where that's known.
        var keptTrack: LocalTrack {
            guard let format else { return track }
            var kept = track
            kept.format = format
            return kept
        }

        /// A smaller copy rather than the original.
        var isSmallerCopy: Bool {
            guard let format else { return false }
            return AudioQuality(LocalPlayback(route: .downloaded(requestedBitRate: requestedBitRate), original: track.format, actual: format))
                .map { if case .converted = $0.reason { true } else { false } } ?? false
        }
    }

    private(set) var items: [String: Item] = [:]
    /// Songs on their way, by track id, from 0 to 1.
    private(set) var progress: [String: Double] = [:]
    /// Called with each song once it's downloaded.
    @ObservationIgnored var onDownloaded: ((LocalTrack) -> Void)?
    /// Songs that couldn't be downloaded, by track id, with why.
    private(set) var failures: [String: String] = [:]

    /// Whether downloads may use cellular data. On unless turned off; off, they wait for Wi-Fi.
    static let cellularKey = "yourMusicDownloadsOverCellular"

    static var allowsCellular: Bool {
        UserDefaults.standard.object(forKey: cellularKey) as? Bool ?? true
    }

    @ObservationIgnored private let servers: MusicServers
    /// A download under way: the song, and the attempt, so a late word from an attempt that
    /// was stopped or replaced is ignored.
    struct Pending: Codable, Sendable {
        let track: LocalTrack
        let attempt: String
        /// The bit rate asked for, or nil for the original file.
        var requestedBitRate: Int?
    }

    @ObservationIgnored private var pending: [String: Pending] = [:]
    /// Attempts stopped on purpose, whose cancellation isn't a failure.
    @ObservationIgnored private var stoppedAttempts: Set<String> = []
    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    @ObservationIgnored private let delegate = DownloadDelegate()
    /// iOS hands this over when it wakes Tracks to finish downloads, and wants it called when
    /// they've been dealt with.
    @ObservationIgnored var backgroundCompletion: (() -> Void)?

    static let sessionIdentifier = "com.luke.tracks.downloads"
    private static var recordURL: URL { LibraryFolders.index.appending(path: "downloads.json") }
    private static var pendingURL: URL { LibraryFolders.index.appending(path: "downloads-pending.json") }

    init(servers: MusicServers) {
        self.servers = servers
        items = Self.load(Self.recordURL) ?? [:]
        pending = Self.load(Self.pendingURL) ?? [:]
        // Files deleted behind Tracks’ back aren't downloaded any more.
        items = items.filter { FileManager.default.fileExists(atPath: Self.fileURL($0.value.fileName).path(percentEncoded: false)) }
        delegate.owner = self
        // Picks up downloads still running from before.
        _ = session
        Task { await restoreProgress() }
    }

    // MARK: - Asking

    func isDownloaded(_ trackID: String) -> Bool { items[trackID] != nil }

    func isDownloading(_ trackID: String) -> Bool { progress[trackID] != nil }

    /// Where a downloaded song is on this iPhone.
    func fileURL(for trackID: String) -> URL? {
        items[trackID].map { Self.fileURL($0.fileName) }
    }

    /// How a downloaded song reaches the player, for the quality badge.
    func playback(for trackID: String) -> LocalPlayback? {
        items[trackID].map {
            LocalPlayback(route: .downloaded(requestedBitRate: $0.requestedBitRate), original: $0.track.format, actual: $0.format)
        }
    }

    var totalBytes: Int64 { items.values.map(\.bytes).reduce(0, +) }

    /// Every downloaded song, as your own.
    var tracks: [LocalTrack] { items.values.map(\.track) }

    // MARK: - Downloading

    /// Starts downloading songs from their servers, the ones not already here, at the Download
    /// Quality set now: the original file, or a smaller copy the server makes as it sends it.
    func download(_ tracks: [LocalTrack]) {
        onAsked?(tracks)
        start(tracks)
    }

    /// Called with the songs each ``download(_:)`` asks for, before they start: Your Music
    /// hears which ones are wanted to keep, as against the ones Tracks Radio gets ready.
    @ObservationIgnored var onAsked: (([LocalTrack]) -> Void)?

    /// Downloads songs, as asked already: again after a change of setting, or a retry.
    private func start(_ tracks: [LocalTrack]) {
        let allowsCellular = Self.allowsCellular
        let bitRate = StreamQuality.download.maxBitRate
        for track in tracks {
            guard case .server(let serverID, let songID) = track.origin,
                  items[track.id] == nil, progress[track.id] == nil,
                  let client = servers.client(for: serverID)
            else { continue }
            let url = bitRate.map { client.streamURL(songID: songID, maxBitRate: $0) } ?? client.downloadURL(songID: songID)
            var request = URLRequest(url: url)
            request.allowsCellularAccess = allowsCellular
            request.allowsExpensiveNetworkAccess = allowsCellular
            let attempt = UUID().uuidString
            let task = session.downloadTask(with: request)
            task.taskDescription = Self.describe(trackID: track.id, attempt: attempt)
            pending[track.id] = Pending(track: track, attempt: attempt, requestedBitRate: bitRate)
            progress[track.id] = 0
            failures[track.id] = nil
            task.resume()
        }
        Self.save(pending, to: Self.pendingURL)
    }

    /// Whether a download is queued and hasn't started: waiting for Wi-Fi, with cellular off.
    func isWaitingForWiFi(_ trackID: String, onCellular: Bool) -> Bool {
        onCellular && !Self.allowsCellular && progress[trackID] == 0
    }

    /// Downloading over cellular was turned on or off: the downloads that haven't started are
    /// asked for again under the new rule, so ones waiting for Wi-Fi start at once, or ones
    /// about to start on cellular wait.
    func cellularSettingChanged() {
        let notStarted = pending.filter { progress[$0.key] == 0 }
        guard !notStarted.isEmpty else { return }
        cancel(Set(notStarted.keys))
        start(notStarted.values.map(\.track))
    }

    /// Stops a download under way.
    func cancel(_ trackIDs: Set<String>) {
        // Only these attempts: a download of the same song started again right after is left alone.
        let attempts = Set(trackIDs.compactMap { pending[$0]?.attempt })
        stoppedAttempts.formUnion(attempts)
        session.getAllTasks { tasks in
            for task in tasks {
                guard let (_, attempt) = Self.parse(task.taskDescription), attempts.contains(attempt) else { continue }
                task.cancel()
            }
        }
        for id in trackIDs {
            progress[id] = nil
            pending[id] = nil
        }
        Self.save(pending, to: Self.pendingURL)
    }

    /// Deletes downloaded songs from this iPhone. They stay on the server.
    func remove(_ trackIDs: Set<String>) {
        for id in trackIDs {
            if let item = items.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: Self.fileURL(item.fileName))
            }
            failures[id] = nil
        }
        Self.save(items, to: Self.recordURL)
    }

    func removeAll() {
        cancel(Set(progress.keys))
        remove(Set(items.keys))
        failures = [:]
    }

    func retryFailed() {
        let tracks = failures.keys.compactMap { id in pending[id]?.track ?? catalogTrack(id) }
        failures = [:]
        start(tracks)
    }

    // MARK: - From the session

    fileprivate func didWrite(_ trackID: String, attempt: String, fraction: Double) {
        guard pending[trackID]?.attempt == attempt else { return }
        // Every row showing a download redraws on each write: whole percents are plenty, and
        // the session reports every chunk.
        if let shown = progress[trackID], fraction < 1, fraction - shown < 0.01 { return }
        progress[trackID] = fraction
    }

    fileprivate func didFinish(_ trackID: String, attempt: String, fileName: String?, bytes: Int64, outcome: Outcome) {
        // Stopped on purpose: nothing more to say.
        if stoppedAttempts.remove(attempt) != nil { return }
        let current = pending[trackID]
        // A newer attempt at the same song is under way: this one's word is stale. Its file, if
        // any, has the same name the newer one will land under.
        if let current, current.attempt != attempt { return }
        progress[trackID] = nil
        pending[trackID] = nil
        Self.save(pending, to: Self.pendingURL)
        switch outcome {
        case .finished:
            // After a relaunch the attempt may be gone from memory; the library still knows the song.
            guard let fileName, let track = current?.track ?? catalogTrack(trackID) else { return }
            items[trackID] = Item(track: track, fileName: fileName, bytes: bytes, downloadedAt: .now, requestedBitRate: current?.requestedBitRate)
            failures[trackID] = nil
            Self.save(items, to: Self.recordURL)
            onDownloaded?(track)
            readFormat(of: trackID, fileName: fileName)
        case .failed(let reason):
            failures[trackID] = reason
        }
    }

    enum Outcome: Sendable {
        case finished
        case failed(String)
    }

    /// Reads what a download turned out to be, so it's shown truthfully: the original, or the
    /// smaller copy the server made, or the original sent when a copy was asked for.
    private func readFormat(of trackID: String, fileName: String) {
        let url = Self.fileURL(fileName)
        Task {
            guard let found = await AudioQualityProbe.format(of: url),
                  let item = items[trackID], item.fileName == fileName
            else { return }
            items[trackID]?.format = AudioFormat.settled(actual: found, original: item.track.format)
            Self.save(items, to: Self.recordURL)
        }
    }

    private func catalogTrack(_ id: String) -> LocalTrack? {
        for tracks in servers.catalogs.values {
            if let track = tracks.first(where: { $0.id == id }) { return track }
        }
        return nil
    }

    fileprivate func didFinishBackgroundEvents() {
        backgroundCompletion?()
        backgroundCompletion = nil
    }

    /// Shows the progress of downloads still running from before. Ones that finished while
    /// Tracks wasn't running are reported by the session as it reconnects, so they're left be.
    private func restoreProgress() async {
        let tasks = await session.allTasks
        for task in tasks {
            guard let (id, attempt) = Self.parse(task.taskDescription), pending[id]?.attempt == attempt else { continue }
            let expected = task.countOfBytesExpectedToReceive
            progress[id] = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
        }
    }

    nonisolated static func describe(trackID: String, attempt: String) -> String {
        trackID + "\u{1F}" + attempt
    }

    nonisolated static func parse(_ description: String?) -> (trackID: String, attempt: String)? {
        guard let parts = description?.split(separator: "\u{1F}", maxSplits: 1), parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: - Files

    nonisolated static func fileURL(_ name: String) -> URL {
        LibraryFolders.downloads.appending(path: name)
    }

    /// A safe file name for a track id, which holds colons and a server's own characters.
    nonisolated static func fileName(for trackID: String, suffix: String) -> String {
        let safe = trackID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return String(safe) + "." + (suffix.isEmpty ? "audio" : suffix)
    }

    private static func load<Value: Decodable>(_ url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func save<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The session's delegate. The finished file has to be moved before its callback returns, so
/// that happens here, off the main actor; everything else is handed to ``Downloads``.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    @MainActor weak var owner: Downloads?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, attempt) = Downloads.parse(downloadTask.taskDescription), totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.owner?.didWrite(id, attempt: attempt, fraction: fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, attempt) = Downloads.parse(downloadTask.taskDescription) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            let reason = String(localized: "The server wouldn't send it (\(status)).")
            Task { @MainActor in self.owner?.didFinish(id, attempt: attempt, fileName: nil, bytes: 0, outcome: .failed(reason)) }
            return
        }
        let suffix = Self.suffix(for: downloadTask.response)
        let name = Downloads.fileName(for: id, suffix: suffix)
        let destination = Downloads.fileURL(name)
        let manager = FileManager.default
        try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: destination)
        do {
            try manager.moveItem(at: location, to: destination)
            let bytes = (try? manager.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64) ?? 0
            Task { @MainActor in self.owner?.didFinish(id, attempt: attempt, fileName: name, bytes: bytes, outcome: .finished) }
        } catch {
            let reason = error.localizedDescription
            Task { @MainActor in self.owner?.didFinish(id, attempt: attempt, fileName: nil, bytes: 0, outcome: .failed(reason)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let (id, attempt) = Downloads.parse(task.taskDescription) else { return }
        // A cancel Tracks didn't ask for (the app was quit, say) is a failure, to try again; one it
        // did ask for is ignored by the owner, which knows the attempt was stopped.
        let reason = (error as? URLError)?.code == .cancelled
            ? String(localized: "Stopped before it finished.")
            : error.localizedDescription
        Task { @MainActor in
            self.owner?.didFinish(id, attempt: attempt, fileName: nil, bytes: 0, outcome: .failed(reason))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in self.owner?.didFinishBackgroundEvents() }
    }

    /// The file's own extension, from its type, or else the server's name for it. The type
    /// comes first: a smaller copy is an MP3 whatever the original was called, and a file
    /// with the wrong extension won't play.
    private static func suffix(for response: URLResponse?) -> String {
        switch response?.mimeType {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/aac", "audio/x-m4a": return "m4a"
        case "audio/wav", "audio/x-wav": return "wav"
        default: break
        }
        if let name = response?.suggestedFilename, let ext = name.split(separator: ".").last, ext.count <= 5, name.contains(".") {
            return ext.lowercased()
        }
        return "audio"
    }
}
