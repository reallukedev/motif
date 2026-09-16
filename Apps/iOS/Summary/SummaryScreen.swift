import SwiftUI
import MotifCore

struct SummaryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("statsRange") private var range: StatsRange = .month
    @State private var summary: StatsSummary?
    @State private var showsSettings = LaunchScene.opensSettings

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if model.hasBanner || model.capture?.nowPlaying != nil {
                        VStack(spacing: 12) {
                            StoreWarningBanner()
                            NowPlayingCard()
                        }
                    }

                    if model.library.isLoaded, model.library.history.isEmpty {
                        WelcomeView()
                            .padding(.top, 40)
                    } else {
                        RangePicker(range: $range)
                        if let summary {
                            if summary.captureCount == 0 {
                                ContentUnavailableView(
                                    "Nothing Played \(Text(range.phrase))",
                                    systemImage: "waveform",
                                    description: Text("Try a longer range.")
                                )
                            } else {
                                SummaryContent(summary: summary)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .animation(LiveUpdate.animation(reduceMotion: reduceMotion), value: model.capture?.nowPlaying)
            .onChange(of: summary != nil) {
                if let anchor = LaunchScene.scrollAnchor {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
        .groupedBackground()
        .navigationTitle("Summary")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
        }
        .refreshable {
            if !model.isShowingSampleData { await model.capture?.catchUp() }
        }
        .task(id: "\(range.rawValue)|\(model.library.revision)") {
            let (range, history, sessions) = (range, model.library.history, model.library.sessions)
            let next = await OffMainActor.run {
                StatsCalculator.summary(range: range, history: history, sessions: sessions, topLimit: 5)
            }
            guard !Task.isCancelled else { return }
            LiveUpdate.apply(isLive: summary?.range == range, reduceMotion: reduceMotion) {
                summary = next
            }
        }
    }
}

/// Everything below the range picker.
struct SummaryContent: View {
    let summary: StatsSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            // Hides itself once access is granted.
            MusicAccessCard()

            VStack(spacing: 12) {
                ListeningCard(summary: summary)
                GlanceGrid(summary: summary, columns: 2)
            }

            if !summary.insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Highlights") {
                        if summary.insights.count > 3 {
                            NavigationLink("Show All", value: Route.highlights(summary.range))
                        }
                    }
                    EqualHeightRows(items: Array(summary.insights.prefix(3)), columns: 1) { insight in
                        HighlightCard(insight: insight)
                    }
                }
                .id("highlights")
            }

            if !summary.topArtists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Top Artists") {
                        Button("See All") { showChart(.artists) }
                    }
                    TopArtistsShelf(artists: summary.topArtists)
                }
                .id("artists")
            }

            if !summary.topSongs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Top Songs") {
                        Button("See All") { showChart(.songs) }
                    }
                    TopSongsCard(songs: summary.topSongs)
                }
                .id("songs")
            }

            if !summary.topAlbums.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Top Albums") {
                        Button("See All") { showChart(.albums) }
                    }
                    TopAlbumsShelf(albums: summary.topAlbums)
                }
                .id("albums")
            }

            NewFavoritesSection(summary: summary, limit: 5)
            GenresSection(summary: summary)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Listening Rhythm")
                VStack(spacing: Metrics.cardSpacing) {
                    CardPair {
                        Card { ListeningClockCard(hourly: summary.hourly) }
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                CardLabel(title: "By Day", systemImage: "calendar")
                                WeekdayChart(weekdays: summary.weekdays)
                                if let busiest = summary.weekdays.max(by: { $0.count < $1.count }), busiest.count > 0 {
                                    Text("Busiest on \(Calendar.current.weekdaySymbols[busiest.weekday - 1])s.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                DayTypeFootnotes(summary: summary)
                            }
                        }
                    }
                    RhythmDetailsRow(summary: summary)
                }
            }
            .id("rhythm")

            TrendsSection(summary: summary)
            VarietySection(summary: summary)
            RecordsSection(summary: summary, columns: 2)

            Text("Listening time is estimated from when each song started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Moves to the Charts tab, which holds the full lists, rather than pushing a second copy
    /// of one inside Summary and leaving the tab bar pointing at the wrong place.
    private func showChart(_ kind: ChartKind) {
        kind.select()
        model.selectedTab = .charts
    }
}
