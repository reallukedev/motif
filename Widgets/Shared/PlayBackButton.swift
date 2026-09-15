import SwiftUI
import AppIntents

/// Plays back today's radio songs. Sits on Up Next when it's showing, otherwise on Today.
struct PlayBackButton: View {
    var body: some View {
        Button(intent: PlayBackTodayIntent()) {
            Label("Play", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        // "Play" alone doesn't say what will play when read out.
        .accessibilityLabel("Play Back Today")
    }
}
