import SwiftUI
import Observation
import MotifCore
import MotifMusic

/// What Music and Spotify are doing, for the menu bar's Now Playing card.
///
/// Separate from ``CaptureService`` so it keeps working while capture is paused. It can't
/// cause a capture: ``SpotifyNowPlaying`` isn't something the coordinator accepts.
@MainActor
@Observable
final class NowPlayingMonitor {
    /// Music's state, and whether what it is playing came from a station.
    private(set) var music: PlayerPresence = .absent

    /// Whether Music has been asked yet. `music` is `.absent` both before the first read and
    /// when Music isn't running, and the card shouldn't flash "Nothing playing" on open.
    private(set) var hasRead = false
    /// Spotify's current track. Nil when Spotify is not running or has nothing loaded.
    private(set) var spotify: SpotifyNowPlaying?

    private let source = SpotifySource()
    private var pump: Task<Void, Never>?

    var spotifyPresence: PlayerPresence {
        // Spotify posts nothing when it quits, so check the process is still there. That
        // costs no Apple event.
        guard SpotifyScripting.isRunning, let spotify else { return .absent }
        return PlayerPresence(state: spotify.playbackState)
    }

    /// The player the transport controls drive.
    var target: MediaApp? {
        TransportRouting.target(music: music, spotify: spotifyPresence)
    }

    var capabilities: TransportCapabilities {
        guard let target else { return .none }
        return TransportRouting.capabilities(for: target, presence: presence(of: target))
    }

    func presence(of app: MediaApp) -> PlayerPresence {
        switch app {
        case .music: music
        case .spotify: spotifyPresence
        }
    }

    /// Starts listening to Spotify. It's a single notification registration, so it stays on
    /// and the card is current as soon as the menu bar opens.
    func start() {
        guard pump == nil else { return }
        source.start()
        pump = Task { [weak self, source] in
            // Main-actor isolated like the class. `self` is weak because the stream only
            // ends when the source is torn down, so a strong capture would be a cycle.
            for await update in source.updates {
                guard let self else { return }
                self.spotify = update
            }
        }
    }

    /// Polls Music while the menu bar window is open (driven from its `.task`). The
    /// `playerInfo` notification is only observed while capture runs, and the transport
    /// controls must work without it.
    func follow() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refresh() async {
        music = await ScriptingQueue.run { MusicScripting.presence() }
        hasRead = true

        if !SpotifyScripting.isRunning {
            spotify = nil
        } else if spotify == nil {
            // Spotify may have been playing before Motif launched.
            spotify = await ScriptingQueue.run { SpotifyScripting.nowPlaying() }
        }
    }

    /// Sends a transport command to whichever player is playing.
    func perform(_ command: TransportCommand) {
        guard let target, capabilities.allows(command) else { return }
        Task {
            _ = await ScriptingQueue.run { MediaTransportControl.perform(command, on: target) }
            // Read the state back, since a station can refuse a skip.
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
        }
    }
}
