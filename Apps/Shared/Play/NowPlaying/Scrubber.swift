import SwiftUI
import MotifCore

/// The song's position, as Music draws it: a thin track that thickens under the finger, the
/// time gone on the left and the time left on the right.
struct Scrubber: View {
    let duration: TimeInterval
    let isPlaying: Bool
    let time: () -> TimeInterval
    /// Your own music's format, shown between the times as Music shows Lossless.
    var format: AudioFormat? = nil
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !isPlaying || dragFraction != nil)) { _ in
            let fraction = dragFraction ?? (duration > 0 ? min(1, max(0, time() / duration)) : 0)
            let elapsed = fraction * duration
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule()
                            .fill(.white.opacity(dragFraction == nil ? 0.7 : 1))
                            .frame(width: max(0, proxy.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 6 : 12)
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

                ZStack {
                    HStack {
                        Text(Self.format(elapsed))
                        Spacer()
                        Text(verbatim: "-" + Self.format(max(0, duration - elapsed)))
                    }
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(dragFraction == nil ? 0.6 : 0.9))
                    if let format {
                        FormatBadge(format: format, onDark: true)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue(Text("\(Self.format(elapsed)) of \(Self.format(duration))"))
            .accessibilityAdjustableAction { direction in
                let step: TimeInterval = direction == .increment ? 15 : -15
                onSeek(min(duration, max(0, elapsed + step)))
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
