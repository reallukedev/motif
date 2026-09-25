import SwiftUI
import MotifCore

/// Summary on the Mac: the same cards as the iPhone, laid out as a dashboard.
struct MacSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(UnexpectedQuitMonitor.self) private var quitMonitor
    @AppStorage("statsRange") private var range: StatsRange = .month
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var summary: StatsSummary?
    /// 0 for this week, month or year; -1 for the one before. Back to 0 when the range changes.
    @State private var periodOffset = LaunchScene.periodOffset
    private var sources = SourceScopeSetting()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if model.hasBanner {
                        StoreWarningBanner()
                    }

                    if quitMonitor.notice != nil {
                        UnexpectedQuitNotice()
                    }

                    if model.library.isLoaded, model.library.history.isEmpty {
                        WelcomeView()
                            .padding(.top, 60)
                    } else if let summary {
                        // Hides itself once Apple Music access is granted.
                        MusicAccessCard()
                        if summary.captureCount == 0 {
                            NothingPlayedView(summary: summary)
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
        .groupedBackground()
        .navigationTitle("Summary")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Sized by its segments, so the insets either side match, as in Calendar.
                RangePicker(range: $range)
                    .fixedSize()
            }
            if sources.isOffered {
                ToolbarItem(placement: .primaryAction) {
                    SourceScopeMenu(scope: sources.selection)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Check for Missed Songs", systemImage: "arrow.clockwise") {
                    Task { await model.capture?.catchUp() }
                }
                .disabled(model.isShowingSampleData)
                .help("Fill in anything you played while Motif wasn't running")
            }
        }
        .task(id: "\(range.rawValue)|\(periodOffset)|\(sources.scope.rawValue)|\(model.library.revision)") {
            let (range, offset, scope, history, sessions) = (range, periodOffset, sources.scope, model.library.history, model.library.sessions)
            let next = await OffMainActor.run {
                StatsCalculator.summary(
                    range: range,
                    history: history.scoped(to: scope),
                    sessions: scope.includesStations ? sessions : [],
                    periodOffset: offset,
                    topLimit: 8
                )
            }
            guard !Task.isCancelled else { return }
            let isLive = summary?.range == range && summary?.periodOffset == next.periodOffset
            LiveUpdate.apply(isLive: isLive, reduceMotion: reduceMotion) {
                summary = next
            }
        }
        .onChange(of: range) { periodOffset = 0 }
        .environment(\.statsPaging, paging)
    }

    /// Steps through periods from the one on show. A step waits for the summary it asked for,
    /// so a quick double tap can't run past the first period.
    private var paging: StatsPeriodPaging? {
        guard let summary, summary.range != .allTime else { return nil }
        let isSettled = summary.periodOffset == periodOffset
        let offset = $periodOffset
        return StatsPeriodPaging(
            canGoBack: isSettled && summary.hasEarlierPeriod,
            canGoForward: isSettled && !summary.isCurrentPeriod
        ) { step in
            offset.wrappedValue = min(0, offset.wrappedValue + step)
        }
    }

    private var subtitle: String {
        guard let summary, summary.captureCount > 0 else { return "" }
        return String(AttributedString(localized: "^[\(summary.captureCount) song](inflect: true)").characters)
    }
}

private struct Dashboard: View {
    let summary: StatsSummary
    /// For "See All", which selects the matching Top Charts row rather than pushing a second
    /// copy of the list and leaving the sidebar on Summary.
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    // The tiles set the row's height at their natural size and the chart
                    // takes up the rest, so neither side has empty space at the bottom.
                    ListeningCard(summary: summary, chartHeight: 150, fillsHeight: true)
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
                            NavigationLink("Show All", value: Route.highlights(summary.range, periodOffset: summary.periodOffset))
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
                        Button("See All") { model.sidebarSelection = SidebarItem(chart: .artists) }
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

            NewFavoritesSection(summary: summary, limit: 6)
            GenresSection(summary: summary)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Listening Rhythm")
                VStack(spacing: Metrics.cardSpacing) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Metrics.cardSpacing) {
                            Card { ListeningClockCard(hourly: summary.hourly) }
                                .frame(width: 320)
                            weekCard
                        }
                        VStack(spacing: Metrics.cardSpacing) {
                            Card { ListeningClockCard(hourly: summary.hourly) }
                            weekCard
                        }
                    }
                    RhythmDetailsRow(summary: summary)
                }
            }
            .id("rhythm")

            TrendsSection(summary: summary)
            VarietySection(summary: summary)
            RecordsSection(summary: summary, columns: 3)

            Text("Listening time is estimated from when each song started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var songs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top Songs") {
                Button("See All") { model.sidebarSelection = SidebarItem(chart: .songs) }
            }
            TopSongsCard(songs: summary.topSongs, limit: 6)
        }
    }

    private var albums: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Top Albums") {
                Button("See All") { model.sidebarSelection = SidebarItem(chart: .albums) }
            }
            Card {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(summary.topAlbums.prefix(6)) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            VStack(alignment: .leading, spacing: 5) {
                                ArtworkView(url: album.artworkURL, seed: album.title, size: nil)
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
                    // Fills the card, which is as tall as the Listening Clock beside it.
                    HeatMapChart(cells: summary.heatMap, fillsHeight: true)
                } else {
                    // Fills the card, which is as tall as the Listening Clock beside it.
                    WeekdayChart(weekdays: summary.weekdays, height: nil)
                }
                if let cell = summary.busiestCell {
                    Text("Busiest around \(Format.hour(cell.hour)) on \(Calendar.current.weekdaySymbols[cell.weekday - 1])s.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DayTypeFootnotes(summary: summary)
            }
        }
    }
}
