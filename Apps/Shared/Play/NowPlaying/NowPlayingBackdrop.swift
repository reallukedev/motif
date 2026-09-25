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
    /// The cover's colours beating in time with the song's feel, swelling on every beat.
    case pulse

    var id: String { rawValue }

    static let storageKey = "nowPlayingBackground"

    var title: LocalizedStringKey {
        switch self {
        case .colour: "Cover Colour"
        case .artwork: "Artwork"
        case .living: "Living Colour"
        case .pulse: "Pulse"
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .colour: "The player takes the colour of the cover, as Music's does."
        case .artwork: "The cover fills the player, softly blurred, and drifts while the music plays."
        case .living: "The cover's colours flow into one another while the music plays, and rest when it's paused."
        case .pulse: "The cover's colours beat with the music: quick and bright for lively songs, slow and deep for calm ones, with a bloom at each new song. Motif can't hear the music, so it keeps time by the song's genre."
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
        case .pulse:
            if reduceMotion {
                LivingBackdrop(cover: cover, tint: tint, isMoving: false)
            } else {
                PulseBackdrop(cover: cover, tint: tint, isPlaying: isPlaying)
            }
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

/// The cover's colours as light, keeping time with the song.
///
/// MusicKit plays Apple Music out of reach of the app, so nothing here hears the audio. The
/// tempo comes from the song's genres (calm genres slow, lively ones quick), the beat from the
/// song's own clock, so it holds still when paused, jumps with a seek and starts again with
/// each song, which blooms in. Each beat swells the light; each bar sends a ring out from
/// the cover, as a speaker's cone would.
///
/// Drawn at a third of the size and stretched: soft light looks the same, for a ninth of the
/// memory and work.
private struct PulseBackdrop: View {
    let cover: CoverArt?
    let tint: Color?
    let isPlaying: Bool
    @Environment(PlayerModel.self) private var player: PlayerModel?
    @State private var palette: [Color] = []
    /// When it last started or stopped playing, so the beat fades in and out.
    @State private var changedPlayingAt = Date.distantPast
    @State private var isSettled = false
    /// When this song arrived, for its bloom.
    @State private var arrivedAt = Date.now
    /// The drift of the light, which keeps its place across pauses.
    @State private var restingAt: Double = 0
    @State private var startedAt: Date?

    private static let scale: CGFloat = 3

    var body: some View {
        let energy = Self.energy(of: player?.current)
        TimelineView(.animation(minimumInterval: 1 / 60, paused: isSettled)) { context in
            let now = context.date
            let frame = Frame(
                drift: restingAt + (startedAt.map { now.timeIntervalSince($0) } ?? 0),
                beats: beats(at: now, energy: energy),
                strength: strength(at: now) * (0.45 + 0.55 * energy),
                bloom: max(0, 1 - now.timeIntervalSince(arrivedAt) / 1.6),
                energy: energy
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
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .task(id: cover) {
            arrivedAt = .now
            isSettled = false
            guard let cover else { return }
            let found = await CoverTint.palette(for: cover)
            guard !Task.isCancelled, !found.isEmpty else { return }
            palette = found
        }
        .onChange(of: isPlaying, initial: true) { _, playing in
            changedPlayingAt = .now
            isSettled = false
            if playing {
                startedAt = .now
            } else if let startedAt {
                restingAt += Date.now.timeIntervalSince(startedAt)
                self.startedAt = nil
            }
        }
        // Once paused and faded, and the bloom done, it stops drawing.
        .task(id: "\(isPlaying)|\(arrivedAt.timeIntervalSinceReferenceDate)") {
            guard !isPlaying else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            isSettled = true
        }
    }

    private struct Frame {
        let drift: Double
        let beats: Double
        let strength: Double
        let bloom: Double
        let energy: Double
    }

    /// How lively the song is, 0 to 1, by its genres; the middle when they don't say.
    static func energy(of track: PlayerTrack?) -> Double {
        guard let track else { return 0.5 }
        var genres = track.song?.genreNames ?? []
        if let genre = track.local?.genre { genres.append(genre) }
        return RadioMoment.energy(ofGenres: genres) ?? 0.5
    }

    /// Beats since the song began, by its own clock: 70 a minute for the calmest, 128 for the
    /// liveliest. Without a song, a clock of its own.
    private func beats(at date: Date, energy: Double) -> Double {
        let perMinute = 70 + 58 * energy
        let time = player.map { $0.current == nil ? date.timeIntervalSinceReferenceDate : $0.playbackTime }
            ?? date.timeIntervalSinceReferenceDate
        return time * perMinute / 60
    }

    /// How hard the beat lands: rising over a moment as it plays, falling away when paused.
    private func strength(at date: Date) -> Double {
        let since = date.timeIntervalSince(changedPlayingAt)
        return isPlaying ? min(1, since / 0.9) : max(0, 1 - since / 1.4)
    }

    private var colors: [Color] {
        let base = tint ?? CoverStage.fallback
        return palette.count >= 4 ? palette : [base, base.mix(with: .white, by: 0.2), base.mix(with: .black, by: 0.25), base.mix(with: .white, by: 0.08)]
    }

    private func draw(_ frame: Frame, in context: inout GraphicsContext, size: CGSize) {
        let colors = colors
        let rect = CGRect(origin: .zero, size: size)
        let side = min(size.width, size.height)
        // Where the cover sits: high on the iPhone; on the Mac, the player's middle.
        #if os(iOS)
        let centre = CGPoint(x: size.width / 2, y: size.height * 0.33)
        #else
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        #endif
        context.fill(Path(rect), with: .color(colors[0].mix(with: .black, by: 0.6)))

        // The beat: a sharp swell that dies away before the next, the first of each bar strongest.
        let beatIndex = floor(frame.beats)
        let phase = frame.beats - beatIndex
        let accent = beatIndex.truncatingRemainder(dividingBy: 4) == 0 ? 1.0 : 0.6
        let kick = exp(-phase * 5.5) * accent * frame.strength
        let speed = 0.12 + 0.22 * frame.energy

        // Five lights on their own slow orbits, each swelling with the beat.
        for index in 0..<5 {
            let i = Double(index)
            let angle = frame.drift * speed * (0.7 + 0.13 * i) + i * 1.26
            let point = CGPoint(
                x: size.width * (0.5 + 0.34 * cos(angle)),
                y: size.height * (0.5 + 0.3 * sin(angle * 0.83 + i))
            )
            let swell = 1 + kick * (index.isMultiple(of: 2) ? 0.36 : 0.2)
            let radius = side * (0.5 + 0.08 * sin(frame.drift * 0.4 + i)) * swell
            let colour = colors[index % colors.count]
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [colour.opacity(0.9), colour.opacity(0.35), colour.opacity(0)]),
                    center: point, startRadius: 0, endRadius: radius
                )
            )
        }

        // Light thrown out from behind the cover on the beat.
        context.blendMode = .plusLighter
        let glow = side * (0.45 + 0.18 * kick)
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [colors[1].mix(with: .white, by: 0.15).opacity(0.7 * kick), colors[1].opacity(0)]),
                center: centre, startRadius: 0, endRadius: glow
            )
        )

        // A ring from each of the last two bars, spreading and fading.
        let bar = floor(frame.beats / 4)
        for back in 0..<2 {
            let progress = (frame.beats / 4 - bar + Double(back)) / 2
            guard progress < 1, frame.strength > 0 else { continue }
            let radius = side * (0.2 + progress * 0.95)
            let opacity = (1 - progress) * (1 - progress) * 0.5 * frame.strength
            context.stroke(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(colors[3].mix(with: .white, by: 0.5).opacity(opacity)),
                lineWidth: side * 0.012 * (1 + (1 - progress) * 2)
            )
        }

        // A new song blooms in from the cover.
        if frame.bloom > 0 {
            let radius = side * (0.3 + (1 - frame.bloom) * 1.1)
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [colors[1].mix(with: .white, by: 0.3).opacity(0.5 * frame.bloom), .clear]),
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

/// Settings ▸ Play ▸ Now Playing: the background and how it changes between songs.
struct NowPlayingBackdropSection: View {
    @AppStorage(NowPlayingBackground.storageKey) private var chosen = NowPlayingBackground.colour
    @AppStorage(BackdropChange.storageKey) private var change = BackdropChange.crossfade

    var body: some View {
        Section {
            NowPlayingBackdropPicker()
            Picker("Between Songs", selection: $change) {
                ForEach(BackdropChange.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("Now Playing")
        } footer: {
            Text(chosen.footer)
                .contentTransition(.opacity)
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
