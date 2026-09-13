import SwiftUI
import MotifCore

struct ArtistDetailView: View {
    let artistID: String
    @Environment(AppModel.self) private var model
    @State private var profile: ArtistProfile?
    @State private var showsAllSongs = false

    var body: some View {
        ScrollView {
            if let profile {
                content(profile)
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            } else if model.library.isLoaded {
                ContentUnavailableView("No Plays", systemImage: "music.microphone")
            }
        }
        .background(GroupedBackground())
        .navigationTitle(profile?.artist.name ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(artistID)|\(model.library.revision)") {
            profile = StatsCalculator.artistProfile(id: artistID, history: model.library.history)
        }
    }

    private func content(_ profile: ArtistProfile) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            VStack(spacing: 12) {
                ArtworkView(url: profile.artist.artworkURL, seed: profile.artist.name, size: 150, isCircle: true)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                Text(profile.artist.name)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("#\(profile.allTimeRank) of all time · \(profile.share.formatted(.percent.precision(.fractionLength(0)))) of your listening")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            StatStrip(items: [
                .init(title: "Plays", value: profile.artist.count.formatted()),
                .init(title: "Listening", value: Format.listening(profile.artist.listeningSeconds)),
                .init(title: "Songs", value: profile.artist.songCount.formatted()),
                .init(title: "First Heard", value: Format.shortDate(profile.artist.firstHeard)),
            ])

            if profile.timeline.count(where: { $0.count > 0 }) > 1 {
                PlaysOverTimeCard(timeline: profile.timeline, unit: profile.timelineUnit)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Top Songs") {
                    if profile.songs.count > 5 {
                        Button(showsAllSongs ? "Show Less" : "Show All") {
                            withAnimation { showsAllSongs.toggle() }
                        }
                    }
                }
                TopSongsCard(songs: profile.songs, limit: showsAllSongs ? profile.songs.count : 5)
            }

            if !profile.albums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Albums")
                    AlbumGrid(albums: profile.albums)
                }
            }

            if profile.artist.count >= 10 {
                Card { ListeningClockCard(hourly: profile.hourly) }
            }
        }
    }
}

/// A row of labelled numbers under a detail header.
struct StatStrip: View {
    struct Item: Identifiable {
        let title: LocalizedStringKey
        let value: String
        var id: String { value + "\(title)" }
    }

    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.value)
                                .font(.headline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        } else {
            strip
        }
    }

    private var strip: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().frame(maxHeight: 36)
                    }
                    VStack(spacing: 3) {
                        Text(item.value)
                            .font(.system(.headline, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Albums as a wrapping grid of covers.
struct AlbumGrid: View {
    let albums: [AlbumTally]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 14, alignment: .top)], spacing: 16) {
            ForEach(albums) { album in
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ArtworkView(url: album.artworkURL, seed: album.title, size: geometry.size.width)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    Text(album.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("^[\(album.count) play](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
