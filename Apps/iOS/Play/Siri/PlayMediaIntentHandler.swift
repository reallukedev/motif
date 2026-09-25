import Intents
import MusicKit
import MotifCore

/// Siri's "Play Phoebe Bridgers in Motif", "Play my Workout playlist on Motif", and plain
/// "Play music" once Siri has learned Motif is where you listen.
///
/// Siri parses the request; this finds what it names, in Motif's own mixes first, then the
/// library for playlists, then Apple Music's catalog, and plays it in Motif so every song is
/// kept. Handled in the app, which is launched in the background to do it.
nonisolated final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        let search = intent.mediaSearch
        let request = MediaRequest(
            name: search?.mediaName?.trimmingCharacters(in: .whitespaces) ?? "",
            artist: search?.artistName?.trimmingCharacters(in: .whitespaces) ?? "",
            type: search?.mediaType ?? .unknown,
            moods: search?.moodNames ?? []
        )
        guard let found = await MediaRequestResolver.item(for: request) else {
            return [.unsupported(forReason: .unsupportedMediaType)]
        }
        let item = INMediaItem(identifier: found.identifier, title: found.title, type: found.type, artwork: nil, artist: found.artist)
        return INPlayMediaMediaItemResolutionResult.successes(with: [item])
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        guard let identifier = intent.mediaItems?.first?.identifier else {
            return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
        }
        let shuffled = intent.playShuffled == true
        let problem = await MediaRequestResolver.play(identifier, shuffled: shuffled)
        switch problem {
        case nil:
            return INPlayMediaIntentResponse(code: .success, userActivity: nil)
        case .needsSubscription, .accessDenied:
            // Something to sort out in Motif itself.
            return INPlayMediaIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil)
        case .onlyExplicit, .explicitSong:
            return INPlayMediaIntentResponse(code: .failureRestrictedContent, userActivity: nil)
        case .nothingToPlay, .notInYourMusic, .needsAppleMusic, .failed:
            return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
        }
    }
}

/// What Siri heard, as plain values.
nonisolated struct MediaRequest: Sendable {
    let name: String
    let artist: String
    let type: INMediaItemType
    /// Moods Siri heard: "something chill", "workout music".
    var moods: [String] = []
}

/// What a request resolved to, as plain values, turned into an `INMediaItem` by the handler.
nonisolated struct ResolvedMedia: Sendable {
    let identifier: String
    let title: String
    let type: INMediaItemType
    var artist: String?
}

/// Turns what Siri heard into something Motif can play, and plays it.
@MainActor
enum MediaRequestResolver {
    // Identifiers carried from resolving to handling: "kind:value".
    private static let motifPrefix = "motif:"

    static func item(for request: MediaRequest) async -> ResolvedMedia? {
        let (name, artist, type) = (request.name, request.artist, request.type)

        // "Play something chill": one of Motif's moods, when Siri heard one and nothing else.
        if name.isEmpty, artist.isEmpty, let mood = request.moods.lazy.compactMap(moodChoice(named:)).first {
            return motifItem(mood)
        }

        // "Play music": Motif Radio, which always has something, or this hour's mix with it off.
        if name.isEmpty, artist.isEmpty {
            return motifItem(PlayPreferences.isMotifRadioOn ? .station : .forYou)
        }
        if artist.isEmpty, let choice = motifChoice(named: name) {
            return motifItem(choice)
        }
        if MusicSource.current == .yourMusic {
            return localItem(name: name, artist: artist, type: type)
        }
        guard MusicAuthorization.currentStatus == .authorized else { return nil }

        switch type {
        case .playlist:
            let inLibrary = await libraryPlaylist(named: name)
            let playlist: Playlist? = if let inLibrary { inLibrary } else { await catalog(Playlist.self, name).first }
            if let playlist {
                return ResolvedMedia(identifier: "playlist:\(playlist.id.rawValue)", title: playlist.name, type: .playlist)
            }
        case .album:
            if let album = PlayPreferences.versions(of: await catalog(Album.self, [name, artist].joined(separator: " "))).first {
                return ResolvedMedia(identifier: "album:\(album.id.rawValue)", title: album.title, type: .album, artist: album.artistName)
            }
        case .artist:
            if let found = await catalog(Artist.self, artist.isEmpty ? name : artist).first {
                return ResolvedMedia(identifier: "artist:\(found.id.rawValue)", title: found.name, type: .artist)
            }
        case .radioStation, .station:
            if let station = await catalog(MusicKit.Station.self, name).first {
                return ResolvedMedia(identifier: "station:\(station.id.rawValue)", title: station.name, type: .radioStation)
            }
        default:
            break
        }

        // A song, or anything unspecified: the catalog's best match.
        if artist.isEmpty || !name.isEmpty {
            let songs = PlayPreferences.versions(of: await catalog(Song.self, [name, artist].joined(separator: " ")))
            if let song = songs.first {
                return ResolvedMedia(identifier: "song:\(song.id.rawValue)", title: song.title, type: .song, artist: song.artistName)
            }
        }
        if let found = await catalog(Artist.self, artist.isEmpty ? name : artist).first {
            return ResolvedMedia(identifier: "artist:\(found.id.rawValue)", title: found.name, type: .artist)
        }
        return nil
    }

    /// Plays what an identifier names. Returns what went wrong, if anything.
    static func play(_ identifier: String, shuffled: Bool) async -> PlayerProblem? {
        let model = AppModel.shared
        guard !model.isDemoLaunch else { return .nothingToPlay }
        let usesYourMusic = model.musicSource == .yourMusic
        // No prompt from the background, where no one would see it. Your own music needs none.
        guard usesYourMusic || MusicAuthorization.currentStatus == .authorized else { return .accessDenied }
        await model.prepareForPlaying()
        let player = model.player
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .nothingToPlay }
        let id = MusicItemID(parts[1])
        defer { player.problem = nil }

        switch parts[0] {
        case "local-track":
            let index = model.yourMusic.index
            guard let track = index.track(id: parts[1]) else { return .nothingToPlay }
            // The song, then the rest of its artist's, so the music doesn't stop after one.
            let more = index.artist(id: track.artistKey)?.tracks.filter { $0.id != track.id }.shuffled() ?? []
            await player.start(.local([track] + more), from: .songs(track.title))
        case "local-album":
            guard let album = model.yourMusic.index.album(id: parts[1]) else { return .nothingToPlay }
            await player.start(.local(album.tracks), from: PlayContext(kind: .album, title: album.title), shuffled: shuffled)
        case "local-artist":
            guard let artist = model.yourMusic.index.artist(id: parts[1]) else { return .nothingToPlay }
            await player.start(.local(artist.tracks), from: PlayContext(kind: .artist, title: artist.name), shuffled: true)
        case "motif":
            guard let choice = PlayChoice(rawValue: parts[1]) else { return .nothingToPlay }
            await MotifPlayback.start(choice, model: model)
        case "song":
            guard let song = await song(id) else { return .nothingToPlay }
            // The song, then more by the same artist, so the music doesn't stop after one.
            await player.start(.songs(await songAndMore(song)), from: .songs(song.title))
        case "album":
            guard let album = await album(id) else { return .nothingToPlay }
            await player.start(.album(album), from: PlayContext(kind: .album, title: album.title), shuffled: shuffled)
        case "playlist":
            guard let playlist = await libraryOrCatalogPlaylist(id) else { return .nothingToPlay }
            await player.start(.playlist(playlist), from: PlayContext(kind: .playlist, title: playlist.name), shuffled: shuffled)
        case "artist":
            guard let artist = await artist(id),
                  let top = try? await artist.with([.topSongs]).topSongs, !top.isEmpty
            else { return .nothingToPlay }
            let songs = PlayPreferences.versions(of: Array(top))
            await player.start(.songs(songs), from: PlayContext(kind: .artist, title: artist.name), shuffled: shuffled)
        case "station":
            guard let station = await station(id) else { return .nothingToPlay }
            await player.start(.station(station), from: PlayContext(kind: .station, title: station.name))
        default:
            return .nothingToPlay
        }
        // Answered to Siri, so it isn't shown again the next time the app opens: the defer
        // above clears it once this has been read.
        return player.problem
    }

    /// Your own music's best match: an artist, album or song, as Siri heard it asked for.
    private static func localItem(name: String, artist: String, type: INMediaItemType) -> ResolvedMedia? {
        let index = AppModel.shared.yourMusic.index
        let query = [name, artist].filter { !$0.isEmpty }.joined(separator: " ")
        let found = index.search(query, limit: 5)
        switch type {
        case .artist:
            let named = index.search(artist.isEmpty ? name : artist, limit: 1).artists.first
            return named.map { ResolvedMedia(identifier: "local-artist:\($0.id)", title: $0.name, type: .artist) }
        case .album:
            return found.albums.first.map { ResolvedMedia(identifier: "local-album:\($0.id)", title: $0.title, type: .album, artist: $0.artist) }
        default:
            if let track = found.tracks.first {
                return ResolvedMedia(identifier: "local-track:\(track.id)", title: track.title, type: .song, artist: track.artist)
            }
            if let album = found.albums.first {
                return ResolvedMedia(identifier: "local-album:\(album.id)", title: album.title, type: .album, artist: album.artist)
            }
            return found.artists.first.map { ResolvedMedia(identifier: "local-artist:\($0.id)", title: $0.name, type: .artist) }
        }
    }

    // MARK: - Finding things

    private static func motifItem(_ choice: PlayChoice) -> ResolvedMedia {
        let title = String(localized: PlayChoice.caseDisplayRepresentations[choice]?.title ?? "Motif Radio")
        return ResolvedMedia(identifier: motifPrefix + choice.rawValue, title: title, type: .music)
    }

    /// A mood Siri named, matched loosely by the start of a word: "chill", "relaxing",
    /// "workout", "sad". Only at a word's start, so "unhappy" isn't happy and "brunch" isn't
    /// a run.
    static func moodChoice(named name: String) -> PlayChoice? {
        let words = StatsCalculator.folded(name).split { !$0.isLetter }
        let spoken = " " + words.joined(separator: " ")
        let starts: [(String, PlayChoice)] = [
            ("chill", .chill), ("relax", .chill), ("calm", .chill), ("focus", .focus), ("study", .focus),
            ("workout", .workout), ("gym", .workout), ("running", .workout), ("party", .party), ("danc", .party),
            ("sleep", .sleep), ("love", .love), ("romantic", .love), ("sad", .heartbreak), ("heartbr", .heartbreak),
            ("happy", .feelGood), ("feel good", .feelGood), ("upbeat", .feelGood), ("energ", .energy), ("pump", .energy),
        ]
        return starts.first { spoken.contains(" " + $0.0) }?.1
    }

    /// One of Motif's own names, however Siri spelled it.
    static func motifChoice(named name: String) -> PlayChoice? {
        let folded = StatsCalculator.folded(name)
        let names: [(String, PlayChoice)] = [
            ("motif radio", .station), ("motif station", .station), ("my station", .station), ("my radio", .station),
            ("my mix", .forYou), ("discover", .discover), ("something new", .discover),
            ("on repeat", .onRepeat), ("all-time favorites", .favorites), ("all time favorites", .favorites),
            ("my favorites", .favorites), ("deep cuts", .deepCuts), ("radio finds", .radioFinds),
            ("feel good music", .feelGood), ("something upbeat", .feelGood), ("energy", .energy),
            ("workout music", .workout), ("focus music", .focus), ("something to focus", .focus),
            ("chill music", .chill), ("something chill", .chill), ("love songs", .love),
            ("sad songs", .heartbreak), ("heartbreak songs", .heartbreak), ("party music", .party),
            ("sleep music", .sleep), ("something to sleep to", .sleep),
        ]
        return names.first { folded == $0.0 }?.1
    }

    private static func catalog<Item: MusicCatalogSearchable>(_ type: Item.Type, _ term: String) async -> [Item] {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: term, types: [type])
        request.limit = 5
        guard let response = try? await request.response() else { return [] }
        return switch type {
        case is Song.Type: Array(response.songs) as? [Item] ?? []
        case is Album.Type: Array(response.albums) as? [Item] ?? []
        case is Artist.Type: Array(response.artists) as? [Item] ?? []
        case is Playlist.Type: Array(response.playlists) as? [Item] ?? []
        case is MusicKit.Station.Type: Array(response.stations) as? [Item] ?? []
        default: []
        }
    }

    private static func libraryPlaylist(named name: String) async -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(text: name)
        request.limit = 5
        let playlists = (try? await request.response().items) ?? []
        let wanted = StatsCalculator.folded(name)
        return playlists.first { StatsCalculator.folded($0.name) == wanted } ?? playlists.first
    }

    private static func song(_ id: MusicItemID) async -> Song? {
        try? await MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id).response().items.first
    }

    private static func album(_ id: MusicItemID) async -> Album? {
        try? await MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id).response().items.first
    }

    private static func artist(_ id: MusicItemID) async -> Artist? {
        try? await MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: id).response().items.first
    }

    private static func station(_ id: MusicItemID) async -> MusicKit.Station? {
        try? await MusicCatalogResourceRequest<MusicKit.Station>(matching: \.id, equalTo: id).response().items.first
    }

    private static func libraryOrCatalogPlaylist(_ id: MusicItemID) async -> Playlist? {
        var library = MusicLibraryRequest<Playlist>()
        library.filter(matching: \.id, equalTo: id)
        if let found = try? await library.response().items.first { return found }
        return try? await MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: id).response().items.first
    }

    /// The song asked for, then the artist's other top songs in a fresh order.
    private static func songAndMore(_ song: Song) async -> [Song] {
        guard let artist = try? await song.with([.artists]).artists?.first,
              let top = try? await artist.with([.topSongs]).topSongs
        else { return [song] }
        let others = PlayPreferences.versions(of: Array(top)).filter {
            ExplicitVersions.versionKey(title: $0.title, artist: $0.artistName)
                != ExplicitVersions.versionKey(title: song.title, artist: song.artistName)
        }
        return [song] + others.shuffled()
    }
}
