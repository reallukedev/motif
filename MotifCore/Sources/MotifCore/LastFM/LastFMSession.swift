import Foundation
import Security

/// The user's Last.fm session key.
///
/// It never expires and is enough to scrobble as the user, so it's kept in the Keychain,
/// not in the App Group defaults every extension can read. Only the username goes there.
public struct LastFMSession: Sendable, Equatable {
    public let username: String
    public let sessionKey: String

    public init(username: String, sessionKey: String) {
        self.username = username
        self.sessionKey = sessionKey
    }
}

public enum LastFMSessionStore {
    // Renaming either signs every existing user out of Last.fm.
    static let service = "com.luke.motif.lastfm"
    static let usernameKey = "MotifLastFMUsername"

    /// Where the username lives, so settings can show who's connected without the Keychain.
    static var defaults: UserDefaults {
        AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public static var current: LastFMSession? {
        guard let username = defaults.string(forKey: usernameKey),
              let key = readKey(for: username)
        else { return nil }
        return LastFMSession(username: username, sessionKey: key)
    }

    public static func save(_ session: LastFMSession) {
        var query = baseQuery(for: session.username)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(session.sessionKey.utf8)
        // The app can launch at login before the first unlock.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
        defaults.set(session.username, forKey: usernameKey)
    }

    public static func clear() {
        if let username = defaults.string(forKey: usernameKey) {
            SecItemDelete(baseQuery(for: username) as CFDictionary)
        }
        defaults.removeObject(forKey: usernameKey)
    }

    static func baseQuery(for username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
        ]
    }

    static func readKey(for username: String) -> String? {
        var query = baseQuery(for: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }
}
