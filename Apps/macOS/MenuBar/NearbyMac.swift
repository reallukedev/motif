import SwiftUI
import MotifCore
import MotifMusic

/// Your other devices, on the Mac: they see what Music is playing here and can play, pause and
/// skip it; the menu bar shows what they're playing, with their controls.
@MainActor
enum NearbyMac {
    /// Starts listening, and tells your devices what Music is playing while any are connected:
    /// read every few seconds then, and not at all otherwise, since each read is an Apple event.
    static func start(_ model: AppModel) {
        guard !model.isDemoLaunch else { return }
        let nearby = model.nearby
        let player = model.player
        nearby.onCommand = { command in
            Task {
                let presence = await ScriptingQueue.run { MusicScripting.presence() }
                if speaksForMotif(model, musicIsPlaying: presence.isPlaying) {
                    switch command {
                    case .playPause: player.togglePlayPause()
                    case .next: player.skipToNext()
                    case .previous: player.skipToPrevious()
                    }
                } else {
                    _ = await ScriptingQueue.run { MediaTransportControl.perform(command) }
                }
                try? await Task.sleep(for: .milliseconds(400))
                await tell(model)
            }
        }
        nearby.onPause = {
            // The song moved to another device: nothing here keeps playing it.
            if player.isPlaying { player.togglePlayPause() }
            Task {
                let presence = await ScriptingQueue.run { MusicScripting.presence() }
                guard presence.isPlaying else { return }
                _ = await ScriptingQueue.run { MediaTransportControl.pause() }
                await tell(model)
            }
        }
        nearby.onJoin = { Task { await tell(model) } }
        nearby.start()
        Task {
            while !Task.isCancelled {
                if !nearby.devices.isEmpty { await tell(model) }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Whether what this Mac is playing is Motif's own player rather than Music. One voice for
    /// the Mac, so your other devices don't see it flick between the two. See ``NearbyVoice``.
    private static func speaksForMotif(_ model: AppModel, musicIsPlaying: Bool) -> Bool {
        let player = model.player
        return NearbyVoice.isMotif(hasSong: player.hasQueue, isPlaying: player.isPlaying, musicIsPlaying: musicIsPlaying)
    }

    /// Tells your devices what this Mac is playing, from whichever player speaks for it. Also
    /// what the window calls as Motif's own player changes, so that change is told through
    /// the same choice rather than over Music's song.
    static func tell(_ model: AppModel) async {
        guard !model.isDemoLaunch else { return }
        let presence = await ScriptingQueue.run { MusicScripting.presence() }
        if speaksForMotif(model, musicIsPlaying: presence.isPlaying) {
            model.tellNearby()
            return
        }
        let capabilities = TransportRouting.capabilities(presence: presence)
        guard presence.isRunning, let song = model.capture?.nowPlaying else {
            model.nearby.publish(NearbyState())
            return
        }
        let artwork = song.artworkURL.flatMap { $0.hasPrefix("https://") ? $0 : nil }
        model.nearby.publish(NearbyState(
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            artworkURL: model.nearbyArtwork(artwork, for: song.title, by: song.artistName),
            isPlaying: presence.isPlaying,
            canSkipBack: capabilities.canSkipBack,
            canSkipForward: capabilities.canSkipForward
        ))
    }
}

/// What your other devices are playing, under the Mac's own, with their controls.
struct NearbyMenuSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let devices = model.nearby.withSongs
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(devices) { device in
                    NearbyMenuRow(device: device)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

private struct NearbyMenuRow: View {
    let device: NearbyDevices.Device
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = device.state ?? NearbyState()
        HStack(spacing: 10) {
            ArtworkView(url: state.artworkURL, seed: state.album ?? state.title ?? device.name, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Label(state.isPlaying ? "Playing on \(device.name)" : "Paused on \(device.name)", systemImage: NearbyDevices.symbol(for: device.platform))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                Text([state.title, state.artist].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if state.canSkipBack { control("Previous Track", "backward.fill", .previous) }
                control(state.isPlaying ? "Pause" : "Play", state.isPlaying ? "pause.fill" : "play.fill", .playPause)
                if state.canSkipForward { control("Next Track", "forward.fill", .next) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func control(_ title: LocalizedStringKey, _ symbol: String, _ command: TransportCommand) -> some View {
        Button(title, systemImage: symbol) { model.nearby.send(command, to: device) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .help(Text(title))
    }
}
