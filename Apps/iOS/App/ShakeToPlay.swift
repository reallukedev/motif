import SwiftUI
import UIKit

extension Notification.Name {
    /// iPhone was shaken, with no text being edited, where a shake means Undo.
    static let motifDidShake = Notification.Name("MotifDidShake")
}

extension UIWindow {
    /// Shakes reach the window when nothing closer takes them, as a text field does for Undo.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: .motifDidShake, object: nil)
    }
}

extension View {
    /// Shake to Play: a shake plays a song Motif thinks you'd like, then Motif Radio on from it,
    /// whichever music is the source. Once every few seconds, so one long shake is one song.
    /// - Parameter onPlay: once the song is playing, to show it: the app opens Now Playing.
    func shakeToPlay(_ player: PlayerModel, onPlay: @escaping () -> Void) -> some View {
        modifier(ShakeToPlay(player: player, onPlay: onPlay))
    }
}

private struct ShakeToPlay: ViewModifier {
    let player: PlayerModel
    let onPlay: () -> Void
    @State private var lastShake = Date.distantPast
    @State private var shakes = 0

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .motifDidShake)) { _ in
                guard PlayPreferences.shakeToPlay, Date.now.timeIntervalSince(lastShake) > 3 else { return }
                lastShake = .now
                shakes += 1
                Task {
                    if await player.playSomethingNew() { onPlay() }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: shakes)
    }
}
