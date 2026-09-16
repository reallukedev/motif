import SwiftUI
import MotifCore

/// Songs, artists and albums matching a query. With an empty query it suggests top artists.
struct SearchResultsList: View {
    let query: String
    @Environment(AppModel.self) private var model
    @State private var results = SearchResults.empty
    @State private var suggestions: [ArtistTally] = []
    /// Built once per library change, so each letter typed only filters it.
    @State private var index: SearchIndex?
    /// Bumped each time a new index lands, so results already on screen are searched again.
    @State private var indexGeneration = 0

    var body: some View {
        List {
            if isBlank {
                if !suggestions.isEmpty {
                    Section("Your Top Artists") {
                        ForEach(suggestions) { artist in
                            NavigationLink(value: Route.artist(artist.id)) { ArtistRow(artist: artist) }
                        }
                    }
                }
            } else {
                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists.prefix(5)) { artist in
                            NavigationLink(value: Route.artist(artist.id)) { ArtistRow(artist: artist) }
                        }
                    }
                }
                if !results.songs.isEmpty {
                    Section("Songs") {
                        ForEach(results.songs) { song in
                            NavigationLink(value: Route.song(song.id)) { SongRow(song: song) }
                        }
                    }
                }
                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums.prefix(8)) { album in
                            NavigationLink(value: Route.album(album.id)) {
                                AlbumRow(album: album)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if !isBlank, results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        // The index is rebuilt when the library changes, so a play that just finished, or
        // one deleted or synced in, shows up in results that are already on screen.
        .task(id: model.library.revision) {
            let history = model.library.history
            let next = await OffMainActor.run { SearchIndex(history: history) }
            guard !Task.isCancelled else { return }
            index = next
            indexGeneration += 1
            suggestions = next.topArtists(limit: 6)
        }
        .task(id: SearchKey(query: query, indexGeneration: indexGeneration)) {
            guard let index else { return }
            // A short pause so typing doesn't search on every letter.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let query = query
            let next = await OffMainActor.run { index.search(query) }
            guard !Task.isCancelled else { return }
            results = next
        }
    }

    private var isBlank: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private struct SearchKey: Equatable {
    let query: String
    let indexGeneration: Int
}
