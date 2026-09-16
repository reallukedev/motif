import SwiftUI
import MotifCore

/// Previous, play/pause and next for Music. The monitor reads the state back after each
/// command, so the glyphs follow the player.
struct TransportControls: View {
    let monitor: NowPlayingMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Presses of each skip button, which step its arrows forward once.
    @State private var skips: [TransportCommand: Int] = [:]

    private var isPlaying: Bool { monitor.music.isPlaying }

    var body: some View {
        VStack(spacing: 6) {
            // Each glyph gets a fixed square, so the circles match and the glyphs sit centred.
            // Sized to the glyph, the wide skip symbols filled their circles edge to edge.
            GlassEffectContainer(spacing: 18) {
                HStack(spacing: 18) {
                    button(.previous, symbol: "backward.fill", label: "Previous Track", glyph: 13, box: 18)
                    button(
                        .playPause,
                        symbol: isPlaying ? "pause.fill" : "play.fill",
                        label: isPlaying ? "Pause" : "Play",
                        glyph: 17,
                        box: 24
                    )
                    button(.next, symbol: "forward.fill", label: "Next Track", glyph: 13, box: 18)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(monitor.music.isRunning ? "Playback controls for Music" : "Playback controls")

            // macOS doesn't show a help tag on a disabled control, so the `.help` below never
            // appears in this case. Spell it out instead.
            if let note = unavailableNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Only for radio. "Nothing is playing" is obvious enough without a caption.
    private var unavailableNote: String? {
        guard monitor.music.isRadio else { return nil }
        return "A radio station can't be skipped."
    }

    /// Uses a real title hidden by the label style, so VoiceOver has something to read.
    private func button(
        _ command: TransportCommand,
        symbol: String,
        label: String,
        glyph: CGFloat,
        box: CGFloat
    ) -> some View {
        let allowed = monitor.capabilities.allows(command)
        return Button {
            if command != .playPause, !reduceMotion { skips[command, default: 0] += 1 }
            monitor.perform(command)
        } label: {
            Label {
                Text(label)
            } icon: {
                if command == .playPause {
                    // Play and pause morph into each other whenever the player changes, even
                    // from the keyboard's media keys, as in Music.
                    Image(systemName: symbol)
                        .font(.system(size: glyph, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .snappy, value: symbol)
                } else {
                    SkipGlyph(isForward: command == .next, height: glyph * 0.85, presses: skips[command, default: 0])
                }
            }
            .labelStyle(.iconOnly)
            .frame(width: box, height: box)
        }
        .disabled(!allowed)
        // Space plays and pauses while this window is open, as in Music.
        .keyboardShortcut(command == .playPause ? KeyboardShortcut(.space, modifiers: []) : nil)
        // Music accepts a skip on a station and ignores it without feedback, so explain.
        .help(allowed ? label : reasonUnavailable)
    }

    private var reasonUnavailable: String {
        guard monitor.music.isRunning else { return "Nothing is playing." }
        if monitor.music.isRadio {
            return "A radio station can't be skipped."
        }
        return "Nothing is playing."
    }
}

/// Music's skip glyph: two arrows that step the way they point when pressed. The front arrow
/// shrinks away at its tip, the back one slides into its place, and a new one grows in
/// behind. It ends looking exactly as it started, so it can be pressed again at once. Back
/// is the same glyph mirrored.
private struct SkipGlyph: View {
    let isForward: Bool
    let height: CGFloat
    let presses: Int

    var body: some View {
        let width = height * 0.82
        KeyframeAnimator(initialValue: 1.0, trigger: presses) { step in
            ZStack(alignment: .leading) {
                SkipArrow()
                    .frame(width: width, height: height)
                    .scaleEffect(step, anchor: .leading)
                SkipArrow()
                    .frame(width: width, height: height)
                    .offset(x: step * width)
                SkipArrow()
                    .frame(width: width, height: height)
                    .scaleEffect(1 - step, anchor: .trailing)
                    .offset(x: width)
            }
            .frame(width: width * 2, height: height, alignment: .leading)
        } keyframes: { _ in
            KeyframeTrack {
                // Restart from the resting pose, then step once.
                MoveKeyframe(0)
                SpringKeyframe(1, duration: 0.38, spring: .snappy)
            }
        }
        .scaleEffect(x: isForward ? 1 : -1)
        .accessibilityHidden(true)
    }
}

/// One arrow of ``SkipGlyph``. The play symbol, so it's drawn and tinted exactly like the
/// glyph beside it; a filled custom shape lost its fill in the glass button.
private struct SkipArrow: View {
    var body: some View {
        Image(systemName: "play.fill")
            .resizable()
            .fontWeight(.semibold)
    }
}
