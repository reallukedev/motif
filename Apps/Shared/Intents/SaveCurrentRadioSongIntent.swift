import AppIntents
import MotifCore

/// Saves whatever radio song is playing right now.
///
/// iOS suspends the app soon after it leaves the foreground and there's no supported way to
/// observe the system player while suspended, so with the app closed this intent is the only
/// way to capture. The Action Button, Back Tap and Control Centre all invoke it.
struct SaveCurrentRadioSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Current Radio Song"
    static let description = IntentDescription(
        "Adds the radio song playing right now to your Heard on Radio playlist.",
        categoryName: "Capture"
    )

    /// Runs without bringing the app forward.
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try MotifStore.shared()
        // Created before capturing so the capture counts as a change.
        let widgets = WidgetRefresher.shared
        let service = CaptureService(store: store)
        let decision = await service.captureCurrentSong()
        // Reload now, since the process is suspended soon after a background intent returns.
        widgets?.reloadIfChanged()

        switch decision {
        case .capture:
            guard let capture = service.lastCapture else {
                return .result(dialog: "Saved.")
            }
            return .result(dialog: "Saved \(capture.title) by \(capture.artistName).")

        case .ignore(let reason):
            return .result(dialog: IntentDialog(stringLiteral: Self.explain(reason)))
        }
    }

    /// A sentence for each reason a capture was rejected, so the shortcut never just does
    /// nothing.
    static func explain(_ reason: CaptureDecision.Reason) -> String {
        switch reason {
        case .notPlaying:
            "Nothing is playing right now."
        case .onDemand:
            "That song is playing on demand, so Apple Music already logs it."
        case .duplicate:
            "That one's already saved."
        case .stationAnnouncement(let name):
            "\(name) is still starting up. Try again once a song is playing."
        case .excludedStation(let name):
            "\(name) is excluded in Settings."
        case .unidentifiable:
            "Couldn't tell what's playing."
        case .tooShort(_, let needs):
            // Only reachable if the capture stops being forced.
            "That's only just started. It counts after ^[\(Int(needs)) second](inflect: true)."
        }
    }
}

/// Exposes the intent to Spotlight and Siri with spoken phrases.
struct MotifShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveCurrentRadioSongIntent(),
            phrases: [
                "Save this song with \(.applicationName)",
                "Save this radio song with \(.applicationName)",
                "\(.applicationName) save this track",
            ],
            shortTitle: "Save Radio Song",
            systemImageName: "radio"
        )
    }
}
