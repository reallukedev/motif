import SwiftUI
import MotifCore

/// Radio: your own station first, on a field of its colour, then the moods, then Apple Music's
/// live stations.
struct RadioPage: View {
    @Environment(PlayFeed.self) private var feed
    @Environment(AppModel.self) private var model
    @AppStorage(PlayPreferences.motifRadioKey) private var isRadioOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PlayMetrics.sectionSpacing) {
                if isRadioOn {
                    MotifRadioStage()
                } else {
                    radioOff
                }
                MoodGrid()
                if !feed.liveStations.isEmpty {
                    Shelf(title: String(localized: "Live Radio"), items: feed.liveStations) { item in
                        FeedTile(item: item)
                    }
                } else if feed.appleMusicState == .loading {
                    LoadingRows(count: 2)
                        .padding(.horizontal, PlayMetrics.margin)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Radio")
        .task(id: model.musicAuthorization) { await feed.loadAppleMusic() }
    }

    /// Motif Radio hidden in Settings: said so where it would be, with the way back.
    private var radioOff: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Motif Radio Is Off")
                .font(.title3.bold())
            Text("Your own station plays everything you love and new finds like it, picked as it plays.")
                .foregroundStyle(.secondary)
            Button("Turn On Motif Radio") { isRadioOn = true }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(.horizontal, PlayMetrics.margin)
    }
}

/// Motif Radio across the top of Radio: its artwork, what it's tuned to, and Play and Tune, on
/// a field of the station's own red.
private struct MotifRadioStage: View {
    @Environment(PlayerModel.self) private var player
    @AppStorage(PlayPreferences.radioTuningKey) private var storedTuning = ""
    @State private var showsTuner = false

    var body: some View {
        let isOn = player.isPlayingMotifRadio
        let tuning = RadioTuning(stored: storedTuning)
        HStack(alignment: .center, spacing: 28) {
            Button {
                if isOn { player.togglePlayPause() } else { player.playMotifRadio() }
            } label: {
                MotifRadioArt(side: 200, isLive: isOn && player.isPlaying, isDriving: player.isRadioDriving)
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Motif Radio")

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Station")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Text("Motif Radio")
                    .font(.system(size: 30, weight: .bold))
                Text(tuning.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                onAir(isOn: isOn)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Button {
                        if isOn { player.togglePlayPause() } else { player.playMotifRadio() }
                    } label: {
                        Label(isOn && player.isPlaying ? "Pause" : isOn ? "Resume" : "Play", systemImage: isOn && player.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.stagePrimary(tint: MotifRadioArt.color))
                    Button("Tune…", systemImage: "slider.horizontal.3") { showsTuner = true }
                        .buttonStyle(.stageSecondary)
                        .help("How adventurous it is, the genres it leans into, and old favorites")
                }
                .padding(.top, 12)
            }
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(MotifRadioArt.color.mix(with: .black, by: 0.35).gradient)
        }
        .padding(.horizontal, PlayMetrics.margin)
        .contextMenu {
            Button(isOn && player.isPlaying ? "Pause" : isOn ? "Resume" : "Play Motif Radio", systemImage: isOn && player.isPlaying ? "pause" : "play") {
                if isOn { player.togglePlayPause() } else { player.playMotifRadio() }
            }
            Button("Tune Motif Radio…", systemImage: "slider.horizontal.3") { showsTuner = true }
        }
        .sheet(isPresented: $showsTuner) { RadioTunerSheet() }
    }

    /// What's on it now, while it plays: the song, and that what's next is being picked. Before
    /// then, what it does, in a line.
    @ViewBuilder
    private func onAir(isOn: Bool) -> some View {
        if isOn, let track = player.current {
            HStack(spacing: 10) {
                CoverImage(cover: track.cover, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying)
                        Text("On Air")
                            .textCase(.uppercase)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    Text("\(track.title) · \(track.artistName)")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .background(.white.opacity(0.12), in: .capsule)
            .transition(.opacity)
            .id(track.id)
        } else {
            Text("Picked one song at a time as it plays. What you skip steers what comes next.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading)
        }
    }
}
