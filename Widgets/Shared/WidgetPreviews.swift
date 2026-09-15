import SwiftUI
import WidgetKit

// Every state of the Today widget at both sizes, since the widget process is hard to watch.

#Preview("Medium · Up Next", as: .systemMedium) {
    TodayOnRadioWidget()
} timeline: {
    CaptureEntry.sample(capacity: .today(family: .systemMedium, showsUpNext: true))
    CaptureEntry.caughtUp(capacity: .today(family: .systemMedium, showsUpNext: true))
}

#Preview("Medium · Up Next off", as: .systemMedium) {
    TodayOnRadioWidget()
} timeline: {
    CaptureEntry.sample(capacity: .today(family: .systemMedium, showsUpNext: false))
}

#Preview("Large · Up Next", as: .systemLarge) {
    TodayOnRadioWidget()
} timeline: {
    CaptureEntry.sample(capacity: .today(family: .systemLarge, showsUpNext: true))
    CaptureEntry.caughtUp(capacity: .today(family: .systemLarge, showsUpNext: true))
}

#Preview("Large · Up Next off", as: .systemLarge) {
    TodayOnRadioWidget()
} timeline: {
    CaptureEntry.sample(capacity: .today(family: .systemLarge, showsUpNext: false))
}

#Preview("Last Played", as: .systemSmall) {
    LastCapturedWidget()
} timeline: {
    CaptureEntry.sample(capacity: .lastPlayed)
}

private extension CaptureEntry {
    /// A day with listening in it and nothing left to play back.
    static func caughtUp(capacity: WidgetCapacity) -> CaptureEntry {
        let sample = CaptureEntry.sample(capacity: capacity)
        return CaptureEntry(
            date: sample.date,
            lastPlayed: sample.lastPlayed,
            today: sample.today,
            upNext: UpNextQueue(songs: [], totalCount: 0),
            isStoreReadable: true
        )
    }
}
