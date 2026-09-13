import SwiftUI
import SwiftData
import MotifCore

/// What's playing right now, shown at the top of Summary while there's music.
struct NowPlayingCard: View {
    @Environment(CaptureService.self) private var capture
    @AppStorage(CaptureSettings.scrobblesToLastFMKey, store: CaptureSettings.sharedDefaults)
    private var scrobbles = true

    var body: some View {
        if let song = capture.nowPlaying {
            Card(padding: 12) {
                HStack(spacing: 12) {
                    ArtworkView(url: song.artworkURL, seed: song.albumTitle ?? song.title, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text(caption)
                        } icon: {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        Text(song.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(song.artistName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var caption: LocalizedStringKey {
        if let station = capture.currentStation, capture.lastCapture?.kind == .radio {
            return "Playing on \(station)"
        }
        return LastFMSessionStore.current != nil && scrobbles ? "Now Playing · Scrobbling" : "Now Playing"
    }
}

/// Stations, Play Back and how much of the radio has been played back. Only shown when
/// the range has radio in it.
struct RadioCard: View {
    let summary: StatsSummary
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Query private var today: [Capture]

    init(summary: StatsSummary) {
        self.summary = summary
        let start = Calendar.current.startOfDay(for: .now)
        let radio = CaptureKind.radio.rawValue
        _today = Query(filter: #Predicate<Capture> {
            $0.capturedAt >= start && $0.kindRawValue == radio && $0.playedBackAt == nil
        })
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(title: "Radio", systemImage: "dot.radiowaves.left.and.right", tint: .pink)

                if summary.topStations.isEmpty {
                    Text("Station names only show up when Motif sees you tune in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(summary.topStations.prefix(4)) { station in
                            AdaptiveStack {
                                Text(station.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("^[\(station.count) song](inflect: true)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !today.isEmpty, !model.isShowingSampleData {
                    Divider()
                    AdaptiveStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("^[\(today.count) radio song](inflect: true) from today")
                                .font(.subheadline.weight(.medium))
                            Text("Apple Music doesn't count radio as plays. Playing them back does.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Play Back", systemImage: "play.fill") {
                            Task { await playback.playBackToday() }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.pink)
                        .disabled(playback.isPlaying)
                    }
                    if let error = playback.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

/// Shown above everything while someone is looking at sample data they chose. Hidden for
/// `-MotifDemoData` launches, which are for screenshots.
struct SampleDataBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sampleStore != nil {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sample Data")
                        .font(.subheadline.weight(.semibold))
                    Text("Invented listening, so you can look around. Nothing here is yours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Done") { model.hideSampleData() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .padding(12)
            .background(.tint.opacity(0.1), in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// When the real store couldn't be opened and we fell back to memory, nothing will be kept.
struct StoreWarningBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.isShowingSampleData, case .inMemory(let reason) = model.store?.backing {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your listening isn't being saved")
                        .font(.subheadline.weight(.semibold))
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

/// The first-run screen: what Motif does, and a way to see it without any history yet.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Your listening will show up here", systemImage: "waveform")
        } description: {
            Text("Play something in Apple Music. Motif keeps what you listen to, including radio, and turns it into charts and highlights.")
        } actions: {
            Button("Explore with Sample Data") { model.showSampleData() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}
