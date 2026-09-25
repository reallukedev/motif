import Foundation

/// The words for Settings ▸ History: what Motif keeps, and when a play counts.
///
/// Pure, so tests pin every sentence and the root row, the page's status line and the Mac
/// pane can never disagree.
public enum HistorySettingsWords {
    /// The root row's value: "All Music" or "Radio Only".
    public static func short(keepsOnDemand: Bool) -> String {
        keepsOnDemand ? String(localized: "All Music") : String(localized: "Radio Only")
    }

    /// The status line: what's kept, then when a play counts.
    public static func status(keepsOnDemand: Bool, minimumListen: TimeInterval) -> String {
        let counting = minimumListen <= 0
            ? String(localized: "counts as soon as a song starts")
            : String(localized: "counts after \(listenLength(minimumListen))")
        return keepsOnDemand
            ? String(localized: "Keeping everything you play · \(counting)")
            : String(localized: "Keeping radio only · \(counting)")
    }

    /// "30 seconds", "1 minute", "1 minute, 30 seconds".
    public static func listenLength(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded())
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    /// The Counts After row's value: "Straight Away" or "30 sec".
    public static func countsAfterValue(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return String(localized: "Straight Away") }
        return Duration.seconds(seconds.rounded())
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    /// What the Counts After position means.
    public static func countsAfterFooter(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else {
            return String(localized: "Every song is kept as soon as it starts, even one you skip straight away.")
        }
        return String(localized: "A song is kept once it has played for \(listenLength(seconds)), so skipping through doesn’t fill your history.")
    }

    /// "10 min", for the Same Song Again row.
    public static func windowValue(minutes: Double) -> String {
        Duration.seconds((minutes * 60).rounded())
            .formatted(.units(allowed: [.minutes], width: .abbreviated))
    }

    /// What the Same Song Again position means.
    public static func windowFooter(minutes: Double) -> String {
        let length = Duration.seconds((minutes * 60).rounded())
            .formatted(.units(allowed: [.minutes], width: .wide))
        return String(localized: "Hearing the same song again within \(length) counts once.")
    }
}
