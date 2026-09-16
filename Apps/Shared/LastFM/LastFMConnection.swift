import SwiftUI
import Observation
import MotifCore

/// Walks the user through connecting a Last.fm account.
///
/// Last.fm's desktop flow: get a token, have the user approve it in a browser, then exchange
/// it for a session key that never expires. Nothing signals approval, so the exchange is
/// polled, and "not approved yet" is expected until they press Allow.
@MainActor
@Observable
final class LastFMConnection {
    enum State: Equatable {
        case idle
        case waitingForBrowser
        case connected(username: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var poll: Task<Void, Never>?
    private var pageClosedAt: Date?

    /// How long to keep asking. Long enough to find the tab, log in, and read the page.
    private static let timeout: TimeInterval = 180
    private static let interval: TimeInterval = 3

    init() {
        if let session = LastFMSessionStore.current {
            state = .connected(username: session.username)
        }
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// Starts the flow. `present` shows the approval page and polling runs alongside it,
    /// cancelling the page once approval arrives.
    ///
    /// - Parameter waitsForPage: true when `present` returns only once the page is closed (the
    ///   in-app sheet on iOS), so closing it without approving ends the attempt.
    func connect(waitsForPage: Bool = false, present: @escaping @MainActor (URL) async -> Void) {
        guard let client = LastFMClient.configured() else {
            state = .failed(String(localized: "Last.fm isn't set up in this build of Motif."))
            return
        }
        poll?.cancel()
        state = .waitingForBrowser

        poll = Task { [weak self] in
            do {
                let token = try await client.requestToken()
                self?.pageClosedAt = nil
                let page = Task { [weak self] in
                    await present(client.authorisationURL(for: token))
                    self?.pageClosedAt = .now
                }
                defer { page.cancel() }

                let deadline = Date.now.addingTimeInterval(Self.timeout)
                while Date.now < deadline {
                    try? await Task.sleep(for: .seconds(Self.interval))
                    if Task.isCancelled { return }
                    do {
                        let session = try await client.session(for: token)
                        LastFMSessionStore.save(session)
                        self?.state = .connected(username: session.username)
                        return
                    } catch LastFMError.notAuthorised {
                        // Normal until they press Allow. A couple more tries after the sheet
                        // closes, in case they approved just before closing it.
                        if waitsForPage, let closed = self?.pageClosedAt,
                           Date.now.timeIntervalSince(closed) > 2 * Self.interval {
                            self?.state = .idle
                            return
                        }
                        continue
                    }
                }
                self?.state = .failed(String(localized: "Timed out waiting for Last.fm. Try again."))
            } catch {
                self?.state = .failed(ScrobbleService.describe(error))
            }
        }
    }

    func disconnect() {
        poll?.cancel()
        poll = nil
        LastFMSessionStore.clear()
        state = .idle
    }
}
