import SwiftUI
import MotifCore

/// The song's position, as Music draws it: a thin track that thickens under the finger, the
/// time gone on the left and the time left on the right.
struct Scrubber: View {
    let duration: TimeInterval
    let isPlaying: Bool
    let time: () -> TimeInterval
    /// The song, whose audio quality shows between the times as Music shows Lossless.
    var track: PlayerTrack? = nil
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !isPlaying || dragFraction != nil || !isOnScreen)) { _ in
            let fraction = dragFraction ?? (duration > 0 ? min(1, max(0, time() / duration)) : 0)
            let elapsed = fraction * duration
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        // Slid along rather than resized, so each tick only redraws.
                        Capsule()
                            .fill(.white.opacity(dragFraction == nil ? 0.7 : 1))
                            .offset(x: -proxy.size.width * (1 - fraction))
                    }
                    .frame(height: dragFraction == nil ? 6 : 12)
                    .clipShape(.capsule)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.14)) {
                                    dragFraction = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                                }
                            }
                            .onEnded { _ in
                                if let dragFraction { onSeek(dragFraction * duration) }
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { dragFraction = nil }
                            }
                    )
                }
                .frame(height: 24)

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(verbatim: "-" + Self.format(max(0, duration - elapsed)))
                }
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(dragFraction == nil ? 0.6 : 0.9))
            }
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue(Text("\(Self.format(elapsed)) of \(Self.format(duration))"))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 15 : -15
                onSeek(min(duration, max(0, elapsed + step)))
            }
        }
        // Its own element after the position, since it opens its details, and outside the
        // timeline, which redraws four times a second. Centred on the times' line: a hidden
        // line of the times' type is its anchor at every text size.
        .overlay(alignment: .bottom) {
            if let track {
                Text(verbatim: "0")
                    .font(.caption.weight(.medium))
                    .hidden()
                    .overlay { AudioQualityBadge(track: track).fixedSize() }
            }
        }
    }

    /// "3:07", or "1:02:07" past an hour.
    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return Duration.seconds(whole).formatted(
            .time(pattern: whole >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }
}

/// A station has no length: the track stays full, marked live.
struct LiveScrubber: View {
    var body: some View {
        VStack(spacing: 8) {
            Capsule().fill(.white.opacity(0.2)).frame(height: 6).frame(height: 24)
            HStack {
                LiveBadge()
                Spacer()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Live radio")
    }
}
