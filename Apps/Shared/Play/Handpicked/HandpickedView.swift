import SwiftUI
import MusicKit
import MotifCore

/// Handpicked's page: the station at the top, and under it the songs it's made from, to add
/// to, start from, or take out. With none picked yet, the page asks for a few, in place.
struct HandpickedView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @State private var addsSongs = false
    @State private var confirmsRemoveAll = false
    @State private var isStarting = false

    var body: some View {
        let source = model.musicSource
        let picks = HandpickedPicks.shared.picks(for: source)
        ScrollView {
            VStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                hero(picks: picks)
                if picks.isEmpty {
                    emptyPicks
                        .padding(.horizontal, PlayMetrics.margin)
                } else {
                    picksList(picks, source: source)
                        .padding(.horizontal, PlayMetrics.margin)
                }
            }
            .padding(.bottom, 24)
        }
        .heroTitle(Handpicked.title)
        #if os(macOS)
        .navigationTitle(Handpicked.title)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !picks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Add Songs", systemImage: "plus") { addsSongs = true }
                            .disabled(HandpickedPicks.shared.isFull(for: source))
                        Divider()
                        Button("Remove All Picks", systemImage: "trash", role: .destructive) { confirmsRemoveAll = true }
                    }
                }
            }
        }
        .confirmationDialog(
            "Remove all \(picks.count) picks?",
            isPresented: $confirmsRemoveAll,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                withAnimation(PlayMotion.row) { HandpickedPicks.shared.removeAll(for: source) }
            }
        } message: {
            Text("The station starts again from whatever you pick next.")
        }
        .sheet(isPresented: $addsSongs) {
            HandpickedPicker()
        }
    }

    // MARK: Hero

    private func hero(picks: [Handpick]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: Handpicked.symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(height: 34, alignment: .bottomLeading)
                    .accessibilityHidden(true)
                Text(Handpicked.title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text(Handpicked.tagline)
                    .font(.title3)
                    .opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                // What Play does, above it, clear of the fade below.
                Text(picks.isEmpty
                     ? String(localized: "Pick a few songs you love, from your playlists, what you play, or a search.")
                     : String(localized: "Your picks and songs like them, chosen as it plays. What you skip steers what comes next."))
                    .font(.footnote)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                playButton(isEnabled: !picks.isEmpty)
            }
            .frame(maxWidth: Self.controlsWidth, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PlayMetrics.margin)
        .padding(.top, Self.heroTop)
        .padding(.bottom, 24 + HeroField.fade)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            HeroField(color: Handpicked.color, symbol: Handpicked.symbol)
        }
    }

    /// The station's on, playing or paused.
    private var isOn: Bool {
        player.hasQueue && player.context == Handpicked.context
    }

    private var playTitle: LocalizedStringKey {
        if isStarting { return "Starting…" }
        guard isOn else { return "Play Station" }
        return player.isPlaying ? "Pause" : "Resume"
    }

    private func playOrPause() {
        if isOn { player.togglePlayPause() } else { start(from: nil) }
    }

    @ViewBuilder
    private func playButton(isEnabled: Bool) -> some View {
        let label = Label(playTitle, systemImage: isOn && player.isPlaying ? "pause.fill" : "play.fill")
            .contentTransition(.symbolEffect(.replace))
        #if os(macOS)
        Button(action: playOrPause) { label }
            .buttonStyle(.stagePrimary(tint: Handpicked.color))
            .disabled(!isEnabled || isStarting)
        #else
        Button(action: playOrPause) {
            label
                .font(.headline)
                .foregroundStyle(Handpicked.palette[0])
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white, in: .capsule)
        }
        .buttonStyle(.pressable)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled || isStarting)
        #endif
    }

    #if os(macOS)
    private static let controlsWidth: CGFloat = 400
    private static let heroTop: CGFloat = 28
    #else
    private static let controlsWidth: CGFloat = .infinity
    private static let heroTop: CGFloat = 12
    #endif

    // MARK: Picks

    /// No picks yet: what to do, where the picks will be.
    private var emptyPicks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Pick a Few Songs")
                .font(.title3.bold())
            Text("Two or three you love is plenty. The station plays them, and finds more like them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Songs", systemImage: "plus") { addsSongs = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardFill, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func picksList(_ picks: [Handpick], source: MusicSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ShelfHeader(title: String(localized: "Your Picks")) {
                Text("\(picks.count) of \(Handpicked.limit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(picks) { pick in
                HStack(spacing: 4) {
                    Button {
                        start(from: pick)
                    } label: {
                        TrackRow(
                            title: pick.title,
                            subtitle: pick.artistName,
                            cover: pick.cover,
                            isCurrent: player.context == Handpicked.context && player.current?.songIdentity == pick.identity
                        )
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Starts the station from this song")
                    Menu {
                        pickMenu(pick, source: source)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
                .contextMenu { pickMenu(pick, source: source) }
                Divider().padding(.leading, 60)
            }
            Button {
                addsSongs = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                        .background(Color.cardFill, in: .rect(cornerRadius: CoverImage.radius(for: 48), style: .continuous))
                    Text("Add Songs")
                        .foregroundStyle(.tint)
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(HandpickedPicks.shared.isFull(for: source))
            if HandpickedPicks.shared.isFull(for: source) {
                Text("That's as many as a station takes. Take one out to add another.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .animation(PlayMotion.row, value: picks.map(\.id))
    }

    @ViewBuilder
    private func pickMenu(_ pick: Handpick, source: MusicSource) -> some View {
        Button("Start Station Here", systemImage: "play") { start(from: pick) }
        Divider()
        Button("Remove from Picks", systemImage: "minus.circle", role: .destructive) {
            withAnimation(PlayMotion.row) { _ = HandpickedPicks.shared.toggle(pick, for: source) }
        }
    }

    private func start(from pick: Handpick?) {
        isStarting = true
        Task {
            await HandpickedPlayback.start(model: model, startingWith: pick)
            isStarting = false
        }
    }
}

// MARK: - The tile

/// Handpicked on Find Your Mood, first: its own field, and the covers of the songs picked,
/// fanned at the end like a hand of records, once there are any.
struct HandpickedTile: View {
    let height: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let picks = HandpickedPicks.shared.picks(for: model.musicSource)
        NavigationLink(value: PlayRoute.handpicked) {
            ZStack(alignment: .bottomLeading) {
                HueField(color: Handpicked.color)
                // Always its symbol, never the covers picked: the tile is where you make a
                // station, not one already made.
                Image(systemName: Handpicked.symbol)
                    .font(.system(size: height * 0.62, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .rotationEffect(.degrees(-12))
                    .offset(x: height * 0.16, y: height * 0.12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
                Text(Handpicked.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(12)
            }
            .frame(width: height * 1.75, height: height)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Handpicked.title)
        .accessibilityValue(picks.isEmpty ? "" : String(localized: "\(picks.count) songs picked"))
    }
}
