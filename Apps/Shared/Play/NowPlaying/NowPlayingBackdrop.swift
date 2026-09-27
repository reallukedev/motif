import SwiftUI
import CoreImage
import MotifCore
import CoreImage.CIFilterBuiltins

/// What fills the player behind the song, chosen in Settings.
enum NowPlayingBackground: String, CaseIterable, Identifiable {
    /// The cover's colour, deepening toward the controls. The default.
    case colour
    /// The cover itself, blurred to fill the screen, drifting slowly while it plays.
    case artwork
    /// The cover's colours, flowing into one another while it plays and resting when paused.
    case living
    /// Light from behind the cover in its colours, moving with the music. Stored as "pulse",
    /// the background it took the place of, so anyone who chose that keeps one that moves.
    case halo = "pulse"

    var id: String { rawValue }

    static let storageKey = "nowPlayingBackground"

    var title: LocalizedStringKey {
        switch self {
        case .colour: "Cover Colour"
        case .artwork: "Artwork"
        case .living: "Living Colour"
        case .halo: "Halo"
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .colour: "The player takes the colour of the cover, as Music's does."
        case .artwork: "The cover fills the player, softly blurred, and drifts while the music plays."
        case .living: "The cover's colours flow into one another while the music plays, and rest when it's paused."
        case .halo: "Light spills from behind the cover in its colours and moves with the music: every beat and note of your own music, and the feel of each Apple Music song, which Motif can't hear."
        }
    }
}

/// How the background turns into the next song's.
enum BackdropChange: String, CaseIterable, Identifiable {
    case crossfade, slide, bloom

    var id: String { rawValue }

    static let storageKey = "nowPlayingBackdropChange"

    var title: LocalizedStringKey {
        switch self {
        case .crossfade: "Crossfade"
        case .slide: "Slide"
        case .bloom: "Bloom"
        }
    }
}

/// The player's background: the chosen style, for the song on, changing to the next song's
/// the chosen way. Under Reduce Motion nothing drifts or flows, and songs cross-fade.
struct NowPlayingBackdrop: View {
    let cover: CoverArt?
    /// The cover's colour, read by the player for its buttons, so both match.
    let tint: Color?
    let isPlaying: Bool
    /// A preview in Settings: this style, whatever's chosen.
    var style: NowPlayingBackground?
    @AppStorage(NowPlayingBackground.storageKey) private var chosen = NowPlayingBackground.colour
    @AppStorage(BackdropChange.storageKey) private var change = BackdropChange.crossfade
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = style ?? chosen
        ZStack {
            Color.black
            layer(style)
                .id("\(style.rawValue)|\(cover.map(String.init(describing:)) ?? "")")
                .transition(transition)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.4) : animation, value: cover)
        .animation(.easeInOut(duration: 0.4), value: style)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(_ style: NowPlayingBackground) -> some View {
        switch style {
        case .colour:
            CoverStage(tint: tint)
        case .artwork:
            ArtworkBackdrop(cover: cover, tint: tint, isMoving: isPlaying && !reduceMotion)
        case .living:
            LivingBackdrop(cover: cover, tint: tint, isMoving: isPlaying && !reduceMotion)
        case .halo:
            HaloBackdrop(cover: cover, tint: tint, isPlaying: isPlaying)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch change {
        case .crossfade: return .opacity
        case .slide: return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .bloom: return .asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity), removal: .opacity)
        }
    }

    private var animation: Animation {
        switch change {
        case .crossfade: .easeInOut(duration: 0.8)
        case .slide: .smooth(duration: 0.6)
        case .bloom: .spring(duration: 0.9, bounce: 0.08)
        }
    }
}

/// The cover, large and soft, filling the player, turning slowly while it plays.
///
/// Drawn from the cover at 48 pixels, softened once and stretched: it looks the same as a
/// full cover blurred, for a sliver of the memory. A blur the size of the window would hold
/// a picture of a quarter of a gigabyte on a large display.
private struct ArtworkBackdrop: View {
    let cover: CoverArt?
    let tint: Color?
    let isMoving: Bool
    @State private var drift = false
    @State private var soft: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                (tint ?? CoverStage.fallback)
                if let soft {
                    Image(decorative: soft, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.5 : 1.3)
                        .rotationEffect(.degrees(drift ? 6 : -6))
                        .saturation(1.3)
                        .transition(.opacity)
                }
                // The words and controls read on it whatever the cover.
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .onAppear { startDrifting() }
        .onChange(of: isMoving) { startDrifting() }
        .task(id: cover) {
            guard let cover, let small = await CoverTint.smallImage(for: cover, pixels: 48) else { return }
            let softened = await OffMainActor.run { SoftCover.soften(small) }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { soft = softened ?? small }
        }
    }

    private func startDrifting() {
        guard isMoving else {
            withAnimation(.easeOut(duration: 1.2)) { drift = false }
            return
        }
        withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
    }
}

/// The cover's colours as a mesh whose points wander while the music plays.
private struct LivingBackdrop: View {
    let cover: CoverArt?
    let tint: Color?
    let isMoving: Bool
    @State private var palette: [Color] = []
    /// When it last stopped, so it rests where it was rather than jumping back.
    @State private var restingAt: Double = 0
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isMoving)) { context in
            let time = elapsed(at: context.date)
            MeshGradient(width: 3, height: 3, points: points(at: time), colors: colors)
        }
        .overlay {
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        }
        .task(id: cover) {
            guard let cover else { return }
            let found = await CoverTint.palette(for: cover)
            guard !Task.isCancelled, !found.isEmpty else { return }
            withAnimation(.easeInOut(duration: 1)) { palette = found }
        }
        .onChange(of: isMoving, initial: true) { _, moving in
            if moving {
                startedAt = .now
            } else if let startedAt {
                restingAt += Date.now.timeIntervalSince(startedAt)
                self.startedAt = nil
            }
        }
    }

    private func elapsed(at date: Date) -> Double {
        restingAt + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    private var colors: [Color] {
        let base = tint ?? CoverStage.fallback
        let p = palette.isEmpty ? [base, base.mix(with: .white, by: 0.12), base.mix(with: .black, by: 0.3), base] : palette
        return [
            p[0], p[1], p[0],
            p[2], p[3], p[1],
            p[0].mix(with: .black, by: 0.3), p[2], p[0].mix(with: .black, by: 0.4),
        ]
    }

    /// The inner points circle slowly on their own paths; the edges stay on the edges.
    private func points(at time: Double) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ amount: Double) -> Float {
            Float(sin(time * speed + phase) * amount)
        }
        return [
            [0, 0], [0.5 + wave(0.21, 0, 0.18), 0], [1, 0],
            [0, 0.5 + wave(0.17, 1.3, 0.2)], [0.5 + wave(0.23, 2.1, 0.2), 0.5 + wave(0.19, 0.4, 0.2)], [1, 0.5 + wave(0.15, 3.2, 0.2)],
            [0, 1], [0.5 + wave(0.18, 4.4, 0.18), 1], [1, 1],
        ]
    }
}
/// How lively a song is, 0 to 1, by its genres, for anything that keeps time by its feel.
func songEnergy(_ track: PlayerTrack?) -> Double {
    guard let track else { return 0.5 }
    var genres = track.song?.genreNames ?? []
    if let genre = track.local?.genre { genres.append(genre) }
    return RadioMoment.energy(ofGenres: genres) ?? 0.5
}

/// Halo: light spilling from behind the cover, in its colours, moving with the music. A
/// corona of soft rays around where the cover sits, each the loudness of one part of the
/// sound, low notes at the top, turning slowly through the cover's colours; a glow that
/// swells with the bass; a bloom as each song arrives. The rays below the cover are held
/// short, so the song's name and the controls stay easy to read.
///
/// Your own music is heard, band by band. Apple Music plays where Motif can't hear it, so for
/// it the rays keep time by the song's feel, as Stage's visualizer does. Paused, the light
/// settles and the drawing stops. Under Reduce Motion it glows, still, in the cover's colours.
///
/// Drawn at a third of the size and stretched: soft light looks the same, for a ninth of the
/// memory and work.
private struct HaloBackdrop: View {
    let cover: CoverArt?
    let tint: Color?
    let isPlaying: Bool
    @Environment(PlayerModel.self) private var player: PlayerModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: [Color] = []
    @State private var levels = SmoothedLevels()
    /// When this song arrived, for its bloom.
    @State private var arrivedAt = Date.now
    /// The slow turn of the colours, which keeps its place across pauses.
    @State private var turnedBefore: Double = 0
    @State private var turningSince: Date?

    private static let scale: CGFloat = 3

    var body: some View {
        let energy = songEnergy(player?.current)
        let settled = reduceMotion || (!isPlaying && levels.isResting && Date.now.timeIntervalSince(arrivedAt) > 2)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: settled)) { context in
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
            let frame = Frame(
                bands: bands,
                turn: turnedBefore + (turningSince.map { now.timeIntervalSince($0) } ?? 0),
                bloom: reduceMotion ? 0 : max(0, 1 - now.timeIntervalSince(arrivedAt) / 1.8)
            )
            GeometryReader { proxy in
                let size = CGSize(width: proxy.size.width / Self.scale, height: proxy.size.height / Self.scale)
                Canvas { context, size in
                    draw(frame, in: &context, size: size)
                }
                .frame(width: size.width, height: size.height)
                .drawingGroup()
                .scaleEffect(Self.scale, anchor: .topLeading)
            }
        }
        .overlay {
            // Quiet at the foot, where the controls are.
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.45),
                .init(color: .black.opacity(0.4), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .task(id: cover) {
            arrivedAt = .now
            guard let cover else { return }
            let found = await CoverTint.palette(for: cover)
            guard !Task.isCancelled, !found.isEmpty else { return }
            palette = found
        }
        .onChange(of: isPlaying, initial: true) { _, playing in
            if playing {
                turningSince = .now
            } else if let turningSince {
                turnedBefore += Date.now.timeIntervalSince(turningSince)
                self.turningSince = nil
            }
        }
        // Your own music is heard only while something's watching it.
        .onAppear { AudioLevelMeter.shared.startListening() }
        .onDisappear { AudioLevelMeter.shared.stopListening() }
    }

    private struct Frame {
        let bands: [Float]
        /// Seconds of turning, for the colours' slow sweep.
        let turn: Double
        /// 1 as a song arrives, to 0.
        let bloom: Double
    }

    private var colors: [Color] {
        let base = tint ?? CoverStage.fallback
        return palette.count >= 4 ? palette : [base, base.mix(with: .white, by: 0.25), base.mix(with: .black, by: 0.2), base.mix(with: .white, by: 0.1)]
    }

    private func draw(_ frame: Frame, in context: inout GraphicsContext, size: CGSize) {
        let colors = colors
        let side = min(size.width, size.height)
        // Where the cover sits: high on the iPhone; on the Mac, the player's middle.
        #if os(iOS)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.33)
        #else
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        #endif
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
        // into one another, so it reads as light, not as rays.
        let spokes = bands + bands.reversed()
        let edge = side * 0.4
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
        let glow = side * (0.46 + 0.16 * bass)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [colors[3].mix(with: .white, by: 0.2).opacity(0.25 + 0.35 * bass), .clear]),
                center: centre, startRadius: side * 0.2, endRadius: glow
            )
        )

        // A new song blooms in from the cover.
        if frame.bloom > 0 {
            let radius = side * (0.35 + (1 - frame.bloom) * 1.1)
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

/// Settings' choice of background: each style as a small live player to tap, as the
/// wallpaper choices in Settings are, and how it changes between songs.
struct NowPlayingBackdropPicker: View {
    @AppStorage(NowPlayingBackground.storageKey) private var chosen = NowPlayingBackground.colour
    @Environment(PlayerModel.self) private var player
    @State private var tint: Color?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(NowPlayingBackground.allCases) { style in
                Button {
                    withAnimation(.snappy) { chosen = style }
                } label: {
                    VStack(spacing: 8) {
                        NowPlayingBackdrop(cover: cover, tint: tint, isPlaying: true, style: style)
                            .overlay(alignment: .bottom) {
                                // A cover and two lines, so it reads as the player.
                                VStack(spacing: 5) {
                                    Group {
                                        if let cover {
                                            CoverImage(cover: cover, size: 34)
                                        } else {
                                            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.3)).frame(width: 34, height: 34)
                                        }
                                    }
                                    Capsule().fill(.white.opacity(0.8)).frame(width: 34, height: 3)
                                    Capsule().fill(.white.opacity(0.45)).frame(width: 24, height: 3)
                                }
                                .padding(.bottom, 14)
                            }
                            .frame(width: 68, height: 118)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(chosen == style ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.1)), lineWidth: chosen == style ? 3 : 1)
                            }
                        Text(style.title)
                            .font(.caption.weight(chosen == style ? .semibold : .regular))
                            .foregroundStyle(chosen == style ? .primary : .secondary)
                        Image(systemName: chosen == style ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen == style ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .imageScale(.medium)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(chosen == style ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .coverTint(of: cover, into: $tint)
    }

    /// The song on, or nothing: the previews show the colours they'd take.
    private var cover: CoverArt? { player.current?.cover }
}

/// Settings ▸ Play ▸ Now Playing: the background, how it changes between songs, and whether
/// the player shows the quality you're hearing.
struct NowPlayingBackdropSection: View {
    @AppStorage(NowPlayingBackground.storageKey) private var chosen = NowPlayingBackground.colour
    @AppStorage(BackdropChange.storageKey) private var change = BackdropChange.crossfade
    @AppStorage(AudioQualityBadge.showsKey) private var showsQuality = true

    var body: some View {
        Section {
            NowPlayingBackdropPicker()
            Picker("Between Songs", selection: $change) {
                ForEach(BackdropChange.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            SettingsSwitch(
                "Show Audio Quality",
                detail: Text(PlaySettingsWords.audioQualityDetail(isShown: showsQuality)),
                isOn: $showsQuality
            )
        } header: {
            Text("Now Playing")
        } footer: {
            #if os(macOS)
            Text(chosen.footer)
                .contentTransition(.opacity)
            #else
            // The iPhone's switch has no detail line: its sentence follows the background's.
            Text("\(Text(chosen.footer)) \(PlaySettingsWords.audioQualityDetail(isShown: showsQuality))")
                .contentTransition(.opacity)
            #endif
        }
    }
}

/// A small cover softened, so stretched across a screen it reads as the cover out of focus.
nonisolated enum SoftCover {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func soften(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(max(image.width, image.height)) / 10
        guard let output = blur.outputImage?.cropped(to: input.extent) else { return nil }
        return context.createCGImage(output, from: input.extent)
    }
}
