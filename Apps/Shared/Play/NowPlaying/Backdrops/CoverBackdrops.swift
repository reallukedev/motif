import SwiftUI
import Combine
import MotifCore

/// Keeps a background's time: running while `isMoving`, gliding to a stop when it isn't and
/// picking up from there, and drawing nothing new once it's still. Livelier songs run a
/// little faster, easing into the new pace rather than jumping to it.
struct BackdropTimeline<Content: View>: View {
    let isMoving: Bool
    var rate: Double = 1
    /// Where the time starts, in seconds.
    var start: Double = 0
    var frameRate: Double = 30
    @ViewBuilder let content: (Double) -> Content
    @State private var clock: BackdropClock?
    @State private var isAtRest = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        // Low Power Mode keeps the motion, at fewer frames: at these speeds it barely shows.
        let frames = isLowPower ? min(frameRate, 20) : frameRate
        TimelineView(.animation(minimumInterval: 1 / frames, paused: isAtRest)) { context in
            content(clock?.phase(at: context.date.timeIntervalSinceReferenceDate) ?? start)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: speed) {
            let now = Date.now.timeIntervalSinceReferenceDate
            var next = clock ?? BackdropClock(speed: speed, at: now, phase: start)
            next.setSpeed(speed, at: now)
            clock = next
            guard let wait = next.secondsToRest(from: now) else {
                isAtRest = false
                return
            }
            if wait > 0 {
                isAtRest = false
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
            }
            isAtRest = true
        }
    }

    private var speed: Double { isMoving ? rate : 0 }
}

/// Draws `content` at a fraction of the size and stretches it to fill: a soft field looks
/// the same, for a small part of the work and memory.
struct StretchedBackdrop<Content: View>: View {
    let factor: CGFloat
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            let small = CGSize(width: max(1, (proxy.size.width / factor).rounded(.up)), height: max(1, (proxy.size.height / factor).rounded(.up)))
            content(small)
                .frame(width: small.width, height: small.height)
                .drawingGroup()
                .scaleEffect(factor, anchor: .topLeading)
        }
    }
}

/// How lively the song on is, for how fast a background flows: 0.75 for the calmest, 1.25
/// for the liveliest.
private struct FlowRate {
    static func of(_ player: PlayerModel?) -> Double {
        0.75 + 0.5 * songEnergy(player?.current)
    }
}

/// Artwork: the cover, large and soft, filling the player, turning slowly while it plays.
///
/// Drawn from the cover at 96 pixels, softened once and stretched: it looks the same as a
/// full cover blurred, for a sliver of the memory. A blur the size of the window would hold
/// a picture of a quarter of a gigabyte on a large display.
struct ArtworkBackdrop: View {
    let art: BackdropArt
    let isMoving: Bool

    var body: some View {
        GeometryReader { proxy in
            BackdropTimeline(isMoving: isMoving, start: art.start, frameRate: 30) { time in
                // One slow breath every 40 seconds, and a sway half as fast.
                let breath = sin(time * 2 * .pi / 40)
                let sway = sin(time * .pi / 40 + 1)
                Image(decorative: art.soft, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1.4 + 0.1 * breath)
                    .rotationEffect(.degrees(7 * sway))
                    .offset(x: proxy.size.width * 0.04 * breath, y: proxy.size.height * 0.03 * sway)
            }
            // Clipped first, so only what's on screen is made readable.
            .clipped()
            .colorEffect(ShaderLibrary.readableColour(.float(1.3), .float(0.5)))
        }
        .background(art.field)
        .overlay {
            // Deeper toward the foot, where the controls are.
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Living Cover: the cover itself, flowing. Its colours swirl and fold into one another as
/// ink does in water, turning slowly the way Music's animated backgrounds do, for as long
/// as the music plays, and settle when it's paused. See `livingCover` in Backdrops.metal.
struct LivingCoverBackdrop: View {
    let art: BackdropArt
    let isMoving: Bool
    @Environment(PlayerModel.self) private var player: PlayerModel?

    var body: some View {
        BackdropTimeline(isMoving: isMoving, rate: FlowRate.of(player), start: art.start) { time in
            StretchedBackdrop(factor: 4) { size in
                Rectangle().fill(Self.shader(size: size, time: time, cover: art.flowing))
            }
        }
        .overlay {
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.4),
                .init(color: .black.opacity(0.3), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private static func shader(size: CGSize, time: Double, cover: CGImage) -> Shader {
        var shader = ShaderLibrary.livingCover(
            .float2(size),
            .float(time.truncatingRemainder(dividingBy: 20_000)),
            .image(Image(decorative: cover, scale: 1))
        )
        shader.dithersColor = true
        return shader
    }
}

/// Reeded Glass: the cover behind a pane of ribbed glass, each reed showing a slice of it,
/// with light on the reeds' faces and shade between them. The cover drifts behind the glass
/// while the music plays, so the slices shift as if you were walking past. See
/// `reededGlass` in Backdrops.metal.
struct ReededGlassBackdrop: View {
    let art: BackdropArt
    let isMoving: Bool

    /// A reed's width in points: wide enough to read as glass, not as stripes.
    static let reed: CGFloat = 26

    var body: some View {
        BackdropTimeline(isMoving: isMoving, rate: 0.8, start: art.start) { time in
            StretchedBackdrop(factor: 2) { size in
                Rectangle().fill(Self.shader(size: size, time: time, cover: art.clear))
            }
        }
        .overlay {
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0.35),
                .init(color: .black.opacity(0.35), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private static func shader(size: CGSize, time: Double, cover: CGImage) -> Shader {
        var shader = ShaderLibrary.reededGlass(
            .float2(size),
            .float(time.truncatingRemainder(dividingBy: 20_000)),
            .float(reed / 2),
            .image(Image(decorative: cover, scale: 1))
        )
        shader.dithersColor = true
        return shader
    }
}

/// Aurora: curtains of light in the cover's colours, rippling over a night sky of its own
/// deepest colour. They hang high, where the cover is; lower down the sky stays dark for the
/// song's name and the controls. See `aurora` in Backdrops.metal.
///
/// On a tall screen the cover fills the upper half, so the curtains hang behind it, their
/// light rising round its edges and into the sky above; on a wide one, where the song sits
/// beside the cover, they hang across the top.
struct AuroraBackdrop: View {
    let art: BackdropArt
    let isMoving: Bool
    /// Where the cover sits, in this view's space.
    let focus: CGRect?
    @Environment(PlayerModel.self) private var player: PlayerModel?

    var body: some View {
        let lights = art.lights.count >= 3 ? art.lights : Array(repeating: art.field.mix(with: .white, by: 0.6), count: 3)
        let sky = art.field.mix(with: .black, by: 0.45)
        GeometryReader { proxy in
            let (hem, tail) = Self.curtains(focus: focus, in: proxy.size)
            BackdropTimeline(isMoving: isMoving, rate: FlowRate.of(player), start: art.start) { time in
                StretchedBackdrop(factor: 3) { size in
                    Rectangle().fill(Self.shader(size: size, time: time, hem: hem, tail: tail, lights: lights, sky: sky))
                }
            }
        }
    }

    /// Where the first curtain's hem hangs, as a part of the height, and how steeply its
    /// glow fades above it.
    private static func curtains(focus: CGRect?, in size: CGSize) -> (hem: Double, tail: Double) {
        guard size.height > size.width * 1.1, size.height > 0 else { return (0.2, 7.5) }
        let middle = focus.map { Double($0.midY / size.height) } ?? 0.33
        return (min(0.5, max(0.2, middle - 0.06)), 3.5)
    }

    private static func shader(size: CGSize, time: Double, hem: Double, tail: Double, lights: [Color], sky: Color) -> Shader {
        var shader = ShaderLibrary.aurora(
            .float2(size),
            .float(time.truncatingRemainder(dividingBy: 20_000)),
            .float(hem),
            .float(tail),
            .color(lights[0]),
            .color(lights[1]),
            .color(lights[2]),
            .color(sky)
        )
        shader.dithersColor = true
        return shader
    }
}
