import SwiftUI
import MotifCore

/// A mood with your own music: go with its flow, a live mix of your songs that suit it and new
/// ones your server finds like them, or look through them, yours and new woven together. Asks
/// nothing of Apple Music.
struct YourMusicMoodView: View {
    let mood: Mood
    @Environment(AppModel.self) private var model
    @Environment(YourMusic.self) private var music
    @Environment(PlayerModel.self) private var player
    @Environment(PlayFeed.self) private var feed
    @AppStorage(SuggestionMode.storageKey) private var suggestionMode = SuggestionMode.everything
    /// Your songs that suit the mood, the ones you play most first.
    @State private var yours: [LocalTrack] = []
    @State private var hasLoaded = false
    @State private var showsAll = false

    var body: some View {
        let finds = newFinds
        let songs = ServerMix.blend(owned: yours, new: finds)
        let isFinding = suggestionMode == .everything && !music.servers.onlineServers.isEmpty && music.discover.moodFinds[mood] == nil
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                hero(canPlay: !songs.isEmpty, hasFinds: !finds.isEmpty)
                list(songs, isFinding: isFinding || !hasLoaded)
                if hasLoaded, songs.isEmpty, !isFinding {
                    ContentUnavailableView(
                        "Nothing for \(mood.title) Yet",
                        systemImage: mood.symbol,
                        description: Text(emptyNote)
                    )
                }
            }
            .padding(.bottom, 24)
            .animation(.snappy, value: songs.count)
        }
        .toolbarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// New songs your server found for the mood, unless suggestions keep to your own music.
    private var newFinds: [LocalTrack] {
        guard suggestionMode == .everything else { return [] }
        return (music.discover.moodFinds[mood]?.songs ?? []).filter { !music.isInYourMusic($0) }
    }

    private var emptyNote: LocalizedStringKey {
        music.servers.onlineServers.isEmpty
            ? "None of your music suits it yet. Motif goes by each song's genre."
            : "None of your music suits it yet, and your server found nothing like it. Motif goes by each song's genre, and your server by songs like the ones you play."
    }

    // MARK: Hero

    private func hero(canPlay: Bool, hasFinds: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: mood.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .accessibilityHidden(true)
                Text(mood.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(mood.tagline)
                    .font(.title3)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    play(startingWith: nil)
                } label: {
                    Label("Go with the Flow", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(mood.color)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white, in: .capsule)
                }
                .buttonStyle(.pressable)
                .disabled(!canPlay)

                Text(hasFinds
                    ? "Your songs that suit it and new ones like them, picked one at a time as it plays. What you skip steers what comes next."
                    : "Your songs that suit it, picked one at a time as it plays. Skip as much as you like.")
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlayMetrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            MoodField(mood: mood)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: mood.symbol)
                        .font(.system(size: 220, weight: .bold))
                        .foregroundStyle(.white.opacity(0.1))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 60, y: 40)
                        .accessibilityHidden(true)
                }
                .clipped()
                // Up under the bar and into any pull past the top.
                .padding(.top, -400)
        }
    }

    // MARK: Songs

    @ViewBuilder
    private func list(_ songs: [LocalTrack], isFinding: Bool) -> some View {
        if !songs.isEmpty || isFinding {
            let shown = showsAll ? songs : Array(songs.prefix(10))
            VStack(alignment: .leading, spacing: 4) {
                ShelfHeader(title: String(localized: "Songs for \(mood.title)")) { EmptyView() }
                ForEach(shown) { track in
                    HStack(spacing: 4) {
                        Button {
                            play(startingWith: track)
                        } label: {
                            LocalTrackRow(track: track, isCurrent: player.current?.local?.id == track.id)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        if track.isFromServer, !music.isInYourMusic(track), !music.servers.isWaitingToKeep(track) {
                            Button("Add to Your Music", systemImage: "plus.circle") {
                                Task { player.confirm(await music.keep(track)) }
                            }
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                        }
                    }
                    .contextMenu { LocalTrackMenu(track: track) }
                    if track.id != shown.last?.id { Divider().padding(.leading, 60) }
                }
                if isFinding {
                    // New songs for it are still being found: they join as they come.
                    LoadingRows(count: songs.isEmpty ? 6 : 2)
                }
                if songs.count > 10 {
                    Button {
                        withAnimation(.snappy) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? "Show Less" : "Show More")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, PlayMetrics.margin)
        }
    }

    // MARK: Playing and loading

    /// Goes with the flow: a live mix of your songs that suit it and the new ones found, from
    /// a tapped song if there is one.
    private func play(startingWith first: LocalTrack?) {
        let (tracks, finds, history, signals, mood) = (music.playableTracks, newFinds, model.library.history, player.signals, mood)
        Task {
            let mix = await OffMainActor.run {
                LiveMix.mood(mood, from: tracks, finds: finds, history: history, signals: signals, seed: .random(in: 0...UInt64.max))
            }
            await player.startLive(mix, from: PlayContext(kind: .endless, title: mood.title), startingWith: first?.mixSong())
        }
    }

    private func load() async {
        // Once per visit: coming back from an album shouldn't look again.
        guard !hasLoaded else { return }
        let (tracks, history, signals, mood) = (music.playableTracks, model.library.history, player.signals, mood)
        let mix = await OffMainActor.run { LiveMix.mood(mood, from: tracks, history: history, signals: signals, seed: 1) }
        yours = mix.candidates
            .sorted { $0.song.plays == $1.song.plays ? $0.song.title < $1.song.title : $0.song.plays > $1.song.plays }
            .compactMap { music.index.track(id: $0.song.songID) }
        hasLoaded = true
        guard suggestionMode == .everything else { return }
        // Songs that suit it to find more like: yours you play most, then ones you've played
        // elsewhere, from your history.
        let played = await OffMainActor.run { MoodMix.songs(for: mood, in: history, signals: signals) }
        let seeds = yours.prefix(3).map { (title: $0.title, artist: $0.artist) }
            + played.prefix(3).map { (title: $0.title, artist: $0.artistName) }
        await music.discover.loadFinds(for: mood, seeds: seeds, heard: { feed.facts[$0] != nil })
    }
}
