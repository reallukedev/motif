import SwiftUI
import TracksCore

/// What fills Stage behind the song. Two of its own that move with the music, then Now
/// Playing's.
enum StageBackground: String, CaseIterable, Identifiable {
    /// The cover's colours as a mesh that drifts with the song and swells on the bass.
    case flow
    /// The cover itself, huge and soft, breathing with the beat.
    case bloom
    /// Halo is stored as "pulse", the background it took the place of.
    case colour, artwork, living, glass, aurora
    case halo = "pulse"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .flow: "Flow"
        case .bloom: "Bloom"
        default: nowPlaying?.title ?? ""
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .flow: "The cover's colours flow into one another and swell with the bass."
        case .bloom: "The cover fills the screen, soft and slowly turning, and breathes with the beat."
        default: nowPlaying?.footer ?? ""
        }
    }

    /// The same background as Now Playing's, for the ones they share.
    var nowPlaying: NowPlayingBackground? {
        switch self {
        case .flow, .bloom: nil
        case .colour: .colour
        case .artwork: .artwork
        case .living: .living
        case .glass: .glass
        case .aurora: .aurora
        case .halo: .halo
        }
    }
}

struct StageBackdrop: View {
    let style: StageBackground
    let cover: CoverArt?
    let tint: Color?
    let palette: [Color]
    let levels: SmoothedLevels
    let energy: Double
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Color.black
            switch style {
            case .flow:
                FlowBackdrop(colors: colors, levels: levels, energy: energy, isPlaying: isPlaying)
            case .bloom:
                BloomBackdrop(cover: cover, levels: levels, energy: energy, isPlaying: isPlaying)
            default:
                NowPlayingBackdrop(cover: cover, tint: tint, isPlaying: isPlaying, style: style.nowPlaying)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: style)
        .accessibilityHidden(true)
    }

    /// At least three colours, deep to light, from the cover or its tint.
    private var colors: [Color] {
        var found = palette
        if found.isEmpty { found = [tint ?? .indigo] }
        while found.count < 3 {
            found.append((found.last ?? .indigo).mix(with: .white, by: 0.3))
        }
        return found
    }
}

/// The cover's colours as a three-by-three mesh. Its inner points wander slowly, the middle
/// one pushed out by the bass, and a light at the centre swells on each kick, the way Apple
/// Music's animated backgrounds move, but in time with the song.
private struct FlowBackdrop: View {
    let colors: [Color]
    let levels: SmoothedLevels
    let energy: Double
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSettled = false
    @State private var drift = BackdropClock(speed: 0, at: Date.now.timeIntervalSinceReferenceDate)
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: isSettled || !isOnScreen)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let bands = levels.next(heard: AudioLevelMeter.shared.current(), time: time, energy: energy, isPlaying: isPlaying, calm: reduceMotion)
            let bass = Float(bands.prefix(5).reduce(0, +) / 5)
            let mid = Float(bands[6..<14].reduce(0, +) / 8)
            // Slow, whatever the song: the drift is the room, the bass is the music.
            // The drift keeps its own time, which stops while paused and goes on from there.
            let t = Float(reduceMotion ? 0 : drift.phase(at: time).truncatingRemainder(dividingBy: 10_000))
            let wander: Float = 0.13
            let points: [SIMD2<Float>] = [
                [0, 0], [0.5 + wander * sin(t * 0.21), 0], [1, 0],
                [0, 0.5 + wander * cos(t * 0.17)],
                [0.5 + (wander + mid * 0.08) * sin(t * 0.31), 0.5 + (wander + bass * 0.12) * cos(t * 0.27)],
                [1, 0.5 + wander * sin(t * 0.19 + 1)],
                [0, 1], [0.5 + wander * cos(t * 0.23), 1], [1, 1],
            ]
            let (deep, middle, light) = (colors[0], colors[1], colors[2])
            let glow = light.mix(with: .white, by: Double(0.1 + bass * 0.35))
            MeshGradient(
                width: 3,
                height: 3,
                points: points,
                colors: [
                    deep, middle, light,
                    middle, glow, deep,
                    light, deep, middle,
                ],
                smoothsColors: true
            )
            .overlay {
                // The kick, as light from the middle.
                RadialGradient(colors: [.white.opacity(Double(bass) * 0.22), .clear], center: .center, startRadius: 0, endRadius: 700)
                    .blendMode(.plusLighter)
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            }
        }
        .settles(isPlaying: isPlaying, into: $isSettled, drift: $drift)
    }
}

/// The cover, far larger than the screen and heavily blurred, turning slowly and breathing
/// with the beat: swelling and brightening on each kick. Drawn from the cover readied for the
/// backgrounds, already softened, so no blur the size of the screen is worked out each frame.
private struct BloomBackdrop: View {
    let cover: CoverArt?
    let levels: SmoothedLevels
    let energy: Double
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var art: BackdropArt?
    @State private var isSettled = false
    @State private var drift = BackdropClock(speed: 0, at: Date.now.timeIntervalSinceReferenceDate)

    init(cover: CoverArt?, levels: SmoothedLevels, energy: Double, isPlaying: Bool) {
        self.cover = cover
        self.levels = levels
        self.energy = energy
        self.isPlaying = isPlaying
        _art = State(initialValue: BackdropArtStore.shared.cached(cover))
    }
    @Environment(\.isOnScreen) private var isOnScreen

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height) * 1.5
            TimelineView(.animation(minimumInterval: 1 / 30, paused: isSettled || !isOnScreen)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let bands = levels.next(heard: AudioLevelMeter.shared.current(), time: time, energy: energy, isPlaying: isPlaying, calm: reduceMotion)
                let bass = CGFloat(bands.prefix(5).reduce(0, +) / 5)
                ZStack {
                    if let art {
                        Image(decorative: art.soft, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: side, height: side)
                            .scaleEffect(1.1 + bass * 0.12)
                            .rotationEffect(.degrees(reduceMotion ? 0 : (drift.phase(at: time) * 3).truncatingRemainder(dividingBy: 360)))
                            .saturation(1.35)
                            .brightness(Double(bass) * 0.14 - 0.1)
                            .transition(.opacity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .background(art?.field ?? CoverStage.fallback)
        .overlay {
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .settles(isPlaying: isPlaying, into: $isSettled, drift: $drift)
        .task(id: cover) {
            guard let cover else { return }
            let found = await BackdropArtStore.shared.art(for: cover)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { art = found }
        }
    }
}

extension View {
    /// Sets `isSettled` a moment after the music pauses, once what moves with it has fallen
    /// still, so the drawing can stop; clears it as soon as the music plays. `drift`, the
    /// slow motion's own time, glides to a stop with it and picks up from there.
    func settles(isPlaying: Bool, into isSettled: Binding<Bool>, drift: Binding<BackdropClock>) -> some View {
        task(id: isPlaying) {
            let now = Date.now.timeIntervalSinceReferenceDate
            drift.wrappedValue.setSpeed(isPlaying ? 1 : 0, at: now)
            guard !isPlaying else {
                isSettled.wrappedValue = false
                return
            }
            let still = drift.wrappedValue.secondsToRest(from: now) ?? 0
            try? await Task.sleep(for: .seconds(max(1.5, still)))
            guard !Task.isCancelled else { return }
            isSettled.wrappedValue = true
        }
    }
}
