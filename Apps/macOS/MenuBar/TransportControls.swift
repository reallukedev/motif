import SwiftUI
import MotifCore

/// Previous, play/pause and next for whichever player is currently playing. The monitor
/// reads the state back after each command, so the glyphs follow the player.
struct TransportControls: View {
    let monitor: NowPlayingMonitor

    private var isPlaying: Bool {
        monitor.target.map { monitor.presence(of: $0).isPlaying } ?? false
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                button(.previous, symbol: "backward.fill", label: "Previous Track")
                button(
                    .playPause,
                    symbol: isPlaying ? "pause.fill" : "play.fill",
                    label: isPlaying ? "Pause" : "Play"
                )
                .controlSize(.extraLarge)
                button(.next, symbol: "forward.fill", label: "Next Track")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                monitor.target.map { "Playback controls for \($0.displayName)" } ?? "Playback controls"
            )

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
        guard monitor.target == .music, monitor.music.isRadio else { return nil }
        return "A radio station can't be skipped."
    }

    /// Uses a real title hidden by the label style, so VoiceOver has something to read.
    private func button(
        _ command: TransportCommand,
        symbol: String,
        label: String
    ) -> some View {
        let allowed = monitor.capabilities.allows(command)
        return Button(label, systemImage: symbol) {
            monitor.perform(command)
        }
        .labelStyle(.iconOnly)
        .disabled(!allowed)
        // Music accepts a skip on a station and ignores it without feedback, so explain.
        .help(allowed ? label : reasonUnavailable)
    }

    private var reasonUnavailable: String {
        guard let target = monitor.target else { return "Nothing is playing." }
        if target == .music, monitor.music.isRadio {
            return "A radio station can't be skipped."
        }
        return "Nothing is playing."
    }
}

/// What Spotify is playing, shown when Spotify is the active player. Marked "Not captured"
/// because Motif never saves Spotify plays.
struct SpotifyNowPlayingRow: View {
    let track: SpotifyNowPlaying

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Not captured")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title) by \(track.artistName), playing on Spotify")
        .accessibilityValue("Not captured")
    }

    @ViewBuilder
    private var artwork: some View {
        if let urlString = track.artworkURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: .rect(cornerRadius: 6))
        }
    }
}
