import SwiftUI
import MusicKit
import MotifCore

/// What can be done with a suggested song in Your Music, at the end of its row: download it
/// from your server or your Lidarr collection, add one a server like Octo found to your music,
/// watch it come down, or read why it can't play.
struct AvailabilityAccessory: View {
    let availability: SongAvailability
    let title: String
    let artist: String
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    @State private var isGetting = false

    var body: some View {
        switch availability {
        case .checking:
            EmptyView()
        case .playable(let track):
            if track.isFromServer, !music.isInYourMusic(track) {
                // Found on a server that doesn't have it yet: it plays, and can be asked for.
                if music.servers.isWaitingToKeep(track) {
                    DownloadStateIcon(track: track)
                        .frame(minWidth: 24)
                } else {
                    Button {
                        Task { player.confirm(await music.keep(track)) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to Your Music")
                }
            } else if track.isFromServer, !music.downloads.isDownloaded(track.id), !music.downloads.isDownloading(track.id) {
                downloadButton { music.downloads.download([track]) }
                    .accessibilityLabel("Download")
            } else {
                DownloadStateIcon(track: track)
                    .frame(minWidth: 24)
            }
        case .inLidarr:
            if isGetting {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Getting from Lidarr")
            } else {
                downloadButton {
                    isGetting = true
                    Task {
                        let message = await music.getFromLidarr(title: title, artist: artist)
                        isGetting = false
                        player.confirm(message)
                    }
                }
                .accessibilityLabel("Download from Your Lidarr Collection")
            }
        case .comingFromLidarr:
            note("Coming from Lidarr", symbol: "clock")
        case .unavailable:
            note("Not Available", symbol: nil)
        }
    }

    private func downloadButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: LocalizedStringKey, symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// A catalog song's menu in Your Music: play or download it where it's yours, ask Lidarr for
/// it where it isn't, and go to its artist.
struct YourMusicSongMenu: View {
    let song: Song
    @Environment(YourMusic.self) private var music
    @Environment(Lidarr.self) private var lidarr
    @Environment(PlayerModel.self) private var player
    @Environment(\.openPlayRoute) private var openPlayRoute

    var body: some View {
        let availability = music.availability(title: song.title, artist: song.artistName)
        if let track = availability.track {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.enqueue(.local([track]), next: true, title: track.title)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.enqueue(.local([track]), next: false, title: track.title)
            }
            if track.isFromServer, !music.isInYourMusic(track) {
                AddToYourMusicButton(track: track)
            } else if track.isFromServer, !music.downloads.isDownloaded(track.id) {
                Button("Download", systemImage: "arrow.down.circle") { music.downloads.download([track]) }
            }
            Divider()
        }
        if lidarr.isSetUp {
            switch availability {
            case .unavailable, .comingFromLidarr, .checking:
                if let album = song.albumTitle {
                    Button("Ask Lidarr for This Album", systemImage: "tray.and.arrow.down") {
                        Task { player.confirm(await lidarr.request(album: album, by: song.artistName)) }
                    }
                }
                Button("Add \(song.artistName) to Lidarr", systemImage: "person.crop.circle.badge.plus") {
                    Task { player.confirm(await lidarr.follow(artistNamed: song.artistName)) }
                }
            case .inLidarr:
                Button("Download from Your Collection", systemImage: "arrow.down.circle") {
                    Task { player.confirm(await music.getFromLidarr(title: song.title, artist: song.artistName)) }
                }
            case .playable:
                EmptyView()
            }
            Divider()
        }
        Button("Go to Artist", systemImage: "music.microphone") {
            Task { if let artist = await SongLinks.artist(of: song) { openPlayRoute(.artist(artist)) } }
        }
        Button("Go to Album", systemImage: "square.stack") {
            Task { if let album = await SongLinks.album(of: song) { openPlayRoute(.album(album)) } }
        }
    }
}

/// A catalog song's row on an Apple Music page, in Your Music: it plays if the song is in your
/// music, and otherwise says why not, with what can be done at its end. With Apple Music as
/// the source it's just the row.
struct AvailabilityGate<Label: View>: View {
    let title: String
    let artist: String
    let album: String?
    let play: () -> Void
    @ViewBuilder var label: Label
    @Environment(AppModel.self) private var model
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    /// Tapped while it was still being looked for: waiting to play it once it's found.
    @State private var isWaiting = false

    var body: some View {
        if model.musicSource == .yourMusic {
            let availability = music.availability(title: title, artist: artist)
            // Still being looked for isn't held against it: a tap waits for the answer.
            let isBlocked = availability != .checking && availability.track == nil
            HStack(spacing: 8) {
                Button {
                    if availability == .checking {
                        isWaiting = true
                        Task {
                            await music.check(title: title, artist: artist, album: album)
                            isWaiting = false
                            let found = music.availability(title: title, artist: artist)
                            if found.track != nil { play() } else if let message = found.message { player.confirm(message) }
                        }
                    } else if isBlocked, let message = availability.message {
                        player.confirm(message)
                    } else {
                        play()
                    }
                } label: {
                    label.opacity(isBlocked ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                if isWaiting {
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Finding This Song")
                } else {
                    AvailabilityAccessory(availability: availability, title: title, artist: artist)
                }
            }
            .task(id: "\(HistoryImport.key(title: title, artistName: artist)).\(music.availabilityGeneration)") {
                await music.check(title: title, artist: artist, album: album)
            }
        } else {
            Button(action: play) { label }
                .buttonStyle(.plain)
        }
    }
}
