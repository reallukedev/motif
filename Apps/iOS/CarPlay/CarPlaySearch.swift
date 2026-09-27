import UIKit
import CarPlay
import MusicKit
import MotifCore

/// Search, as Music has it in the car: Siri at the top, since CarPlay gives music apps a voice
/// rather than a keyboard, then what you searched for lately on the phone, each a tap from its
/// results. With nothing searched yet, a few things to say, each of which also plays at a tap.
extension CarPlaySceneDelegate {
    /// Where the phone keeps its recent searches, one list for each music source.
    private var recentSearchesKey: String {
        model.musicSource == .yourMusic ? "recentYourMusicSearches" : "recentMusicSearches"
    }

    func searchSections() -> [CPListSection] {
        let recents = RecentSearches.list(UserDefaults.standard.string(forKey: recentSearchesKey) ?? "")
        guard recents.isEmpty else {
            let rows = recents.map { term in
                let row = CPListItem(text: term, detailText: nil, image: nil, accessoryImage: nil, accessoryType: .disclosureIndicator)
                row.handler = { [weak self] _, completion in
                    self?.open({ await self?.resultsPage(for: term) }, then: completion)
                }
                return row
            }
            return [CPListSection(items: rows, header: String(localized: "Recent Searches"), sectionIndexTitle: nil)]
        }
        let rows = suggestions().map { suggestion in
            let row = CPListItem(text: suggestion.phrase, detailText: nil)
            row.handler = { [weak self] _, completion in
                self?.play(suggestion.action, completion: completion)
            }
            return row
        }
        return [CPListSection(items: rows, header: String(localized: "Try Asking Siri"), sectionIndexTitle: nil)]
    }

    /// Things Siri understands in Motif, drawn from your own listening where it can be, so each
    /// reads as something you'd really ask for.
    private func suggestions() -> [(phrase: String, action: () async -> Void)] {
        let model = self.model
        var suggestions: [(phrase: String, action: () async -> Void)] = []
        if hasMotifRadio {
            suggestions.append((String(localized: "“Play Motif Radio”"), { [weak self] in await self?.startOrResumeMotifRadio() }))
        }
        suggestions.append((String(localized: "“Play driving music”"), { await MotifPlayback.start(.drive, model: model) }))
        if let last = model.library.history.captures.last, model.player.canPlay(songID: last.songID) {
            let song = HistorySong(songID: last.songID, title: last.title, artistName: last.artistName, albumTitle: last.albumTitle, artworkURL: last.artworkURL)
            suggestions.append((String(localized: "“Play \(last.title) by \(last.artistName)”"), {
                await model.player.start(.history([song]), from: .songs(song.title))
            }))
        }
        suggestions.append((String(localized: "“Play something chill”"), { await MotifPlayback.start(.chill, model: model) }))
        return suggestions
    }

    // MARK: - Results

    /// A search's results, in Music's order: songs, artists, albums, playlists. The search
    /// moves back to the top of the recent ones, as it does on the phone.
    private func resultsPage(for term: String) async -> CPListTemplate {
        let defaults = UserDefaults.standard
        defaults.set(RecentSearches.adding(term, to: defaults.string(forKey: recentSearchesKey) ?? ""), forKey: recentSearchesKey)

        let sections = model.musicSource == .yourMusic ? await yourMusicResults(term) : await appleMusicResults(term)
        let page = CPListTemplate(title: term, sections: sections ?? [])
        page.emptyViewTitleVariants = [sections == nil ? String(localized: "Couldn’t Search") : String(localized: "No Results")]
        page.emptyViewSubtitleVariants = [sections == nil
            ? String(localized: "Check your connection and try again.")
            : String(localized: "Nothing matched “\(term)”.")]
        return page
    }

    /// Nil when Apple Music couldn't be asked.
    private func appleMusicResults(_ term: String) async -> [CPListSection]? {
        guard MusicAuthorization.currentStatus == .authorized, !model.isDemoLaunch else { return nil }
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Artist.self, Album.self, Playlist.self])
        request.limit = 8
        guard let response = try? await request.response() else { return nil }
        let player = model.player
        var sections: [CPListSection] = []

        let songs = PlayPreferences.versions(of: Array(response.songs))
        if !songs.isEmpty {
            let context = PlayContext.songs(term)
            var rows: [CPListItem] = []
            for (index, song) in songs.enumerated() {
                let art = song.artwork.map(CoverArt.artwork) ?? .url(nil, seed: song.albumTitle ?? song.title)
                let image = await CarPlayImages.cover(art, side: CPListItem.maximumImageSize.height, scale: scale)
                let row = CPListItem(text: song.title, detailText: song.artistName, image: image)
                row.isExplicitContent = song.contentRating == .explicit
                row.isPlaying = player.current?.song?.id == song.id
                row.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.songs(songs, startingAt: index), from: context) }, completion: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Songs"), sectionIndexTitle: nil))
        }

        let artists = Array(response.artists.prefix(4))
        if !artists.isEmpty {
            var rows: [CPListItem] = []
            let side = CPListItem.maximumImageSize.height
            for artist in artists {
                let image = if let artwork = artist.artwork {
                    CarPlayImages.circle(await CarPlayImages.cover(.artwork(artwork), side: side, scale: scale))
                } else {
                    CarPlayImages.placeholder(symbol: "music.microphone", side: side, scale: scale, round: true)
                }
                let row = CPListItem(text: artist.name, detailText: nil, image: image, accessoryImage: nil, accessoryType: .disclosureIndicator)
                row.handler = { [weak self] _, completion in
                    self?.open({ await self?.catalogArtistPage(artist) }, then: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Artists"), sectionIndexTitle: nil))
        }

        let albums = PlayPreferences.versions(of: Array(response.albums)).prefix(6)
        if !albums.isEmpty {
            sections.append(CPListSection(items: albumRows(Array(albums)), header: String(localized: "Albums"), sectionIndexTitle: nil))
        }
        let playlists = Array(response.playlists.prefix(4))
        if !playlists.isEmpty {
            sections.append(CPListSection(items: playlistRows(playlists), header: String(localized: "Playlists"), sectionIndexTitle: nil))
        }
        return sections
    }

    private func yourMusicResults(_ term: String) async -> [CPListSection]? {
        let music = model.yourMusic
        let player = model.player
        let found = music.index.search(term, limit: 8)
        var sections: [CPListSection] = []

        let tracks = found.tracks.filter(music.isPlayable)
        if !tracks.isEmpty {
            let context = PlayContext.songs(term)
            var rows: [CPListItem] = []
            for (index, track) in tracks.enumerated() {
                let image = await CarPlayImages.cover(url: music.artworkURL(track.artwork)?.absoluteString, seed: track.album ?? track.title, side: CPListItem.maximumImageSize.height, scale: scale)
                let row = CPListItem(text: track.title, detailText: track.artist, image: image)
                row.isPlaying = player.current?.local?.id == track.id
                row.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.local(tracks, startingAt: index), from: context) }, completion: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Songs"), sectionIndexTitle: nil))
        }
        if !found.artists.isEmpty {
            let side = CPListItem.maximumImageSize.height
            var rows: [CPListItem] = []
            for artist in found.artists.prefix(4) {
                let image = if let picture = music.artistPicture(for: artist) {
                    CarPlayImages.circle(await CarPlayImages.cover(picture, side: side, scale: scale))
                } else {
                    CarPlayImages.placeholder(symbol: "music.microphone", side: side, scale: scale, round: true)
                }
                let row = CPListItem(text: artist.name, detailText: nil, image: image, accessoryImage: nil, accessoryType: .disclosureIndicator)
                row.handler = { [weak self] _, completion in
                    self?.open({ await self?.localArtistPage(artist) }, then: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Artists"), sectionIndexTitle: nil))
        }
        if !found.albums.isEmpty {
            var rows: [CPListItem] = []
            for album in found.albums.prefix(6) {
                let image = await CarPlayImages.cover(url: music.artworkURL(album.artwork)?.absoluteString, seed: album.title, side: CPListItem.maximumImageSize.height, scale: scale)
                let row = CPListItem(text: album.displayTitle, detailText: album.artist, image: image, accessoryImage: nil, accessoryType: .disclosureIndicator)
                row.handler = { [weak self] _, completion in
                    self?.open({ await self?.localAlbumPage(album) }, then: completion)
                }
                rows.append(row)
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Albums"), sectionIndexTitle: nil))
        }
        return sections
    }

    /// An artist from Apple Music: Play and Shuffle their top songs, the songs, then albums.
    private func catalogArtistPage(_ artist: Artist) async -> CPListTemplate {
        let player = model.player
        let detailed = (try? await artist.with([.topSongs, .albums])) ?? artist
        let songs = PlayPreferences.versions(of: Array(detailed.topSongs ?? []))
        let albums = PlayPreferences.versions(of: Array(detailed.albums ?? [])).prefix(12)
        let context = PlayContext(kind: .artist, title: artist.name)
        let actions = playRows(
            detail: String(localized: "Top Songs"),
            play: songs.isEmpty ? nil : { await player.start(.songs(songs), from: context) },
            shuffle: songs.isEmpty ? nil : { await player.start(.songs(songs), from: context, shuffled: true) }
        )
        var sections: [CPListSection] = []
        if !songs.isEmpty {
            let rows = songs.prefix(10).enumerated().map { index, song in
                let row = CPListItem(text: song.title, detailText: song.albumTitle)
                row.isExplicitContent = song.contentRating == .explicit
                row.isPlaying = player.current?.song?.id == song.id
                row.handler = { [weak self] _, completion in
                    self?.play({ await player.start(.songs(songs, startingAt: index), from: context) }, completion: completion)
                }
                return row
            }
            sections.append(CPListSection(items: rows, header: String(localized: "Top Songs"), sectionIndexTitle: nil))
        }
        if !albums.isEmpty {
            let rows = albumRows(Array(albums)) { album in album.releaseDate.map { String(Calendar.current.component(.year, from: $0)) } }
            sections.append(CPListSection(items: rows, header: String(localized: "Albums"), sectionIndexTitle: nil))
        }
        let page = CPListTemplate(title: artist.name, sections: Self.section(actions) + sections, assistantCellConfiguration: nil)
        page.emptyViewTitleVariants = [String(localized: "Nothing to Play")]
        return page
    }
}
