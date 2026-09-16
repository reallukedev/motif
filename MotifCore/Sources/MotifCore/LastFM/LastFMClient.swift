import Foundation

public enum LastFMError: Error, Sendable, Equatable {
    /// This build has no Last.fm application configured. See ``LastFMCredentials``.
    case notConfigured
    /// Nobody has connected an account yet.
    case notConnected
    /// The user has not yet approved the token in their browser.
    case notAuthorised
    case http(status: Int)
    /// Last.fm's own error code and message.
    case service(code: Int, message: String)
    case malformedResponse

    /// Whether trying again later could succeed.
    public var isRetryable: Bool {
        switch self {
        case .http(let status): status == 429 || status >= 500
        // 11 service offline, 16 temporarily unavailable, 29 rate limit.
        case .service(let code, _): [11, 16, 29].contains(code)
        case .notConfigured, .notConnected, .notAuthorised, .malformedResponse: false
        }
    }

    /// Whether the failure is down to this build's credentials or the connected account
    /// rather than the scrobbles in the request.
    ///
    /// Not retryable, but not the songs' fault either: charging them an attempt would give up
    /// on a whole queue of listening because a session was revoked, and reconnecting
    /// wouldn't bring it back.
    var concernsAccount: Bool {
        switch self {
        case .notConfigured, .notConnected, .notAuthorised: true
        // 4 authentication failed, 9 invalid session key, 10 invalid API key, 13 invalid
        // signature, 14 and 15 token not authorised or expired, 26 API key suspended.
        case .service(let code, _): [4, 9, 10, 13, 14, 15, 26].contains(code)
        case .http, .malformedResponse: false
        }
    }
}

/// What Last.fm did with one scrobble from a batch.
///
/// A batch that Last.fm takes still answers 200 when it ignored some of the entries. It says
/// so per entry, in `ignoredMessage`, and in the `ignored` count under `@attr`.
public enum ScrobbleOutcome: Sendable, Equatable {
    case accepted
    /// Ignored, with Last.fm's `ignoredMessage` code and text (usually empty).
    case ignored(code: Int, message: String)

    public var isAccepted: Bool { self == .accepted }

    /// Whether sending the same entry later could succeed.
    ///
    /// 4 (timestamp in the future) passes once the clock catches up with it, and 5 (daily
    /// scrobble limit) the next day. 1 and 2 (artist or track ignored) and 3 (timestamp too
    /// old) are about the entry itself and will never pass.
    public var isRetryable: Bool {
        guard case .ignored(let code, _) = self else { return false }
        return code == 4 || code == 5
    }
}

/// One scrobble.
public struct Scrobble: Sendable, Equatable {
    public let artist: String
    public let track: String
    public let album: String?
    public let playedAt: Date

    public init(artist: String, track: String, album: String? = nil, playedAt: Date) {
        self.artist = artist
        self.track = track
        self.album = album
        self.playedAt = playedAt
    }
}

/// Talks to Last.fm.
///
/// Every call is a form-encoded POST signed with `api_sig` (see ``LastFMSignature``).
/// `format=json` gets JSON back and must not be signed.
public struct LastFMClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    /// Last.fm accepts up to fifty scrobbles in one call.
    public static let batchLimit = 50

    let apiKey: String
    let secret: String
    let transport: Transport

    public init(apiKey: String, secret: String, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.apiKey = apiKey
        self.secret = secret
        self.transport = transport
    }

    /// Builds a client from the build's credentials, or nil if this build has none.
    public static func configured(transport: Transport? = nil) -> LastFMClient? {
        guard let apiKey = LastFMCredentials.apiKey, let secret = LastFMCredentials.secret
        else { return nil }
        if let transport { return LastFMClient(apiKey: apiKey, secret: secret, transport: transport) }
        return LastFMClient(apiKey: apiKey, secret: secret)
    }

    // MARK: - Authentication

    /// Step one of the desktop flow: a token to send the user to the browser with.
    public func requestToken() async throws -> String {
        let json = try await call(["method": "auth.getToken"])
        guard let token = json["token"] as? String else { throw LastFMError.malformedResponse }
        return token
    }

    /// Where to send the user to approve the token.
    public func authorisationURL(for token: String) -> URL {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")!
    }

    /// Step two: exchange an approved token for a session key that never expires.
    ///
    /// Throws ``LastFMError/notAuthorised`` until the user clicks Allow in the browser; the
    /// caller keeps polling.
    public func session(for token: String) async throws -> LastFMSession {
        do {
            let json = try await call(["method": "auth.getSession", "token": token])
            guard let session = json["session"] as? [String: Any],
                  let name = session["name"] as? String,
                  let key = session["key"] as? String
            else { throw LastFMError.malformedResponse }
            return LastFMSession(username: name, sessionKey: key)
        } catch LastFMError.service(let code, let message) {
            // 14 is "unauthorized token", 15 "token has expired".
            throw code == 14 ? LastFMError.notAuthorised : LastFMError.service(code: code, message: message)
        }
    }

    // MARK: - Scrobbling

    /// Sends up to ``batchLimit`` scrobbles in one call.
    ///
    /// - Returns: how many Last.fm accepted. See ``submit(_:session:)`` for which.
    @discardableResult
    public func scrobble(_ scrobbles: [Scrobble], session: LastFMSession) async throws -> Int {
        try await submit(scrobbles, session: session).filter(\.isAccepted).count
    }

    /// Sends up to ``batchLimit`` scrobbles in one call and reports what became of each.
    ///
    /// Batch parameters are indexed (`artist[0]`, `track[0]`) and all of them are signed.
    ///
    /// - Returns: one outcome per scrobble sent, in the order given.
    public func submit(_ scrobbles: [Scrobble], session: LastFMSession) async throws -> [ScrobbleOutcome] {
        guard !scrobbles.isEmpty else { return [] }
        var parameters: [String: String] = [
            "method": "track.scrobble",
            "sk": session.sessionKey,
        ]
        for (index, scrobble) in scrobbles.prefix(Self.batchLimit).enumerated() {
            parameters["artist[\(index)]"] = scrobble.artist
            parameters["track[\(index)]"] = scrobble.track
            parameters["timestamp[\(index)]"] = String(Int(scrobble.playedAt.timeIntervalSince1970))
            if let album = scrobble.album, !album.isEmpty {
                parameters["album[\(index)]"] = album
            }
        }
        let json = try await call(parameters)
        return try Self.scrobbleOutcomes(from: json, sent: min(scrobbles.count, Self.batchLimit))
    }

    /// Reads the per-entry result out of a `track.scrobble` response.
    ///
    /// `scrobbles.scrobble` is an array for a batch but a lone object when one scrobble was
    /// sent, and the codes come back as strings (`"0"`) as often as numbers. Entries are in
    /// the order they were sent.
    static func scrobbleOutcomes(from json: [String: Any], sent count: Int) throws -> [ScrobbleOutcome] {
        guard let report = json["scrobbles"] as? [String: Any] else {
            // A 200 that says nothing about the entries. Last.fm reports errors in the body,
            // and `call` has already checked for one, so it took them.
            return Array(repeating: .accepted, count: count)
        }

        let entries: [[String: Any]] = switch report["scrobble"] {
        case let many as [[String: Any]]: many
        case let one as [String: Any]: [one]
        default: []
        }
        if entries.count == count {
            return entries.map(outcome(of:))
        }

        // Can't line the entries up with what was sent. That only matters if some of them
        // were ignored.
        let attributes = report["@attr"] as? [String: Any]
        if integer(attributes?["ignored"]) == 0 {
            return Array(repeating: .accepted, count: count)
        }
        throw LastFMError.malformedResponse
    }

    private static func outcome(of entry: [String: Any]) -> ScrobbleOutcome {
        guard let ignored = entry["ignoredMessage"] as? [String: Any],
              let code = integer(ignored["code"]),
              code != 0
        else { return .accepted }
        return .ignored(code: code, message: ignored["#text"] as? String ?? "")
    }

    /// Last.fm's JSON is converted from XML, so a number can arrive as either.
    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let text as String: Int(text)
        default: nil
        }
    }

    /// Tells Last.fm what's playing. It expires on its own, so failures aren't retried.
    public func updateNowPlaying(_ scrobble: Scrobble, session: LastFMSession) async throws {
        var parameters: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": scrobble.artist,
            "track": scrobble.track,
            "sk": session.sessionKey,
        ]
        if let album = scrobble.album, !album.isEmpty { parameters["album"] = album }
        _ = try await call(parameters)
    }

    // MARK: - Transport

    func call(_ parameters: [String: String]) async throws -> [String: Any] {
        var all = parameters
        all["api_key"] = apiKey
        all["api_sig"] = LastFMSignature.sign(all, secret: secret)
        // After signing: Last.fm rejects a signature that includes `format`.
        all["format"] = "json"

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(all)

        let (data, response) = try await transport(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        // Check the body first. Last.fm's errors usually come with a plain 400.
        if let code = json["error"] as? Int {
            throw LastFMError.service(code: code, message: json["message"] as? String ?? "")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LastFMError.http(status: http.statusCode)
        }
        return json
    }

    static func formBody(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        // `URLComponents` leaves `+` unescaped, and it decodes as a space
        // ("C+C Music Factory" would scrobble as "C C Music Factory").
        let encoded = (components.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(encoded.utf8)
    }
}
