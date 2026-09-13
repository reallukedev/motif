import SwiftUI
import MotifCore

/// Summary on the Mac: the same cards as the iPhone, laid out as a dashboard.
struct MacSummaryView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("statsRange") private var range: StatsRange = .month
    @State private var summary: StatsSummary?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if model.hasBanner {
                        VStack(spacing: 10) {
                            StoreWarningBanner()
                            SampleDataBanner()
                        }
                    }

                    if model.library.isLoaded, model.library.history.isEmpty {
                        WelcomeView()
                            .padding(.top, 60)
                    } else if let summary {
                        if summary.captureCount == 0 {
                            ContentUnavailableView(
                                "Nothing Played \(Text(range.phrase))",
                                systemImage: "waveform",
                                description: Text("Try a longer range.")
                            )
                            .padding(.top, 60)
                        } else {
                            Dashboard(summary: summary)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: summary != nil) {
                if let anchor = LaunchScene.scrollAnchor {
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
        .background(GroupedBackground())
        .navigationTitle("Summary")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                RangePicker(range: $range)
                    .frame(width: 300)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Check for Missed Songs", systemImage: "arrow.clockwise") {
                    Task { await model.capture?.catchUp() }
                }
                .disabled(model.isShowingSampleData)
                .help("Fill in anything you played while Motif wasn't running")
            }
        }
        .task(id: "\(range.rawValue)|\(model.library.revision)") {
            summary = StatsCalculator.summary(
                range: range,
                history: model.library.history,
                sessions: model.library.sessions,
                topLimit: 8
            )
        }
    }

    private var subtitle: String {
        guard let summary, summary.captureCount > 0 else { return "" }
        return String(AttributedString(localized: "^[\(summary.captureCount) song](inflect: true)").characters)
    }
}

private struct Dashboard: View {
    let summary: StatsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ListeningCard(summary: summary, chartHeight: 220)
                        .frame(minWidth: 560)
                    GlanceGrid(summary: summary, columns: 1)
                        .frame(width: 260)
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 16) {
                    ListeningCard(summary: summary, chartHeight: 190)
                    GlanceGrid(summary: summary, columns: 4)
                }
            }

            if !summary.insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Highlights") {
                        if summary.insights.count > 3 {
                            NavigationLink("Show All", value: Route.highlights(summary.range))
                        }
                    }
                    EqualHeightRows(items: Array(summary.insights.prefix(6)), columns: 3, spacing: 14) { insight in
                        HighlightCard(insight: insight)
                    }
                }
                .id("highlights")
            }

            if !summary.topArtists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Top Artists") {
                        NavigationLink("See All", value: Route.chart(.artists))
                    }
                    TopArtistsShelf(artists: summary.topArtists, artworkSize: 110)
                }
                .id("artists")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    songs.frame(minWidth: 420)
                    albums.frame(minWidth: 420)
                }
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    songs
                    albums
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("When You Listen")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        Card { ListeningClockCard(hourly: summary.hourly) }
                            .frame(width: 320)
                        weekCard
                    }
                    VStack(spacing: 16) {
                        Card { ListeningClockCard(hourly: summary.hourly) }
                        weekCard
                    }
                }
            }
            .id("rhythm")

            if summary.sourcesAreInformative || summary.sources.contains(where: { $0.kind == .radio }) {
                HStack(alignment: .top, spacing: 16) {
                    if summary.sourcesAreInformative {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                CardLabel(title: "How You Listened", systemImage: "headphones")
                                SourcesDonut(sources: summary.sources)
                            }
                        }
                    }
                    if summary.sources.contains(where: { $0.kind == .radio }) {
                        RadioCard(summary: summary)
                    }
                }
            }

            Text("Listening time is estimated from when each song started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var songs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top Songs") {
                NavigationLink("See All", value: Route.chart(.songs))
            }
            TopSongsCard(songs: summary.topSongs, limit: 6)
        }
    }

    private var albums: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top Albums") {
                NavigationLink("See All", value: Route.chart(.albums))
            }
            Card {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(summary.topAlbums.prefix(6)) { album in
                        NavigationLink(value: Route.artist(StatsCalculator.folded(album.artistName))) {
                            VStack(alignment: .leading, spacing: 5) {
                                GeometryReader { geometry in
                                    ArtworkView(url: album.artworkURL, seed: album.title, size: geometry.size.width)
                                }
                                .aspectRatio(1, contentMode: .fit)
                                Text(album.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(album.artistName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(title: "Your Week", systemImage: "calendar")
                if summary.heatMapIsInformative {
                    HeatMapChart(cells: summary.heatMap)
                } else {
                    WeekdayChart(weekdays: summary.weekdays, height: 150)
                }
                if let cell = summary.busiestCell {
                    Text("Busiest around \(Format.hour(cell.hour)) on \(Calendar.current.weekdaySymbols[cell.weekday - 1])s.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
