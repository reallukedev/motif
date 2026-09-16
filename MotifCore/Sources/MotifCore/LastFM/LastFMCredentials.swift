import Foundation

/// Motif's Last.fm API key and shared secret.
///
/// These identify the app, not the user. They're read from Info.plist, filled in from the
/// xcconfig, so the repository carries no secret. The user's session key is in
/// ``LastFMSession``.
public enum LastFMCredentials {
    public static let apiKeyInfoPlistKey = "MotifLastFMAPIKey"
    public static let secretInfoPlistKey = "MotifLastFMSecret"

    /// Nil when this build has no Last.fm application configured.
    public static var apiKey: String? { infoPlistValue(apiKeyInfoPlistKey) }
    public static var secret: String? { infoPlistValue(secretInfoPlistKey) }

    public static var isConfigured: Bool { apiKey != nil && secret != nil }

    private static func infoPlistValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              // An unresolved build setting leaves the `$(…)` literal behind.
              !value.contains("$(")
        else { return nil }
        return value
    }
}
