import SwiftUI
import Observation
import MotifCore
import MotifMusic

/// What Music is doing, for the menu bar's Now Playing card.
///
/// Separate from ``CaptureService`` so it keeps working while capture is paused.
@MainActor
@Observable
final class NowPlayingMonitor {
    /// Music's state, and whether what it is playing came from a station.
    private(set) var music: PlayerPresence = .absent

    /// Whether Music has been asked yet. `music` is `.absent` both before the first read and
    /// when Music isn't running, and the card shouldn't flash "Nothing playing" on open.
    private(set) var hasRead = false

    var capabilities: TransportCapabilities {
        TransportRouting.capabilities(presence: music)
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
    }

    /// Sends a transport command to Music.
    func perform(_ command: TransportCommand) {
        guard capabilities.allows(command) else { return }
        Task {
            _ = await ScriptingQueue.run { MediaTransportControl.perform(command) }
            // Read the state back, since a station can refuse a skip.
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
        }
    }
}
