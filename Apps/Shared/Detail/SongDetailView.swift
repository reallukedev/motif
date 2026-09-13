import SwiftUI
import MotifCore

struct SongDetailView: View {
    let songID: String
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Environment(\.openURL) private var openURL
    @State private var profile: SongProfile?
    @State private var showsAllPlays = false

    var body: some View {
        ScrollView {
            if let profile {
                content(profile)
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            } else if model.library.isLoaded {
                ContentUnavailableView("No Plays", systemImage: "music.note")
            }
        }
        .background(GroupedBackground())
        .navigationTitle(profile?.song.title ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(songID)|\(model.library.revision)") {
            profile = StatsCalculator.songProfile(id: songID, history: model.library.history)
        }
    }

    private func content(_ profile: SongProfile) -> some View {
        let song = profile.song
        return VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            VStack(spacing: 14) {
                ArtworkView(url: song.artworkURL, seed: song.albumTitle ?? song.title, size: 200)
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                VStack(spacing: 4) {
                    Text(song.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    NavigationLink(value: Route.artist(profile.artistID)) {
                        Text(song.artistName)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    if let album = song.albumTitle {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                actions(for: song)
            }
            .frame(maxWidth: .infinity)

            StatStrip(items: [
                .init(title: "Plays", value: song.count.formatted()),
                .init(title: "All-Time Rank", value: "#\(profile.allTimeRank)"),
                .init(title: "First Heard", value: Format.shortDate(song.firstHeard)),
                .init(title: "Last Heard", value: Format.shortDate(song.lastHeard)),
            ])

            if profile.timeline.count(where: { $0.count > 0 }) > 1 {
                PlaysOverTimeCard(timeline: profile.timeline, unit: profile.timelineUnit)
            }

            if profile.sources.count > 1 || !profile.stations.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardLabel(title: "How You Heard It", systemImage: "headphones", tint: .accentColor)
                        if profile.sources.count > 1 {
                            SourcesDonut(sources: profile.sources)
                        }
                        ForEach(profile.stations) { station in
                            Label {
                                HStack {
                                    Text(station.name)
                                    Spacer()
                                    Text("^[\(station.count) time](inflect: true)")
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(.pink)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Plays") {
                    if profile.plays.count > 8 {
                        Button(showsAllPlays ? "Show Less" : "Show All") {
                            withAnimation { showsAllPlays.toggle() }
                        }
                    }
                }
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        let plays = showsAllPlays ? profile.plays : Array(profile.plays.prefix(8))
                        ForEach(Array(plays.enumerated()), id: \.offset) { index, date in
                            HStack {
                                Text(Format.day(date))
                                Spacer()
                                Text(date, format: .dateTime.hour().minute())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.horizontal, Metrics.cardPadding)
                            .padding(.vertical, 11)
                            if index < plays.count - 1 {
                                Divider().padding(.leading, Metrics.cardPadding)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for song: SongTally) -> some View {
        if !song.songID.isEmpty, !model.isShowingSampleData {
            HStack(spacing: 12) {
                Button("Play", systemImage: "play.fill") {
                    Task { await playback.play(songID: song.songID) }
                }
                .buttonStyle(.borderedProminent)
                Button("Apple Music", systemImage: "arrow.up.forward.app") {
                    if let url = URL(string: "https://music.apple.com/song/\(song.songID)") {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}
