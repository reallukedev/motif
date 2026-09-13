#if DEBUG
import Foundation
import AppKit
import MotifCore

/// Runs the probe from the command line, with no window and no Dock icon. Output goes to
/// stdout with a meaningful exit status, so it can be scripted and diffed.
enum HeadlessProbe {
    static let flag = "--headless"

    static func shouldRun(_ arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    static func usage() -> String {
        """
        Motif headless probe

          Motif.app/Contents/MacOS/Motif --headless <command>

        Commands:
          env               Print environment: authorization, subscription, store backing.
          catalog <term>    Search the Apple Music catalog and print candidate song ids.
          write [songID]    Create a throwaway playlist and add a song. With no id, resolves
                            whatever is playing now; pass an id to exercise the add endpoint
                            on its own when nothing is playing. Writes to your Apple Music
                            library; delete the playlist afterwards.
          scrobble          Send everything owed to Last.fm now.
          lastfm            Report whether Last.fm is configured and connected, and how
                            many songs are owed a scrobble.
          forget <text>     Remove every song whose title contains <text>, and stop it
                            being imported back out of Apple's history.
          stations          List the stations Apple Music remembers, with provider and
                            live flags, to see which are Apple's own.
          autoplay [on|off] Report every guard automatic play-back checks, and what it
                            would do right now. Pass on or off to set the switch.
          playone <id> [s]  Play one catalog song for N seconds (default 240), touching no
                            store and marking nothing. Isolates whether ApplicationMusicPlayer
                            actually registers a play: pick a song that is NOT already in
                            `recent`, then run `recent` afterwards.
          sample [seconds]  Observe Music.app for N seconds (default 30) and dump every
                            playerInfo notification and scripting read.
          cleanup           List the "Motif Probe …" playlists so you can delete them
                            in Music. The Apple Music API cannot delete playlists.
          playlists         List every library playlist with its id.
          captures          Dump stored captures: catalog id, artwork, playlist state.
          readonly          Try to open the store read-only, as a widget would.
          stats             Compute the statistics screen's numbers for every range, and
                            report how many rows actually carry a station name.
          play              Play back today's captures. Starts audio.
          reset-playback    Clear played-back marks so a day can be replayed.
          retry-unresolved  Retry captures the catalog could not identify.
          recent            Read Apple Music's own recently-played list.

        Exit status is 0 on success, 1 on failure, 2 on bad usage.
        """
    }

    /// Runs to completion and exits. Never returns.
    static func run(_ arguments: [String]) -> Never {
        // No Dock icon, menu bar or window.
        NSApplication.shared.setActivationPolicy(.prohibited)

        var command = "env"
        if let index = arguments.firstIndex(of: flag), arguments.count > index + 1 {
            command = arguments[index + 1]
        }
        let remainder = arguments.drop { $0 != flag }.dropFirst(2)

        var exitCode: Int32 = 0
        var finished = false

        Task { @MainActor in
            exitCode = await execute(command: command, arguments: Array(remainder))
            finished = true
        }

        // Spin the main run loop instead of blocking it. MusicKit's token and authorization
        // work needs a live run loop, so a semaphore here would deadlock.
        while !finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    @MainActor
    private static func execute(command: String, arguments: [String]) async -> Int32 {
        // Before ProbeModel, which opens the real store (and with it iCloud sync).
        if command == "cloudcheck" {
            if arguments.first == "--purge-local" { return CloudCheck.purgeLocal() }
            return await CloudCheck.run(purge: arguments.first == "--purge")
        }
        let model = ProbeModel()

        switch command {
        case "env":
            await model.loadEnvironment()
            print(render(model.log))
            return 0

        case "catalog":
            let term = arguments.joined(separator: " ")
            guard !term.isEmpty else {
                FileHandle.standardError.write(Data("catalog needs a search term\n".utf8))
                return 2
            }
            await model.searchCatalog(term: term)
            print(render(model.log))
            return 0

        case "write":
            await model.loadEnvironment()
            await model.testCreatePlaylist()
            guard model.probePlaylistID != nil else {
                print(render(model.log))
                FileHandle.standardError.write(Data("\nCreate failed; not attempting the add.\n".utf8))
                return 1
            }
            // An explicit id tests just the add endpoint. Without one it also tests
            // identifying the current song, which needs Music.app to be playing.
            if let songID = arguments.first, !songID.isEmpty {
                await model.testAddSong(id: songID)
            } else {
                await model.testAddCurrentSong()
            }
            print(render(model.log))
            return 0

        case "retry-unresolved":
            await model.retryUnresolved()
            print(render(model.log))
            return 0

        case "reset-playback":
            model.resetPlayback()
            print(render(model.log))
            return 0

        case "play":
            await model.playBackToday()
            print(render(model.log))
            return 0

        case "recent":
            await model.showRecentlyPlayed()
            print(render(model.log))
            return 0

        case "readonly":
            // Checks a second process can read the store while the app has it open, which
            // widgets depend on.
            do {
                let store = try MotifStore(readOnly: true)
                let captures = try store.context.fetch(MotifStore.radioCaptures(limit: 5))
                model.log.append(.environment, "Read-only open", fields: [
                    ("backing", store.backing.description),
                    ("captures readable", String(captures.count)),
                    ("newest", captures.first.map { "\($0.title) by \($0.artistName)" } ?? "‹none›"),
                ])
            } catch {
                model.log.append(.error, "Read-only open failed", fields: [
                    ("error", String(describing: error)),
                ])
            }
            print(render(model.log))
            return 0

        case "captures":
            model.dumpCaptures()
            print(render(model.log))
            return 0

        case "stats":
            model.dumpStats()
            print(render(model.log))
            return 0

        case "playlists":
            await model.listAllPlaylists()
            print(render(model.log))
            return 0

        case "cleanup":
            await model.listProbePlaylists()
            print(render(model.log))
            return 0

        case "playone":
            guard let songID = arguments.first else {
                FileHandle.standardError.write(Data("playone needs a song id\n".utf8))
                return 2
            }
            await model.playOne(
                songID: songID,
                seconds: arguments.dropFirst().first.flatMap(Int.init) ?? 240
            )
            print(render(model.log))
            return 0

        case "scrobble":
            await model.sendScrobbles()
            print(render(model.log))
            return 0

        case "lastfm":
            model.dumpLastFM()
            print(render(model.log))
            return 0

        case "forget":
            guard let text = arguments.first else {
                FileHandle.standardError.write(Data("forget needs some of a song title\n".utf8))
                return 2
            }
            model.forgetSong(matching: text)
            print(render(model.log))
            return 0

        case "menubar":
            model.setMenuBarStyle(arguments.first ?? "radio")
            print(render(model.log))
            return 0

        case "stations":
            await model.dumpStations()
            print(render(model.log))
            return 0

        case "autoplay":
            let setting = arguments.first.flatMap { ["on": true, "off": false][$0] }
            model.dumpAutoPlaybackDecision(setting: setting)
            print(render(model.log))
            return 0

        case "playlib":
            guard let title = arguments.first else {
                FileHandle.standardError.write(Data("playlib needs a song title\n".utf8))
                return 2
            }
            await model.playLibraryCopy(title: title)
            print(render(model.log))
            return 0

        case "sample":
            let seconds = arguments.first.flatMap(Int.init) ?? 30
            await model.loadEnvironment()
            model.isSampling = true
            try? await Task.sleep(for: .seconds(seconds))
            model.isSampling = false
            print(render(model.log))
            return 0

        default:
            FileHandle.standardError.write(Data((usage() + "\n").utf8))
            return 2
        }
    }

    @MainActor
    private static func render(_ log: ProbeLog) -> String {
        log.exportText
    }
}
#endif
