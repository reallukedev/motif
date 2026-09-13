import SwiftUI
import MotifCore

/// Songs, artists and albums matching a query. With an empty query it suggests top artists.
struct SearchResultsList: View {
    let query: String
    @Environment(AppModel.self) private var model
    @State private var results = SearchResults.empty
    @State private var suggestions: [ArtistTally] = []

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
                            NavigationLink(value: Route.artist(StatsCalculator.folded(album.artistName))) {
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
        .task(id: query) {
            // A short pause so typing doesn't search on every letter.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            results = StatsCalculator.search(query, in: model.library.history)
        }
        .task(id: model.library.revision) {
            suggestions = StatsCalculator.artistChart(range: .allTime, history: model.library.history, limit: 6).map(\.item)
        }
    }

    private var isBlank: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
