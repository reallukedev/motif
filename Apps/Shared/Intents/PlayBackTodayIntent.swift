import AppIntents
import MotifCore
import MotifMusic

/// Plays back today's captures.
///
/// Runs in the foreground so playback starts from the app. Run in the background (from the
/// widget, say), its process can be terminated as soon as the intent returns.
struct PlayBackTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Back Today"
    static let description = IntentDescription(
        "Plays the songs Motif captured today, so Apple Music logs them as real plays.",
        categoryName: "Playback"
    )

    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try MotifStore.shared()
        let controller = PlaybackController(store: store, service: PlatformPlaybackService.make())
        await controller.playBackToday()

        if let error = controller.lastError {
            return .result(dialog: IntentDialog(stringLiteral: error))
        }
        return .result(dialog: "^[Playing \(controller.queuedCount) song](inflect: true).")
    }
}
