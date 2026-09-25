import SwiftUI
import MotifCore

/// What Motif keeps, when a play counts, and mending covers. An iPhone page, and the Mac's
/// History pane.
struct HistorySettingsPage: View {
    @AppStorage(CaptureSettings.capturesOnDemandKey, store: CaptureSettings.sharedDefaults)
    private var keepsOnDemand = true
    @AppStorage(CaptureSettings.importsRecentlyPlayedKey, store: CaptureSettings.sharedDefaults)
    private var recoversRecentlyPlayed = true
    @AppStorage(CaptureSettings.minimumListenKey, store: CaptureSettings.sharedDefaults)
    private var minimumListen: Double = 30
    @AppStorage(CaptureSettings.dedupeWindowKey, store: CaptureSettings.sharedDefaults)
    private var dedupeSeconds: Double = DedupePolicy.default.window
    @AppStorage(SourceScope.separatesKey) private var separatesSources = false
    /// Nil in a preview, where there's no history to ask.
    @Environment(AppModel.self) private var model: AppModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil where capture isn't running at all, as in a preview.
    @Environment(CaptureService.self) private var capture: CaptureService?
    /// The switch's side of the pause, followed both ways with the service's.
    @State private var isPaused = UserDefaults.standard.bool(forKey: CaptureService.pausedKey)

    var body: some View {
        Form {
            SettingsHero(
                "History",
                subtitle: Text(HistorySettingsWords.status(keepsOnDemand: keepsOnDemand, minimumListen: minimumListen)),
                systemImage: "clock.fill",
                tint: .teal
            )
            pauseSection
            keptSection
            countingSection
            statisticsSection
            ArtworkRepairSection()
        }
        .animation(SettingsMotion.row(reduceMotion: reduceMotion), value: recoversRecentlyPlayed)
        .onChange(of: isPaused) { _, paused in
            guard let capture, paused != capture.isPaused else { return }
            if paused { capture.pause() } else { Task { await capture.resume() } }
        }
        .onChange(of: capture?.isPaused) { _, paused in
            // Paused or resumed elsewhere, as from the Mac's menu bar.
            if let paused, paused != isPaused { isPaused = paused }
        }
        #if os(macOS)
        .settingsPane()
        #else
        .settingsPage("History")
        #endif
    }

    // MARK: - Pausing

    private var pauseSection: some View {
        Section {
            SettingsSwitch(
                "Pause History",
                detail: isPaused
                    ? Text("Nothing you play is kept until you turn this off.")
                    : Text("Stop keeping what you play for a while."),
                isOn: $isPaused
            )
        } footer: {
            if isPaused {
                Text("Songs you play now won’t be kept, counted toward your stats or scrobbled, and your music server isn’t told about them. When you resume, Motif won’t fill them in from Recently Played. Your history so far stays as it is.")
                    .contentTransition(.opacity)
            }
        }
    }

    // MARK: - What's kept

    private var keptSection: some View {
        Section {
            SettingsSwitch(
                "Keep Songs Played on Demand",
                detail: keepsOnDemand
                    ? Text("Songs you choose are kept alongside radio.")
                    : Text("Only radio is kept. Songs you choose yourself aren’t."),
                isOn: $keepsOnDemand
            )
            SettingsSwitch(
                "Recover from Recently Played",
                detail: recoversRecentlyPlayed
                    ? Text("When Motif starts, it fills in what you played while it was closed.")
                    : Text("Songs played while Motif was closed aren’t kept."),
                isOn: $recoversRecentlyPlayed
            )
            #if os(iOS)
            if recoversRecentlyPlayed {
                BackgroundRefreshNotice()
            }
            #endif
        } header: {
            Text("What Motif Keeps")
        } footer: {
            #if os(iOS)
            Text(keptFooter)
                .contentTransition(.opacity)
            #endif
        }
    }

    #if os(iOS)
    private var keptFooter: LocalizedStringKey {
        switch (keepsOnDemand, recoversRecentlyPlayed) {
        case (true, true):
            "Motif keeps radio and the songs you choose. It only sees music while it’s open, so it fills in the rest from Apple Music’s Recently Played, which doesn’t say exactly when you played them."
        case (false, true):
            "Motif keeps radio only. It fills in radio it missed from Apple Music’s Recently Played, which doesn’t say exactly when you played them."
        case (true, false):
            "Motif keeps radio and the songs you choose, but only while it’s open."
        case (false, false):
            "Motif keeps radio only, and only while it’s open."
        }
    }
    #endif

    // MARK: - Counting plays

    private var countingSection: some View {
        Section {
            SettingsSliderRow(
                title: "Counts After",
                value: $minimumListen,
                range: 0...120,
                step: 5,
                minimumLabel: Text("0 sec"),
                maximumLabel: Text("2 min"),
                describe: HistorySettingsWords.countsAfterValue
            )
            SettingsSliderRow(
                title: "Same Song Again Within",
                value: dedupeMinutes,
                range: 1...60,
                step: 1,
                minimumLabel: Text("1 min"),
                maximumLabel: Text("60 min"),
                describe: { HistorySettingsWords.windowValue(minutes: $0) }
            )
        } header: {
            Text("Counting Plays")
        } footer: {
            Text("\(HistorySettingsWords.countsAfterFooter(minimumListen)) \(HistorySettingsWords.windowFooter(minutes: dedupeMinutes.wrappedValue))")
                .contentTransition(.opacity)
        }
    }

    // MARK: - Statistics

    private var hasYourMusic: Bool {
        model?.library.history.hasYourMusic ?? false
    }

    private var statisticsSection: some View {
        Section {
            SettingsSwitch(
                "Separate Apple Music and Your Music",
                detail: Text(statisticsWords),
                isOn: $separatesSources
            )
            // Nothing to tell apart until something plays from Your Music. Left on, it can
            // still be turned off.
            .disabled(!hasYourMusic && !separatesSources)
        } header: {
            Text("Statistics")
        } footer: {
            #if os(iOS)
            Text(statisticsWords)
                .contentTransition(.opacity)
            #endif
        }
    }

    private var statisticsWords: LocalizedStringKey {
        if !hasYourMusic {
            "Once you play songs from Your Music, Summary, History and Charts can show them apart from Apple Music."
        } else if separatesSources {
            "Summary, History and Charts can show all your music, or Apple Music or Your Music alone."
        } else {
            "Everything you play counts together."
        }
    }

    /// Stored in seconds, shown in minutes. A stored zero means the default, as
    /// `CaptureSettings.dedupePolicy` reads it.
    private var dedupeMinutes: Binding<Double> {
        Binding(
            get: { (dedupeSeconds > 0 ? dedupeSeconds : DedupePolicy.default.window) / 60 },
            set: { dedupeSeconds = $0 * 60 }
        )
    }
}
