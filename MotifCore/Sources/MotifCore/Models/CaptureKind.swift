import Foundation

/// How a track came to be in the store.
///
/// Stored on `Capture` as a raw `String`: CloudKit needs a default for every persisted
/// property, and a raw-value column migrates more predictably than a codable enum.
public enum CaptureKind: String, Codable, Sendable, CaseIterable {
    /// Heard on a radio station. Apple doesn't count these, so only these go to the
    /// playlist and get offered for play-back.
    case radio
    /// Played on demand. Kept and scrobbled like everything else, but never added to the
    /// playlist since Apple already counted it.
    case onDemand
    /// Read from Apple's recently-played list. It doesn't say how a song was played, so
    /// radio-specific features leave these alone.
    case imported

    /// Whether Motif knows how this was played.
    public var sourceIsKnown: Bool { self != .imported }

    public var name: String {
        switch self {
        case .radio: "Radio"
        case .onDemand: "On demand"
        case .imported: "Imported"
        }
    }
}
