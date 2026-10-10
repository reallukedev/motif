import SwiftUI
import TracksCore

/// How lively a song is, 0 to 1, by its genres, for anything that keeps time by its feel.
func songEnergy(_ track: PlayerTrack?) -> Double {
    guard let track else { return 0.5 }
    var genres = track.song?.genreNames ?? []
    if let genre = track.local?.genre { genres.append(genre) }
    return RadioMoment.energy(ofGenres: genres) ?? 0.5
}

/// Halo: light spilling from behind the cover, in its colours, moving with the music. A
/// corona of soft rays around the cover, each the loudness of one part of the sound, low
/// notes at the top, turning slowly through the cover's colours; a glow that swells with the
/// bass; a bloom as each song arrives. The rays below the cover are held short, so the song's
/// name and the controls stay easy to read.
///
/// It's centred on the cover wherever the player puts it (see
/// ``SwiftUI/View/backdropFocus()``), and follows it, gliding, when the cover moves.
///
/// Your own music is heard, band by band. Apple Music plays where Tracks can't hear it, so for
/// it the rays keep time by the song's feel, as Stage's visualizer does. Paused, the light
/// settles and the drawing stops. Under Reduce Motion it glows, still, in the cover's colours.
///
/// Drawn at a third of the size and stretched: soft light looks the same, for a ninth of the
/// memory and work.
struct HaloBackdrop: View {
    let art: BackdropArt
    let isPlaying: Bool
    /// Where the cover sits, in this view's space.
    let focus: CGRect?
    @Environment(PlayerModel.self) private var player: PlayerModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var levels = SmoothedLevels()
    /// When this song arrived, for its bloom.
    @State private var arrivedAt = Date.now
    /// The slow turn of the colours, which keeps its place across pauses.
    @State private var turn = BackdropClock(speed: 0, at: Date.now.timeIntervalSinceReferenceDate)
    /// Paused, and the light has settled: nothing left to draw.
    @State private var isSettled = false

    private static let scale: CGFloat = 3
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        let energy = songEnergy(player?.current)
        GeometryReader { proxy in
            let light = Light(focus: focus, in: proxy.size)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || isSettled || !isOnScreen)) { context in
                let now = context.date
                let bands = reduceMotion
                    ? [Float](repeating: 0.3, count: AudioLevelMeter.bandCount)
                    : levels.next(
                        heard: AudioLevelMeter.shared.current(),
                        time: now.timeIntervalSinceReferenceDate,
                        energy: energy,
                        isPlaying: isPlaying,
                        calm: false
                    )
                let frame = HaloFrame(
                    bands: bands,
                    turn: turn.phase(at: now.timeIntervalSinceReferenceDate),
                    bloom: reduceMotion ? 0 : max(0, 1 - now.timeIntervalSince(arrivedAt) / 1.8)
                )
                HaloLight(frame: frame, colors: colors, light: light, scale: Self.scale)
            }
            .animation(.smooth(duration: 0.6), value: light)
        }
        .overlay {
            // Quiet at the foot, where the controls are.
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.45),
                .init(color: .black.opacity(0.4), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .task(id: isPlaying) {
            let now = Date.now.timeIntervalSinceReferenceDate
            turn.setSpeed(isPlaying ? 1 : 0, at: now)
            guard !isPlaying else {
                isSettled = false
                return
            }
            // The rays fall back in about a second, and a song's bloom takes two.
            let bloomLeft = max(0, 1.8 - Date.now.timeIntervalSince(arrivedAt))
            try? await Task.sleep(for: .seconds(max(1.5, bloomLeft) + 0.2))
            guard !Task.isCancelled else { return }
            isSettled = true
        }
        // Your own music is heard only while something's watching it.
        .onAppear { AudioLevelMeter.shared.startListening() }
        .onDisappear { AudioLevelMeter.shared.stopListening() }
    }

    private var colors: [Color] {
        if art.deep.count >= 4 { return art.deep }
        let base = art.field
        return [base, base.mix(with: .white, by: 0.25), base.mix(with: .black, by: 0.2), base.mix(with: .white, by: 0.1)]
    }
}

/// Where the light comes from, as parts of the size, and how large the cover is, as a part
/// of the shorter side. Animatable, so the light glides after the cover.
private struct Light: Equatable {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat

    init(focus: CGRect?, in size: CGSize) {
        let side = max(1, min(size.width, size.height))
        if let focus, focus.width > 0, size.width > 0, size.height > 0 {
            x = focus.midX / size.width
            y = focus.midY / size.height
            radius = min(focus.width, focus.height) / 2 / side
        } else {
            // With nothing marked: where the cover usually sits. High on the iPhone; on the
            // Mac, the player's middle.
            #if os(iOS)
            (x, y, radius) = (0.5, 0.33, 0.43)
            #else
            (x, y, radius) = (0.5, 0.5, 0.3)
            #endif
        }
    }
}

private struct HaloFrame {
    let bands: [Float]
    /// Seconds of turning, for the colours' slow sweep.
    let turn: Double
    /// 1 as a song arrives, to 0.
    let bloom: Double
}

private struct HaloLight: View, Animatable {
    let frame: HaloFrame
    let colors: [Color]
    var light: Light
    let scale: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(light.x, light.y), light.radius) }
        set { (light.x, light.y, light.radius) = (newValue.first.first, newValue.first.second, newValue.second) }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width / scale, height: proxy.size.height / scale)
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: size.width, height: size.height)
            .drawingGroup()
            .scaleEffect(scale, anchor: .topLeading)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let centre = CGPoint(x: size.width * light.x, y: size.height * light.y)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors[0].mix(with: .black, by: 0.62)))

        let bands = frame.bands
        let bass = Double(bands.prefix(4).reduce(0, +)) / 4
        let loudness = Double(bands.reduce(0, +)) / Double(max(1, bands.count))

        // A wide, dim wash behind it all, breathing with the song as a whole.
        let wash = side * (0.95 + 0.12 * loudness)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - wash, y: centre.y - wash, width: wash * 2, height: wash * 2)),
            with: .radialGradient(
                Gradient(colors: [colors[1].opacity(0.45), colors[2].opacity(0.18), .clear]),
                center: centre, startRadius: 0, endRadius: wash
            )
        )

        // The corona: each band twice, mirrored, so it's whole, the low notes at the top. The
        // rays pointing down stay short, clear of the words below the cover. Wide and blurred
        // into one another, so it reads as light, not as rays. They reach as far as the cover
        // is large, so a small cover in a large window isn't lost in its own light.
        let spokes = bands + bands.reversed()
        let edge = side * light.radius
        let sweep = frame.turn * 0.04
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: side * 0.02))
            layer.blendMode = .plusLighter
            for (index, level) in spokes.enumerated() {
                let angle = Double(index) / Double(spokes.count) * 2 * .pi - .pi / 2
                let downward = max(0, sin(angle))
                let reach = 1 - 0.75 * downward
                let length = edge * (0.22 + 0.85 * Double(level)) * reach
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                let middle = CGPoint(x: centre.x + direction.x * (edge * 0.92 + length * 0.3), y: centre.y + direction.y * (edge * 0.92 + length * 0.3))
                let width = edge * 0.5
                // Through the cover's colours, turning slowly.
                let hue = (Double(index) / Double(spokes.count) + sweep).truncatingRemainder(dividingBy: 1)
                let colour = colors[1 + Int(hue * Double(colors.count - 1)) % (colors.count - 1)]
                var ray = layer
                ray.translateBy(x: middle.x, y: middle.y)
                ray.rotate(by: .radians(angle))
                ray.fill(
                    Path(ellipseIn: CGRect(x: -length, y: -width / 2, width: length * 2, height: width)),
                    with: .radialGradient(
                        Gradient(colors: [colour.mix(with: .white, by: 0.1).opacity(0.14 + 0.34 * Double(level)), colour.opacity(0)]),
                        center: .zero, startRadius: 0, endRadius: length
                    )
                )
            }
        }

        context.blendMode = .plusLighter
        // Light from right behind the cover, swelling with the bass.
        let glow = edge * (1.15 + 0.4 * bass)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [colors[3].mix(with: .white, by: 0.2).opacity(0.25 + 0.35 * bass), .clear]),
                center: centre, startRadius: edge * 0.5, endRadius: glow
            )
        )

        // A new song blooms in from the cover.
        if frame.bloom > 0 {
            let radius = edge * 0.9 + side * (1 - frame.bloom) * 1.1
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [colors[1].mix(with: .white, by: 0.3).opacity(0.45 * frame.bloom), .clear]),
                    center: centre, startRadius: 0, endRadius: radius
                )
            )
        }
    }
}
