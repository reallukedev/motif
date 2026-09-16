import Foundation
import SwiftData

/// Sends captures to Last.fm.
///
/// Like the playlist queue, failures are stored on the row, so a device that was offline
/// catches up when it's back.
@MainActor
public final class ScrobbleService {
    private let store: MotifStore
    private let settings: CaptureSettings
    private let makeClient: @Sendable () -> LastFMClient?
    /// The connected account. The Keychain in the app; injected in tests, which mustn't
    /// touch the developer's own session.
    private let currentSession: @Sendable () -> LastFMSession?

    public private(set) var lastError: String?

    /// The drain in progress, which later callers wait on rather than starting their own.
    ///
    /// The queue is drained from launch, after each capture and from the housekeeping timer,
    /// and each of those can arrive while another drain is waiting on Last.fm with the same
    /// rows. Two drains at once sent every scrobble twice.
    private var running: Task<Int, Never>?
    /// Set when someone asked for a drain while one was running, so rows that turned up
    /// after the running drain last looked get another pass.
    private var wantsAnotherPass = false

    /// Leaves Last.fm alone for a while after a failure that isn't the rows' fault.
    private(set) var backoff = RetryBackoff()
    /// The clock, replaceable so tests can step past the backoff.
    var now: () -> Date = { .now }

    public init(
        store: MotifStore,
        settings: CaptureSettings = CaptureSettings(),
        makeClient: @escaping @Sendable () -> LastFMClient? = { LastFMClient.configured() },
        currentSession: @escaping @Sendable () -> LastFMSession? = { LastFMSessionStore.current }
    ) {
        self.store = store
        self.settings = settings
        self.makeClient = makeClient
        self.currentSession = currentSession
    }

    public var isConnected: Bool { currentSession() != nil }

    /// Sends everything owed, oldest first, in batches.
    ///
    /// Cheap to call any time; does nothing if there's nothing owed, no account, scrobbling
    /// is off, or Last.fm failed recently. If a drain is already running this waits for it,
    /// and it takes one more look at the queue before finishing.
    ///
    /// - Returns: how many scrobbles Last.fm accepted.
    @discardableResult
    public func drain() async -> Int {
        if let running {
            wantsAnotherPass = true
            return await running.value
        }
        let task = Task {
            var sent = 0
            repeat {
                wantsAnotherPass = false
                sent += await drainOnce()
            } while wantsAnotherPass
            // Cleared here rather than by the caller, with nothing in between that can
            // suspend, so a caller can't join a drain that has already finished looking.
            running = nil
            return sent
        }
        running = task
        return await task.value
    }

    private func drainOnce() async -> Int {
        guard settings.scrobblesToLastFM else { return 0 }
        guard let session = currentSession(), let client = makeClient() else { return 0 }
        guard backoff.allows(at: now()) else { return 0 }

        var sent = 0
        // Up to fifty scrobbles per request.
        while true {
            // Saved first, so every row has the identity it will keep.
            try? store.context.save()
            let descriptor = MotifStore.pendingScrobbles(
                includingImported: settings.scrobblesImported,
                limit: LastFMClient.batchLimit
            )
            guard let owed = try? store.context.fetch(descriptor), !owed.isEmpty else { break }

            // Only identities cross the request: the rows may be merged away meanwhile.
            let ids = owed.map(\.persistentModelID)
            let scrobbles = owed.map {
                Scrobble(
                    artist: $0.artistName,
                    track: $0.title,
                    album: $0.albumTitle,
                    playedAt: $0.capturedAt
                )
            }

            let outcomes: [ScrobbleOutcome]
            do {
                outcomes = try await client.submit(scrobbles, session: session)
            } catch {
                let message = Self.describe(error)
                lastError = message
                if Self.isTheScrobblesFault(error) {
                    for capture in store.existingCaptures(ids).values {
                        capture.scrobbleAttempts += 1
                        capture.lastScrobbleError = message
                    }
                    try? store.context.save()
                } else {
                    // Offline, Last.fm down or rate limiting, or an account problem. Nothing
                    // to do with these rows, so they keep their attempts and wait.
                    backoff.recordFailure(at: now())
                }
                // Stop here either way: the next batch would fail the same way.
                return sent
            }

            let rows = store.existingCaptures(ids)
            let stamp = now()
            var heldBack: String?
            for (id, outcome) in zip(ids, outcomes) {
                // Accepted or not, a row merged away while the request was out has nothing
                // left to record it on.
                if outcome.isAccepted { sent += 1 }
                guard let capture = rows[id] else { continue }
                switch outcome {
                case .accepted:
                    capture.scrobbledAt = stamp
                    capture.lastScrobbleError = nil
                case .ignored(let code, let message) where outcome.isRetryable:
                    // Left owed, untouched, for when the limit or the clock allows it.
                    heldBack = Self.describeIgnored(code: code, message: message)
                case .ignored(let code, let message):
                    // Last.fm will never take this one. Give up on it now, with the reason,
                    // which is what the history shows next to it. Marking it scrobbled would
                    // claim a play Last.fm doesn't have.
                    capture.scrobbleAttempts = max(capture.scrobbleAttempts, MotifStore.maxScrobbleAttempts)
                    capture.lastScrobbleError = Self.describeIgnored(code: code, message: message)
                }
            }
            // A save that fails would leave these rows owed, and the loop would send them again.
            guard (try? store.context.save()) != nil else { return sent }

            if let heldBack {
                // Not reset first, so a daily limit that is still in force keeps lengthening
                // the wait instead of being asked about again every thirty seconds.
                lastError = heldBack
                backoff.recordFailure(at: now())
                return sent
            }
            backoff.reset()
            lastError = nil
            if owed.count < LastFMClient.batchLimit { break }
        }
        return sent
    }

    /// Whether a failed request says something about the scrobbles in it, so each is charged
    /// an attempt and eventually given up on.
    ///
    /// Everything else (no network, a timeout, Last.fm down or rate limiting, the account)
    /// would fail any request, and charging the rows would throw away listening because of an
    /// outage.
    static func isTheScrobblesFault(_ error: any Error) -> Bool {
        guard let error = error as? LastFMError else { return false }
        return !error.isRetryable && !error.concernsAccount
    }

    /// Tells Last.fm what's playing. Not queued, since it expires on its own.
    public func updateNowPlaying(title: String, artistName: String, albumTitle: String?) async {
        guard settings.scrobblesToLastFM,
              let session = currentSession(),
              let client = makeClient()
        else { return }
        try? await client.updateNowPlaying(
            Scrobble(artist: artistName, track: title, album: albumTitle, playedAt: .now),
            session: session
        )
    }

    /// Public so the connect flow reports failures in the same words.
    public static func describe(_ error: any Error) -> String {
        guard let error = error as? LastFMError else { return String(describing: error) }
        return switch error {
        case .notConfigured: "This build has no Last.fm API key."
        case .notConnected: "No Last.fm account is connected."
        case .notAuthorised: "Last.fm has not approved this connection yet."
        case .http(let status): "Last.fm returned HTTP \(status)."
        case .service(let code, let message): "Last.fm error \(code): \(message)"
        case .malformedResponse: "Last.fm sent a response Motif could not read."
        }
    }

    /// Why Last.fm ignored one scrobble from a batch, in words for the history.
    public static func describeIgnored(code: Int, message: String) -> String {
        let reason = switch code {
        case 1: "Last.fm ignored the artist."
        case 2: "Last.fm ignored the track."
        case 3: "Too old for Last.fm, which only takes scrobbles from the last two weeks."
        case 4: "Last.fm thinks this was played in the future. Check the date and time."
        case 5: "Last.fm's daily scrobble limit was reached."
        default: "Last.fm ignored this scrobble (code \(code))."
        }
        return message.isEmpty ? reason : "\(reason) \(message)"
    }
}
