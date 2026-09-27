import SwiftUI
import MusicKit
import MotifCore

/// The crate at the top of Play: this hour's mix, Motif Radio, Discover and the rest of the
/// day's mixes, flipped through like records, as Cover Flow flipped through albums. The one in
/// front says why it's there and plays in one tap; the page behind glows in its colour.
///
/// Past the mixes, either way, it goes on with songs suggested for you, for as long as you
/// flip: nearing either end looks for more, and a quiet record holds the end while they come.
/// Each song is dealt to one side for good, as it's found, so nothing already in the crate
/// ever moves.
struct Crate: View {
    let cards: [ForYouCard]
    /// The card to start in front of: Motif Radio, with this hour's mix beside it.
    let leadID: String?
    /// Suggested songs, in the order they were found.
    var songs: [CrateSong] = []
    /// Whether more songs can come, past the last.
    var songsGoOn = false
    /// Changes each time looking for more has had its answer, even an empty one, so nearing
    /// an end asks again only after that.
    var songsGeneration = 0
    /// Looks for more songs, as an end nears.
    var loadMoreSongs: (() async -> Void)?

    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var model
    @Environment(YourMusic.self) private var music
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var front: String?
    /// Whether the crate's been flipped by hand, after which it stays where it was put.
    @State private var hasMoved = false
    @State private var width: CGFloat = 0
    @State private var glow: Color?
    @State private var showsTuner = LaunchScene.opensRadioTuner
    /// The songs dealt to each side, nearest the mixes first.
    @State private var leading: [CrateSong] = []
    @State private var trailing: [CrateSong] = []
    /// While a finger or a fling is moving the crate, songs found wait to be dealt, so the
    /// records never shift under it.
    @State private var isScrolling = false
    /// False until the records have been scrolled to the one in front the first time: lazy
    /// records are laid out a moment after the crate is, and until then it would show the
    /// first of them, then jump.
    @State private var isPlaced = false
    @FocusState private var isFocused: Bool
    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// Every record in order: the leading songs, the mixes, the trailing songs.
    private var items: [ForYouCard] {
        leading.reversed().map(ForYouCard.song) + cards + trailing.map(ForYouCard.song)
    }

    private var showsLeadingEnd: Bool { songsGoOn && !leading.isEmpty }
    private var showsTrailingEnd: Bool { songsGoOn && !trailing.isEmpty }

    var body: some View {
        let items = items
        let current = items.first { $0.id == front } ?? (front.map(CrateEnd.isEnd) == true ? nil : cards.first)
        VStack(spacing: Self.detailsGap) {
            flow(items)
            Group {
                if let current {
                    CrateDetails(record: record(for: current), showsTuner: $showsTuner)
                        .id(current.id)
                } else {
                    CrateEndDetails()
                }
            }
            .transition(.opacity)
            if cards.count > 1 || !items.isEmpty && items.count > cards.count {
                // The mixes, one dot each: from among the songs none is filled, and a dot
                // brings you back.
                PageDots(ids: cards.map(\.id), current: front) { id in move(to: id) }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: front)
        .background(alignment: .top) {
            CrateGlow(color: glow)
        }
        .task(id: current?.id) {
            guard let current else { return }
            let found = await record(for: current).tint()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { glow = found }
        }
        .task(id: loadKey(items)) {
            guard nearsEnd(items), songsGoOn, let loadMoreSongs else { return }
            await loadMoreSongs()
        }
        .onAppear {
            if front == nil { front = leadID ?? cards.first?.id }
            deal()
        }
        .onChange(of: songs.map(\.id)) { deal() }
        .sheet(isPresented: $showsTuner) { RadioTunerSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("For You")
    }

    // MARK: - Dealing songs

    /// Deals songs found since last time, alternately to each side, in a fresh order that keeps
    /// an artist from following themselves; takes out any no longer suggested. Waits while the
    /// crate is moving.
    private func deal() {
        guard !isScrolling else { return }
        let known = Set(songs.map(\.id))
        let removed = (leading + trailing).contains { !known.contains($0.id) }
        if removed {
            let items = items
            let index = items.firstIndex { $0.id == front }
            leading.removeAll { !known.contains($0.id) }
            trailing.removeAll { !known.contains($0.id) }
            // The one in front taken out: the next one out from the mixes takes its place.
            if let index, let front, !known.contains(front), front.hasPrefix("song.") || front.hasPrefix("local.") {
                let remaining = self.items
                let fallback = index < items.count / 2 ? min(index, remaining.count - 1) : max(0, min(index - 1, remaining.count - 1))
                self.front = remaining.indices.contains(fallback) ? remaining[fallback].id : leadID
            }
        }
        defer { startWhereLaunchAsks() }
        let dealt = Set((leading + trailing).map(\.id))
        let fresh = songs.filter { !dealt.contains($0.id) }
        guard !fresh.isEmpty else { return }
        let order = FreshShuffle.order(
            fresh,
            artist: { StatsCalculator.folded($0.artistName) },
            seed: FreshShuffle.dailySeed(for: .now, salt: "crate.\(dealt.count)")
        )
        var (leading, trailing) = (self.leading, self.trailing)
        for song in order {
            // The trailing side first, as the eye reads on to the right.
            if trailing.count <= leading.count { trailing.append(song) } else { leading.append(song) }
        }
        self.leading = leading
        self.trailing = trailing
    }

    /// `-MotifCrate`, for screenshots: once there are records that far from the lead.
    private func startWhereLaunchAsks() {
        #if DEBUG
        guard let offset = LaunchScene.crateOffset, !hasMoved else { return }
        let items = items
        let lead = items.firstIndex { $0.id == (leadID ?? cards.first?.id) } ?? 0
        guard items.indices.contains(lead + offset) else { return }
        hasMoved = true
        front = items[lead + offset].id
        #endif
    }

    /// Within a few records of either end, so the next songs are ready before they're reached.
    private func nearsEnd(_ items: [ForYouCard]) -> Bool {
        guard !songs.isEmpty || songsGoOn else { return false }
        if let front, CrateEnd.isEnd(front) { return true }
        guard let index = items.firstIndex(where: { $0.id == front }) else { return false }
        // Past what shows either side, so the ends are never in view before more come.
        let ahead = Int(CrateFan.depth(width: width, side: side)) + Self.lookAhead
        return index < ahead || items.count - 1 - index < ahead
    }

    private func loadKey(_ items: [ForYouCard]) -> String {
        "\(nearsEnd(items))|\(songs.count)|\(songsGeneration)|\(songsGoOn)"
    }

    /// Records past the last in view at which more are looked for.
    private static let lookAhead = 4

    // MARK: - The flow

    private func flow(_ items: [ForYouCard]) -> some View {
        // Taken out for the fan, which is worked out off the main actor as the crate scrolls.
        let (side, spacing, stillness) = (self.side, Self.spacing, reduceMotion)
        let depth = CrateFan.depth(width: width, side: side)
        let frontIndex = items.firstIndex { $0.id == front }
            ?? (front == CrateEnd.leading ? -1 : front == CrateEnd.trailing ? items.count : 0)
        return ScrollViewReader { proxy in ScrollView(.horizontal) {
            // Lazy, since the songs go on as long as you flip.
            LazyHStack(spacing: Self.spacing) {
                if showsLeadingEnd {
                    endRecord(CrateEnd.leading, side: side, spacing: spacing, depth: depth, stillness: stillness, distance: frontIndex + 1)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                    let record = record(for: card)
                    Button {
                        if front == card.id { open(record) } else { move(to: card.id) }
                    } label: {
                        record.cover(side)
                            // Flattened first, so the shadow falls from the cover's outline
                            // rather than from each of the layers drawn on it.
                            .compositingGroup()
                            .shadow(color: .black.opacity(0.26), radius: Self.shadowRadius, y: Self.shadowDrop)
                    }
                    .buttonStyle(CrateCoverStyle(isFront: front == card.id))
                    .frame(width: side, height: side)
                    // Room for the shadow, inside the scroll view's clip.
                    .padding(.vertical, Self.shadowRoom)
                    .visualEffect { content, proxy in
                        content.fanned(by: Self.turn(of: proxy, side: side, spacing: spacing), side: side, spacing: spacing, depth: depth, reduceMotion: stillness)
                    }
                    // The record in front is on top of the stack, and each behind it lower.
                    .zIndex(-Double(abs(index - frontIndex)))
                    .accessibilityLabel(record.accessibilityTitle)
                    .accessibilityHint(front == card.id ? record.frontHint : String(localized: "Brings it to the front"))
                    .contextMenu { CrateMenu(record: record, showsTuner: $showsTuner) }
                }
                if showsTrailingEnd {
                    endRecord(CrateEnd.trailing, side: side, spacing: spacing, depth: depth, stillness: stillness, distance: items.count - frontIndex)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $front, anchor: .center)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { hasMoved = true }
            isScrolling = phase != .idle
            // Songs found while it moved are dealt once it's still.
            if phase == .idle { deal() }
        }
        // What's in front has to be the record chosen. The cards can change under it, as the
        // history arrives and Motif Radio joins them in the middle, songs are dealt to either
        // side, and the page's width is only known after the first layout, which moves the
        // middle: each time, back to the one chosen, or to the lead until someone has moved
        // it themselves.
        .onChange(of: "\(items.map(\.id).joined(separator: ","))|\(showsLeadingEnd)|\(leadID ?? "")|\(Int(width))", initial: true) {
            if !hasMoved || !(items.contains { $0.id == front } || front.map(CrateEnd.isEnd) == true) {
                front = leadID ?? cards.first?.id
            }
            guard let front else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(front, anchor: .center) }
            // Lazy records aren't laid out yet on the first pass, and a jump to one that isn't
            // lands short: once more after this layout, when they are.
            Task { @MainActor in
                withTransaction(instant) { proxy.scrollTo(front, anchor: .center) }
                if !isPlaced {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isPlaced = true }
                }
            }
        }
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .contentMargins(.horizontal, max(0, (width - side) / 2), for: .scrollContent)
        .scrollIndicators(.hidden)
        .frame(height: side + Self.shadowRoom * 2)
        .opacity(isPlaced ? 1 : 0)
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
            if let card = items.first(where: { $0.id == front }) { open(record(for: card)) }
            return .handled
        }
        .overlay { if isHovering { hoverArrows(items) } }
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
    private func hoverArrows(_ items: [ForYouCard]) -> some View {
        HStack {
            arrow(-1, systemImage: "chevron.backward", label: "Previous", items: items)
            Spacer()
            arrow(1, systemImage: "chevron.forward", label: "Next", items: items)
        }
        .padding(.horizontal, 20)
        .transition(.opacity)
    }

    private func arrow(_ step: Int, systemImage: String, label: LocalizedStringKey, items: [ForYouCard]) -> some View {
        let index = items.firstIndex { $0.id == front } ?? 0
        let isAvailable = items.indices.contains(index + step)
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
        let items = items
        guard let index = items.firstIndex(where: { $0.id == front }) else { return }
        let next = min(max(0, index + by), items.count - 1)
        // The keyboard's result is shown at once; a click or tap turns the crate.
        front = items[next].id
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

    static let shadowRadius: CGFloat = 20
    static let shadowDrop: CGFloat = 12
    /// Room above and below the records for their shadow, inside the scroll view's clip and
    /// the fade's mask. A blur fades out over about twice its radius, and the drop pushes it
    /// that much further down: any less and the shadow stops at a hard line across the page.
    static let shadowRoom: CGFloat = shadowDrop + shadowRadius * 2

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
        CrateRecord(card: card, player: player, music: music, source: model.musicSource, following: following(card))
    }

    /// A song and the ones after it on its side, out from the mixes: what plays from it.
    private func following(_ card: ForYouCard) -> [CrateSong] {
        guard case .song(let song) = card else { return [] }
        if let index = trailing.firstIndex(of: song) { return Array(trailing[index...]) }
        if let index = leading.firstIndex(of: song) { return Array(leading[index...]) }
        return [song]
    }

    /// The quiet record at an end while more songs are looked for: the shape of a cover,
    /// and nothing made up on it.
    private func endRecord(_ id: String, side: CGFloat, spacing: CGFloat, depth: Double, stillness: Bool, distance: Int) -> some View {
        RoundedRectangle(cornerRadius: CoverImage.radius(for: side), style: .continuous)
            .fill(Color.placeholderFill)
            .overlay { ProgressView().controlSize(.large) }
            .frame(width: side, height: side)
            .padding(.vertical, Self.shadowRoom)
            .visualEffect { content, proxy in
                content.fanned(by: Self.turn(of: proxy, side: side, spacing: spacing), side: side, spacing: spacing, depth: depth, reduceMotion: stillness)
            }
            .zIndex(-Double(abs(distance)))
            .id(id)
            .accessibilityLabel("Finding More Songs")
    }
}

/// The ids of the quiet records at either end.
enum CrateEnd {
    static let leading = "end.leading"
    static let trailing = "end.trailing"

    static func isEnd(_ id: String) -> Bool { id == leading || id == trailing }
}

/// Where each record sits, as Cover Flow laid out its albums: the one in front, the first
/// either side tucked just behind it, and each one after that the same step further out, a
/// little smaller and darker, crisp all the way. As many as fit the width show; the next one
/// out fades as it comes or goes, so there's never a record half there at rest.
enum CrateFan {
    /// How far a record sits from the front's centre, in covers, `a` records out.
    nonisolated static func reach(_ a: Double) -> Double {
        min(a, 1) * 0.86 + max(0, a - 1) * step
    }

    nonisolated static func scale(_ a: Double) -> Double {
        max(0.5, 1 - 0.14 * min(a, 1) - 0.07 * max(0, a - 1))
    }

    /// Each record past the first beside the front, in covers.
    nonisolated static let step = 0.34

    /// How many records a side fit in this width, the front's included in none: at least one,
    /// the one beside the front, which may run under the edge's fade.
    nonisolated static func depth(width: CGFloat, side: CGFloat) -> Double {
        // Inside the fade at either edge.
        let room = Double(width) / 2 * 0.91
        var count = 1
        while count < 12 {
            let next = Double(count + 1)
            guard (reach(next) + scale(next) / 2) * Double(side) <= room else { break }
            count += 1
        }
        return Double(count)
    }
}

private extension VisualEffect {
    /// The records fan out from the one in front, as a hand of records held up: each one
    /// behind the one nearer the front, turned a touch away, and each further out a step
    /// smaller and darker. Scrolling slides a record out from behind the others and up to
    /// the front. Under Reduce Motion nothing turns.
    nonisolated func fanned(by distance: Double, side: CGFloat, spacing: CGFloat, depth: Double, reduceMotion: Bool) -> some VisualEffect {
        let a = min(abs(distance), depth + 1)
        let sign: Double = distance < 0 ? -1 : 1
        let near = min(a, 1)
        let far = max(0, a - 1)
        let shift = sign * CrateFan.reach(a) * side - distance * (side + spacing)
        return self
            .offset(x: shift)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -sign * near * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(CrateFan.scale(a))
            .brightness(max(-0.4, -0.1 * near - 0.07 * far))
            // The last that fits in full; the one past it fading as it comes or goes.
            .opacity(min(1, max(0, depth + 1 - abs(distance))))
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
                // A song's name can run long; a mix's never does.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
                if let song = record.favoriteSong {
                    CrateFavoriteButton(song: song)
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

/// Under the quiet record at an end: the same shape as a record's details, so the page
/// doesn't move, saying what's coming.
private struct CrateEndDetails: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("New to You")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Text("Finding More Songs")
                .font(.title2.bold())
            Text("Songs you've never played, like the ones you do")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {} label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.top, 8)
        }
        .padding(.horizontal, PlayMetrics.margin)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Music's star, beside a suggested song's Play: favorites it in Apple Music, which keeps it
/// in the library too.
private struct CrateFavoriteButton: View {
    let song: Song
    @Environment(PlayerModel.self) private var player
    /// Counts stars given here, so the tap is felt but a lookup finding one isn't.
    @State private var starred = 0

    var body: some View {
        let isFavorite = player.isFavorite(song)
        Button(isFavorite ? "Undo Favorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star") {
            if !isFavorite { starred += 1 }
            player.setFavorite(song, !isFavorite)
        }
        .labelStyle(.iconOnly)
        .contentTransition(.symbolEffect(.replace))
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .sensoryFeedback(.success, trigger: starred)
        .help(isFavorite ? "Undo Favorite" : "Favorite")
        .task(id: song.id) { player.lookUpFavorite(song) }
    }
}

/// A record's menu, from its "…" and from a long press or right-click on it.
private struct CrateMenu: View {
    let record: CrateRecord
    @Binding var showsTuner: Bool
    @Environment(\.openPlayRoute) private var openRoute

    var body: some View {
        if case .song(let song) = record.card {
            songMenu(song)
        } else {
            recordMenu
        }
    }

    /// A suggested song's own menu, as it has everywhere else: Play first.
    @ViewBuilder
    private func songMenu(_ song: CrateSong) -> some View {
        Button("Play", systemImage: "play") { record.play() }
        Divider()
        switch song.kind {
        case .catalog(let suggestion): SuggestionMenu(suggestion: suggestion)
        case .local(let track): LocalTrackMenu(track: track)
        }
    }

    @ViewBuilder
    private var recordMenu: some View {
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
    /// The record in front, which may be a song, with no dot.
    let current: String?
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

/// One of the crate's records, however it plays: a mix, Motif Radio, Discover or a song.
struct CrateRecord {
    let card: ForYouCard
    let player: PlayerModel
    let music: YourMusic
    let source: MusicSource
    /// For a song, it and the ones after it on its side, which play from it.
    var following: [CrateSong] = []

    var eyebrow: String {
        switch card {
        case .mix(let mix): mix.kind.eyebrow ?? mix.kind.tileLine
        case .station: player.isRadioDriving ? String(localized: "Driving") : String(localized: "Your Station")
        case .discover: String(localized: "New to You")
        case .song(let song): song.reason
        }
    }

    var title: String {
        switch card {
        case .mix(let mix): mix.kind.title
        case .station: String(localized: "Motif Radio")
        case .discover: String(localized: "Discover")
        case .song(let song): song.title
        }
    }

    var reason: String {
        switch card {
        case .mix(let mix): mix.kind.reason
        case .station: RadioTuning(stored: UserDefaults.standard.string(forKey: PlayPreferences.radioTuningKey) ?? "").summary
        case .discover: String(localized: "Songs you've never played, by the artists you play most")
        case .song(let song): song.artistName
        }
    }

    /// What VoiceOver says for the cover: a song's name with its artist's.
    var accessibilityTitle: String {
        if case .song(let song) = card { return "\(song.title), \(song.artistName)" }
        return title
    }

    /// What tapping the record in front does.
    var frontHint: String {
        route == nil ? String(localized: "Plays it") : String(localized: "Opens it")
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
        case .song: .songs(String(localized: "Suggested Songs"))
        }
    }

    /// Where opening the record goes. Motif Radio has no list to show, and a song is itself:
    /// they play.
    var route: PlayRoute? {
        switch card {
        case .mix(let mix): .mix(mix.id)
        case .station, .song: nil
        case .discover: .songFinder(.yourArtists)
        }
    }

    /// Music's star, for a song from Apple Music played through it.
    var favoriteSong: Song? {
        guard source == .appleMusic, !player.isDemo, case .song(let song) = card, case .catalog(let suggestion) = song.kind else { return nil }
        return suggestion.song
    }

    @MainActor var canPlay: Bool {
        switch card {
        case .mix(let mix): !player.songs(in: mix).isEmpty
        case .station, .song: true
        case .discover(let songs): !songs.isEmpty
        }
    }

    @MainActor var isPlayingThis: Bool {
        if case .song(let song) = card { return player.current?.songIdentity == song.identity }
        return player.hasQueue && player.context == context && !player.isOnAutoplayPick
    }

    @MainActor func play() {
        switch card {
        case .mix(let mix): player.play(.history(player.songs(in: mix)), from: context)
        case .station: player.playMotifRadio()
        case .discover(let songs): player.play(.songs(songs), from: context)
        case .song(let song): playSongs(from: song)
        }
    }

    /// The song, then the rest out along its side. Suggestions from Apple Music with your own
    /// music play once they're found there, or say why they can't.
    @MainActor private func playSongs(from song: CrateSong) {
        let queue = following.isEmpty ? [song] : following
        switch song.kind {
        case .catalog(let suggestion):
            let songs = queue.compactMap { if case .catalog(let other) = $0.kind { other.song } else { nil } }
            let (player, music, source, context) = (player, music, source, context)
            // The pretend player plays sample songs by name; nothing may reach Apple Music.
            if player.isDemo {
                player.play(.history(songs.map { HistorySong(MixSong(catalog: $0)) }), from: context)
                return
            }
            Task {
                await SuggestionPlayback.play(suggestion.song, source: source, music: music, player: player) {
                    player.play(.songs(songs), from: context)
                }
            }
        case .local:
            let tracks = queue.compactMap { if case .local(let track) = $0.kind { track } else { nil } }
            player.play(.local(tracks), from: context)
        }
    }

    /// Nil for Motif Radio, which picks its own order as it plays, and for a song.
    @MainActor var shuffle: (() -> Void)? {
        switch card {
        case .mix(let mix): { player.play(.history(player.songs(in: mix)), from: context, shuffled: true) }
        case .station, .song: nil
        case .discover(let songs): { player.play(.songs(songs), from: context, shuffled: true) }
        }
    }

    /// Play Next and Play Last, for what has a list of songs. A song's own menu has its own.
    @MainActor var enqueue: ((_ next: Bool) -> Void)? {
        switch card {
        case .mix(let mix):
            { next in player.enqueue(.history(player.songs(in: mix)), next: next, title: mix.kind.title) }
        case .station, .song: nil
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
        case .song(let song):
            CoverImage(cover: song.cover, size: side)
                .overlay {
                    if isPlayingThis { NowPlayingMark(side: side, isPlaying: player.isPlaying) }
                }
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
        case .song(let song):
            return await CoverTint.glow(for: song.cover)
        }
    }
}

/// On a song's cover in the crate while it plays: Music's waveform in the corner.
private struct NowPlayingMark: View {
    let side: CGFloat
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: side * 0.08, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying && !reduceMotion)
            .frame(width: side * 0.18, height: side * 0.18)
            .background(.black.opacity(0.45), in: .circle)
            .padding(side * 0.05)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .accessibilityHidden(true)
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
