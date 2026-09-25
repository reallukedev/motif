import SwiftUI
import MusicKit
import MotifCore

/// The crate at the top of Play: this hour's mix, Motif Radio, Discover and the rest of the
/// day's mixes, flipped through like records, as Cover Flow flipped through albums. The one in
/// front says why it's there and plays in one tap; the page behind glows in its colour.
struct Crate: View {
    let cards: [ForYouCard]
    /// The card to start in front of: Motif Radio, with this hour's mix beside it.
    let leadID: String?

    @Environment(PlayerModel.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var front: String?
    /// Whether the crate's been flipped by hand, after which it stays where it was put.
    @State private var hasMoved = false
    @State private var width: CGFloat = 0
    @State private var glow: Color?
    @State private var showsTuner = LaunchScene.opensRadioTuner
    @FocusState private var isFocused: Bool
    #if os(macOS)
    @State private var isHovering = false
    #endif

    var body: some View {
        let current = cards.first { $0.id == front } ?? cards.first
        VStack(spacing: Self.detailsGap) {
            flow
            if let current {
                CrateDetails(record: record(for: current), showsTuner: $showsTuner)
                    .id(current.id)
                    .transition(.opacity)
                if cards.count > 1 {
                    PageDots(ids: cards.map(\.id), current: current.id) { id in move(to: id) }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current?.id)
        .background(alignment: .top) {
            CrateGlow(color: glow)
        }
        .task(id: current?.id) {
            guard let current else { return }
            let found = await record(for: current).tint()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { glow = found }
        }
        .onAppear {
            if front == nil { front = leadID ?? cards.first?.id }
        }
        .sheet(isPresented: $showsTuner) { RadioTunerSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("For You")
    }

    // MARK: - The flow

    private var flow: some View {
        // Taken out for the fan, which is worked out off the main actor as the crate scrolls.
        let (side, spacing, stillness) = (self.side, Self.spacing, reduceMotion)
        let frontIndex = cards.firstIndex { $0.id == front } ?? 0
        return ScrollViewReader { proxy in ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let record = record(for: card)
                    Button {
                        if front == card.id { open(record) } else { move(to: card.id) }
                    } label: {
                        record.cover(side)
                            .shadow(color: .black.opacity(0.3), radius: 22, y: 14)
                    }
                    .buttonStyle(CrateCoverStyle(isFront: front == card.id))
                    .frame(width: side, height: side)
                    // Room for the shadow, inside the scroll view's clip.
                    .padding(.vertical, Self.shadowRoom)
                    .visualEffect { content, proxy in
                        content.fanned(by: Self.turn(of: proxy, side: side, spacing: spacing), side: side, spacing: spacing, reduceMotion: stillness)
                    }
                    // The record in front is on top of the stack, and each behind it lower.
                    .zIndex(-Double(abs(index - frontIndex)))
                    .accessibilityLabel(record.title)
                    .accessibilityHint(front == card.id ? String(localized: "Opens it") : String(localized: "Brings it to the front"))
                    .contextMenu { CrateMenu(record: record, showsTuner: $showsTuner) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $front, anchor: .center)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { hasMoved = true }
        }
        // What's in front has to be the record chosen. The cards can change under it, as the
        // history arrives and Motif Radio joins them in the middle, and the page's width is
        // only known after the first layout, which moves the middle: each time, back to the
        // one chosen, or to the lead until someone has moved it themselves.
        .onChange(of: "\(cards.map(\.id).joined(separator: ","))|\(leadID ?? "")|\(Int(width))", initial: true) {
            if !hasMoved || !cards.contains(where: { $0.id == front }) {
                front = leadID ?? cards.first?.id
            }
            guard let front else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(front, anchor: .center) }
        }
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .contentMargins(.horizontal, max(0, (width - side) / 2), for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(height: side + Self.shadowRoom * 2)
        // The records farthest out fade into the page rather than stopping at its edge.
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.09),
                        .init(color: .black, location: 0.91), .init(color: .clear, location: 1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .padding(.vertical, -Self.shadowRoom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        #if os(macOS)
        // The keyboard flips through the crate, as the arrows did in Cover Flow.
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        // Return opens the front record, as a click does.
        .onKeyPress(.return) {
            if let card = cards.first(where: { $0.id == front }) { open(record(for: card)) }
            return .handled
        }
        .overlay { if isHovering { hoverArrows } }
        .overlay(alignment: .center) {
            // The system's ring goes around the whole crate; this one goes around the record
            // the keys act on.
            if isFocused {
                RoundedRectangle(cornerRadius: CoverImage.radius(for: side) + 4, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 3)
                    .frame(width: side + 8, height: side + 8)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovering = $0 }
        #endif
    }

    #if os(macOS)
    /// Arrows at either side of the front record while the pointer is over the crate.
    private var hoverArrows: some View {
        HStack {
            arrow(-1, systemImage: "chevron.backward", label: "Previous")
            Spacer()
            arrow(1, systemImage: "chevron.forward", label: "Next")
        }
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    private func arrow(_ step: Int, systemImage: String, label: LocalizedStringKey) -> some View {
        let index = cards.firstIndex { $0.id == front } ?? 0
        let isAvailable = cards.indices.contains(index + step)
        return Button(label, systemImage: systemImage) { self.step(step) }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .opacity(isAvailable ? 1 : 0)
            .disabled(!isAvailable)
    }
    #endif

    // MARK: - Moving

    private func step(_ by: Int) {
        hasMoved = true
        guard let index = cards.firstIndex(where: { $0.id == front }) else { return }
        let next = min(max(0, index + by), cards.count - 1)
        // The keyboard's result is shown at once; a click or tap turns the crate.
        front = cards[next].id
    }

    private func move(to id: String) {
        hasMoved = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { front = id }
    }

    private func open(_ record: CrateRecord) {
        if let route = record.route {
            openRoute(route)
        } else {
            record.play()
        }
    }

    @Environment(\.openPlayRoute) private var openRoute

    // MARK: - Geometry

    static let shadowRoom: CGFloat = 30

    /// A cover's side. A wide Mac window gets bigger records, so the crate still leads the
    /// page on an ultra-wide display rather than sitting small in the middle of it.
    private var side: CGFloat {
        #if os(macOS)
        min(max(Self.side, (width * 0.2).rounded()), 360)
        #else
        Self.side
        #endif
    }

    #if os(macOS)
    static let side: CGFloat = 260
    static let spacing: CGFloat = 20
    static let detailsGap: CGFloat = 18
    #else
    static let side: CGFloat = 232
    static let spacing: CGFloat = 8
    static let detailsGap: CGFloat = 16
    #endif

    /// How far a record is from the front, in records: 0 in front, 1 beside it, and so on.
    nonisolated static func turn(of proxy: GeometryProxy, side: CGFloat, spacing: CGFloat) -> Double {
        let frame = proxy.frame(in: .scrollView(axis: .horizontal))
        let visible = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? frame.width
        return Double((frame.midX - visible / 2) / (side + spacing))
    }

    private func record(for card: ForYouCard) -> CrateRecord {
        CrateRecord(card: card, player: player)
    }
}

private extension VisualEffect {
    /// The records fan out from the one in front, as a hand of records held up: each one
    /// behind the one nearer the front, a little smaller, a little darker, turned a touch
    /// away, and the farther ones drawn in close and soft. Scrolling slides a record out from
    /// behind the others and up to the front. Under Reduce Motion nothing turns or blurs.
    nonisolated func fanned(by distance: Double, side: CGFloat, spacing: CGFloat, reduceMotion: Bool) -> some VisualEffect {
        let a = min(abs(distance), 3.4)
        let sign: Double = distance < 0 ? -1 : 1
        let near = min(a, 1)
        let far = max(0, a - 1)
        // Where the record sits, from the front's centre, as a share of a cover: the first
        // one beside it tucks only its inner edge behind the front, the ones after show a
        // generous slice each, so the crate breathes rather than piles up.
        let reach = near * 0.88 + min(far, 1) * 0.46 + max(0, far - 1) * 0.3
        let shift = sign * reach * side - distance * (side + spacing)
        return self
            .offset(x: shift)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -sign * near * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(1 - 0.14 * near - 0.08 * far)
            .brightness(-0.1 * near - 0.05 * far)
            .blur(radius: reduceMotion ? 0 : far * 1.5)
            .opacity(1 - max(0, a - 2) * 0.9)
    }
}

/// A record in the crate answers the pointer and a press: the front one lifts toward you.
private struct CrateCoverStyle: ButtonStyle {
    let isFront: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isFront && isHovering && !reduceMotion ? 1.02 : 1))
            .animation(PlayMotion.press, value: configuration.isPressed)
            .animation(PlayMotion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

/// Under the crate: why the front record is there, what it's called, and Play.
private struct CrateDetails: View {
    let record: CrateRecord
    @Binding var showsTuner: Bool
    @Environment(PlayerModel.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 6) {
            Text(record.eyebrow)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Text(record.title)
                .font(titleFont)
                .multilineTextAlignment(.center)
            Text(record.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // The reason is why it's here: never cut short at the largest sizes.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button {
                    if record.isPlayingThis { player.togglePlayPause() } else { record.play() }
                } label: {
                    Label(primaryTitle, systemImage: record.isPlayingThis && player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: 96)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!record.canPlay)

                if let shuffle = record.shuffle {
                    Button("Shuffle", systemImage: "shuffle", action: shuffle)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .disabled(!record.canPlay)
                        .help("Shuffle")
                }
                Menu {
                    CrateMenu(record: record, showsTuner: $showsTuner)
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .fixedSize()
                .help("More")
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // Buttons stop growing where they'd crowd each other off the row; their words are
            // already the largest on the page.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.top, 8)
        }
        .padding(.horizontal, PlayMetrics.margin)
        .frame(maxWidth: .infinity)
    }

    private var titleFont: Font {
        #if os(macOS)
        .system(size: 26, weight: .bold)
        #else
        .title2.bold()
        #endif
    }

    private var primaryTitle: LocalizedStringKey {
        guard record.isPlayingThis else { return "Play" }
        return player.isPlaying ? "Pause" : "Resume"
    }
}

/// A record's menu, from its "…" and from a long press or right-click on it.
private struct CrateMenu: View {
    let record: CrateRecord
    @Binding var showsTuner: Bool
    @Environment(\.openPlayRoute) private var openRoute

    var body: some View {
        Button("Play", systemImage: "play") { record.play() }
            .disabled(!record.canPlay)
        if let shuffle = record.shuffle {
            Button("Shuffle", systemImage: "shuffle", action: shuffle)
                .disabled(!record.canPlay)
        }
        if let enqueue = record.enqueue {
            Divider()
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { enqueue(true) }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { enqueue(false) }
        }
        if let route = record.route {
            Divider()
            Button(record.isStation ? "Find More Songs" : "Show Songs", systemImage: "list.bullet") { openRoute(route) }
        }
        if record.isStation {
            Divider()
            Button("Tune Motif Radio", systemImage: "slider.horizontal.3") { showsTuner = true }
        }
    }
}

/// Small dots under the crate, one a record, the front one filled. Each one moves to its record.
private struct PageDots: View {
    let ids: [String]
    let current: String
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                Button {
                    select(id)
                } label: {
                    Circle()
                        .fill(id == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                        .padding(4)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
    }
}

/// The front record's colour, washed across the top of the page behind the large title, and
/// fading into the page before the shelves begin.
private struct CrateGlow: View {
    let color: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    var body: some View {
        let tint = color.map { $0.glowAdapted(to: colorScheme, in: environment) } ?? .clear
        LinearGradient(
            stops: [
                .init(color: tint.opacity(colorScheme == .dark ? 0.5 : 0.32), location: 0),
                .init(color: tint.opacity(colorScheme == .dark ? 0.22 : 0.12), location: 0.55),
                .init(color: tint.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 720)
        .offset(y: -260)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - A record

/// One of the crate's records, however it plays: a mix, Motif Radio or Discover.
struct CrateRecord {
    let card: ForYouCard
    let player: PlayerModel

    var eyebrow: String {
        switch card {
        case .mix(let mix): mix.kind.eyebrow ?? mix.kind.tileLine
        case .station: player.isRadioDriving ? String(localized: "Driving") : String(localized: "Your Station")
        case .discover: String(localized: "New to You")
        }
    }

    var title: String {
        switch card {
        case .mix(let mix): mix.kind.title
        case .station: String(localized: "Motif Radio")
        case .discover: String(localized: "Discover")
        }
    }

    var reason: String {
        switch card {
        case .mix(let mix): mix.kind.reason
        case .station: RadioTuning(stored: UserDefaults.standard.string(forKey: PlayPreferences.radioTuningKey) ?? "").summary
        case .discover: String(localized: "Songs you've never played, by the artists you play most")
        }
    }

    var isStation: Bool {
        if case .station = card { return true }
        return false
    }

    var context: PlayContext {
        switch card {
        case .mix(let mix): PlayContext(kind: .mix, title: mix.kind.title)
        case .station: .motifRadio
        case .discover: PlayContext(kind: .mix, title: String(localized: "Discover"))
        }
    }

    /// Where opening the record goes. Motif Radio has no list to show; it plays.
    var route: PlayRoute? {
        switch card {
        case .mix(let mix): .mix(mix.id)
        case .station: nil
        case .discover: .songFinder(.yourArtists)
        }
    }

    @MainActor var canPlay: Bool {
        switch card {
        case .mix(let mix): !player.songs(in: mix).isEmpty
        case .station: true
        case .discover(let songs): !songs.isEmpty
        }
    }

    @MainActor var isPlayingThis: Bool {
        player.hasQueue && player.context == context
    }

    @MainActor func play() {
        switch card {
        case .mix(let mix): player.play(.history(player.songs(in: mix)), from: context)
        case .station: player.playMotifRadio()
        case .discover(let songs): player.play(.songs(songs), from: context)
        }
    }

    /// Nil for Motif Radio, which picks its own order as it plays.
    @MainActor var shuffle: (() -> Void)? {
        switch card {
        case .mix(let mix): { player.play(.history(player.songs(in: mix)), from: context, shuffled: true) }
        case .station: nil
        case .discover(let songs): { player.play(.songs(songs), from: context, shuffled: true) }
        }
    }

    /// Play Next and Play Last, for what has a list of songs.
    @MainActor var enqueue: ((_ next: Bool) -> Void)? {
        switch card {
        case .mix(let mix):
            { next in player.enqueue(.history(player.songs(in: mix)), next: next, title: mix.kind.title) }
        case .station: nil
        case .discover(let songs):
            { next in player.enqueue(.songs(songs), next: next, title: String(localized: "Discover")) }
        }
    }

    @MainActor @ViewBuilder
    func cover(_ side: CGFloat) -> some View {
        switch card {
        case .mix(let mix):
            MixCover(mix: mix, size: side)
        case .station:
            MotifRadioArt(side: side, isLive: player.isPlayingMotifRadio && player.isPlaying, isDriving: player.isRadioDriving)
        case .discover(let songs):
            MosaicCover(covers: songs.prefix(4).map { $0.artwork.map(CoverArt.artwork) ?? .url(nil, seed: $0.title) }, symbol: "sparkles", size: side)
        }
    }

    /// The colour the page glows with while this record is in front: its cover's own colour,
    /// bright, since nothing is read on it.
    func tint() async -> Color? {
        switch card {
        case .mix(let mix):
            guard let first = mix.covers.first else { return nil }
            return await CoverTint.glow(for: .url(first.url, seed: first.seed))
        case .station:
            return MotifRadioArt.color
        case .discover(let songs):
            guard let artwork = songs.first?.artwork else { return nil }
            return await CoverTint.glow(for: .artwork(artwork))
        }
    }
}

/// Four covers to a square, with a symbol in the corner: a mix's cover made from any songs.
struct MosaicCover: View {
    let covers: [CoverArt]
    let symbol: String
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if covers.count >= 4 {
                let half = size / 2
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        tile(covers[0], half)
                        tile(covers[1], half)
                    }
                    GridRow {
                        tile(covers[2], half)
                        tile(covers[3], half)
                    }
                }
            } else if let first = covers.first {
                tile(first, size)
            } else {
                Color.placeholderFill
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.1, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 0.2, height: size * 0.2)
                .background(.black.opacity(0.45), in: .circle)
                .padding(size * 0.05)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: CoverImage.radius(for: size), style: .continuous))
        .accessibilityHidden(true)
    }

    private func tile(_ cover: CoverArt, _ side: CGFloat) -> some View {
        CoverImage(cover: cover, size: side, isBare: true)
    }
}
