import Foundation
import MotifCore

extension PlayPreferences {
    /// Motif Radio follows the time of day: what you play at this hour, with energy that
    /// follows the day. On by default.
    static let radioFollowsTimeKey = "motifRadioFollowsTime"

    static var radioFollowsTime: Bool {
        UserDefaults.standard.object(forKey: radioFollowsTimeKey) as? Bool ?? true
    }

    /// How Motif Radio feels through the day, when it follows the time of day: a
    /// ``RadioDay`` as JSON. Empty is the standard day, calm at night.
    static let radioDayKey = "motifRadioDay"

    static var radioDay: RadioDay {
        RadioDay(stored: UserDefaults.standard.string(forKey: radioDayKey) ?? "")
    }

    /// Motif Radio notices when you're driving and plays for the road. On by default, on
    /// iPhone only: a Mac doesn't drive.
    static let radioNoticesDrivingKey = "motifRadioNoticesDriving"

    static var radioNoticesDriving: Bool {
        #if os(iOS)
        UserDefaults.standard.object(forKey: radioNoticesDrivingKey) as? Bool ?? true
        #else
        false
        #endif
    }
}
