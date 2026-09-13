import SwiftUI
import MotifCore

/// A horizontal shelf of artists, like the Music app's.
struct TopArtistsShelf: View {
    let artists: [ArtistTally]
    var artworkSize: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(artists) { artist in
                    NavigationLink(value: Route.artist(artist.id)) {
                        VStack(spacing: 8) {
                            ArtworkView(url: artist.artworkURL, seed: artist.name, size: artworkSize, isCircle: true)
                            VStack(spacing: 1) {
                                Text(artist.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("^[\(artist.count) play](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: artworkSize + 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(artist.name), \(artist.count) plays")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Numbered song rows inside a card.
struct TopSongsCard: View {
    let songs: [SongTally]
    var limit = 5

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(songs.prefix(limit).enumerated()), id: \.element.id) { index, song in
                    NavigationLink(value: Route.song(song.id)) {
                        SongRow(song: song, rank: index + 1)
                            .padding(.horizontal, Metrics.cardPadding)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if index < min(limit, songs.count) - 1 {
                        Divider().padding(.leading, Metrics.cardPadding + 28 + 52)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// Rank, cover, title and artist, and the play count.
struct SongRow: View {
    let song: SongTally
    var rank: Int?
    var showsCount = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                ArtworkView(url: song.artworkURL, seed: song.albumTitle ?? song.title, size: 44)
                Text(rank.map { "\($0). \(song.title)" } ?? song.title)
                Text(song.artistName)
                    .foregroundStyle(.secondary)
                if showsCount {
                    Text("^[\(song.count) play](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let rank {
                Text(rank.formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 22, alignment: .trailing)
            }
            ArtworkView(url: song.artworkURL, seed: song.albumTitle ?? song.title, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsCount {
                Text("^[\(song.count) play](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Album covers in a horizontal shelf.
struct TopAlbumsShelf: View {
    let albums: [AlbumTally]
    var coverSize: CGFloat = 140

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(albums) { album in
                    NavigationLink(value: Route.artist(StatsCalculator.folded(album.artistName))) {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(url: album.artworkURL, seed: album.title, size: coverSize)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(album.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(album.artistName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: coverSize)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}
