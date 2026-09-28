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
    /// The record chosen, in front: moved to by a tap or a key, or the one in the middle as
    /// the crate is flipped by hand. Never what the scroll view reports once still, which is
    /// wherever the row has shifted to when songs are dealt in before it.
    @State private var front: String?
    /// Drives the scroll view to the record chosen.
    @State private var position = ScrollPosition(idType: String.self)
    /// While the row changes under the crate and it's being put back on the record chosen, a
    /// shift at rest isn't someone scrolling.
    @State private var isRowChanging = false
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
    @State private var scrollPhase = ScrollPhase.idle
    /// The check that the chosen record is in the middle, once the row settles.
    @State private var settling: Task<Void, Never>?
    /// Where a scroll by hand began, which a flick goes only a few records from.
    @State private var flickStart: Int?
    /// The place in the row passing through the middle of the crate, as it scrolls.
    @State private var centered = 0
    #if os(iOS)
    /// Counts records settling into the middle and pulls past an end, each felt.
    @State private var ticks = 0
    @State private var bumps = 0
    #endif
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
    }

    // MARK: - Dealing songs

    /// Deals songs found since last time, alternately to each side, in a fresh order that keeps
    /// an artist from following themselves; takes out any no longer suggested. Waits while the
    /// crate is moving.
    private func deal() {
        guard !isScrolling else { return }
        let known = Set(songs.map(\.id))
        let removed = (leading + trailing).contains { !known.contains($0.id) }
        // Whatever is dealt in or taken out before the one in front moves the row under it.
        if removed {
            isRowChanging = true
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
        isRowChanging = true
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
        position.scrollTo(id: items[lead + offset].id, anchor: .center)
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
        // Records are counted from the first place in the row, the quiet one at the start
        // included.
        let row = row(items)
        let (firstRecord, places) = (row.hasLeadingEnd ? 1 : 0, row.places)
        // Every record has its place in the row, but only those near the middle are drawn: the
        // songs go on as long as you flip. Not a lazy stack, which draws only what's laid out
        // in view, when the fan pulls records in from well outside it.
        let drawn = Int(depth) + 2
        return ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                if showsLeadingEnd {
                    endRecord(CrateEnd.leading, side: side, spacing: spacing, depth: depth, stillness: stillness, distance: frontIndex + 1)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                    // Near the middle as it scrolls, or near the one chosen, which songs dealt
                    // to the start move along the row a moment before the crate follows it.
                    if abs(index + firstRecord - centered) <= drawn || abs(index - frontIndex) <= drawn {
                        recordView(card, side: side, spacing: spacing, depth: depth, stillness: stillness, distance: index - frontIndex)
                    } else {
                        Color.clear
                            .frame(width: side, height: side)
                            .padding(.vertical, Self.shadowRoom)
                    }
                }
                if showsTrailingEnd {
                    endRecord(CrateEnd.trailing, side: side, spacing: spacing, depth: depth, stillness: stillness, distance: items.count - frontIndex)
                }
            }
            .scrollTargetLayout()
            // Room either side for the first and last records to come to the middle. Inside
            // the row, not as the scroll view's margins, which on the Mac narrow what it
            // answers clicks and scrolls over to the record in front.
            .padding(.horizontal, max(0, (width - side) / 2))
        }
        .scrollPosition($position, anchor: .center)
        .onScrollPhaseChange { old, phase in
            if phase == .interacting { hasMoved = true }
            // Each flick goes a few from where the finger came down, even onto a crate still
            // gliding from the last.
            let touches: [ScrollPhase] = [.tracking, .interacting]
            if touches.contains(phase), !touches.contains(old) { flickStart = centered }
            if phase == .idle { flickStart = nil }
            scrollPhase = phase
            isScrolling = phase != .idle
            // Songs found while it moved are dealt once it's still.
            if phase == .idle { deal() }
        }
        // Where the middle of the crate is, in records: which one is passing through it, and
        // whether it's being pulled past either end.
        .onScrollGeometryChange(for: CrateScroll.self) { geometry in
            CrateScroll(
                position: CratePosition(offset: geometry.contentOffset.x, pitch: side + spacing, places: places),
                rowWidth: geometry.contentSize.width,
                width: geometry.containerSize.width
            )
        } action: { oldScroll, newScroll in
            let (old, new) = (oldScroll.position, newScroll.position)
            centered = new.place
            switch scrollPhase {
            case .idle where isRowChanging:
                // The row changed under it: back to the one chosen, once it's still.
                if new != old { keepChosenInMiddle() }
            case .animating:
                // On its way to the one chosen, already in front.
                break
            case .idle where !newScroll.isSameSize(as: oldScroll):
                // The window resized: the one chosen stays chosen.
                if new != old { keepChosenInMiddle() }
            default:
                // Flipped by hand, or by a mouse's wheel, which has no phases: the one
                // passing through the middle is chosen.
                if new.place != old.place, let id = id(atPlace: new.place) {
                    front = id
                    hasMoved = true
                }
                if scrollPhase == .idle, new != old { keepChosenInMiddle() }
            }
            // A tick as each record settles into the middle, the way a picker's detents are
            // felt, while it's being moved rather than put back in place.
            guard isPlaced, scrollPhase != .idle else { return }
            if new.place != old.place { feel(.detent) }
            if new.isPastEnd, !old.isPastEnd, scrollPhase == .interacting { feel(.end) }
        }
        #if os(iOS)
        .sensoryFeedback(CrateHaptics.detent, trigger: ticks)
        .sensoryFeedback(CrateHaptics.end, trigger: bumps)
        #endif
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
            isRowChanging = true
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { position.scrollTo(id: front, anchor: .center) }
            // The row's room either side comes from the width, known only after the first
            // layout, and a jump before it lands short: once more after this layout.
            Task { @MainActor in
                withTransaction(instant) { position.scrollTo(id: front, anchor: .center) }
                if !isPlaced {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isPlaced = true }
                }
            }
            keepChosenInMiddle()
        }
        .scrollTargetBehavior(CrateSnap(pitch: side + spacing, start: flickStart))
        .scrollIndicators(.hidden)
        .frame(height: side + Self.shadowRoom * 2)
        .opacity(isPlaced ? 1 : 0)
        // The records farthest out fade into the page rather than stopping at its edge.
        .mask { Self.edgeFade }
        .padding(.vertical, -Self.shadowRoom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // To VoiceOver the crate is one control, flipped with a swipe up or down as a picker
        // is: only the records near the middle are drawn, and the one in front is what counts.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("For You")
        .accessibilityValue(frontCard(items).map { record(for: $0).accessibilityTitle } ?? String(localized: "Finding More Songs"))
        .accessibilityHint(frontCard(items).map { record(for: $0).frontHint } ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityAction { openFront(items) }
        #if os(macOS)
        // The keyboard flips through the crate, as the arrows did in Cover Flow.
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        // Return opens the front record, as a click does.
        .onKeyPress(.return) {
            openFront(items)
            return .handled
        }
        .overlay {
            ZStack { if isHovering { hoverArrows(items) } }
                .animation(PlayMotion.hover, value: isHovering)
        }
        .overlay(alignment: .center) {
            // The system's ring goes around the whole crate; this one goes around the record
            // the keys act on. Drawn only for keyboard navigation, as the system draws its
            // own: a click focuses the crate for the arrow keys without ringing it.
            if isFocused, NSApplication.shared.isFullKeyboardAccessEnabled {
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
        let index = items.firstIndex { $0.id == front }
            ?? (front == CrateEnd.leading ? -1 : front == CrateEnd.trailing ? items.count : 0)
        let isAvailable = items.indices.contains(index + step)
        return Button(label, systemImage: systemImage) { self.step(step) }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .help(label)
            .opacity(isAvailable ? 1 : 0)
            .disabled(!isAvailable)
    }
    #endif

    // MARK: - Moving

    private func feel(_ kind: CrateHaptics.Kind) {
        #if os(macOS)
        CrateHaptics.play(kind)
        #else
        switch kind {
        case .detent: ticks += 1
        case .end: bumps += 1
        }
        #endif
    }

    private func step(_ by: Int) {
        hasMoved = true
        let items = items
        guard !items.isEmpty else { return }
        // From the quiet record at an end, back to the nearest real one.
        let index = items.firstIndex { $0.id == front }
            ?? (front == CrateEnd.leading ? -1 : front == CrateEnd.trailing ? items.count : 0)
        let next = min(max(0, index + by), items.count - 1)
        guard next != index else { return }
        // Quick, so a held arrow key riffles through the records as Cover Flow's did.
        choose(items[next].id, animation: .snappy(duration: 0.24))
    }

    private func move(to id: String) {
        hasMoved = true
        choose(id, animation: .smooth(duration: 0.35))
    }

    /// Brings a record to the front, sliding the crate along to it.
    private func choose(_ id: String, animation: Animation) {
        withAnimation(reduceMotion ? nil : animation) {
            front = id
            position.scrollTo(id: id, anchor: .center)
        }
    }

    private func frontCard(_ items: [ForYouCard]) -> ForYouCard? {
        items.first { $0.id == front }
    }

    private func openFront(_ items: [ForYouCard]) {
        if let card = frontCard(items) { open(record(for: card)) }
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

    /// The crate's edges, fading into the page. ``CrateFan/depth(width:side:)`` counts only
    /// the records inside it.
    static let edgeFade = LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.09),
                .init(color: .black, location: 0.91), .init(color: .clear, location: 1)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let shadowRadius: CGFloat = 20
    static let shadowDrop: CGFloat = 12
    /// Room above and below the records for their shadow, inside the scroll view's clip and
    /// the fade's mask. A blur fades out over about twice its radius, and the drop pushes it
    /// that much further down: any less and the shadow stops at a hard line across the page.
    static let shadowRoom: CGFloat = shadowDrop + shadowRadius * 2

    private var side: CGFloat { Self.side(for: width) }

    /// A cover's side. A wide Mac window gets bigger records, so the crate still leads the
    /// page on an ultra-wide display rather than sitting small in the middle of it.
    static func side(for width: CGFloat) -> CGFloat {
        #if os(macOS)
        min(max(side, (width * 0.2).rounded()), 360)
        #else
        side
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

    /// At rest, the record in the middle is the one chosen, whose details show under it. Songs
    /// dealt in quick succession, or the first layouts, can leave a jump landing on a row that
    /// has since grown, a few places short: once the layout has settled, it's checked against
    /// what's really in the middle and put right.
    private func keepChosenInMiddle() {
        settling?.cancel()
        settling = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, scrollPhase == .idle else { return }
            defer { isRowChanging = false }
            guard let front, let chosen = place(of: front), centered != chosen else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { position.scrollTo(id: front, anchor: .center) }
        }
    }

    /// The record at a place in the row, counting the quiet one at the start.
    private func id(atPlace place: Int) -> String? {
        let items = items
        switch row(items).slot(at: place) {
        case .leadingEnd: return CrateEnd.leading
        case .record(let index): return items[index].id
        case .trailingEnd: return CrateEnd.trailing
        case nil: return nil
        }
    }

    /// Where a record is in the row now, counting the quiet one at the start.
    private func place(of id: String) -> Int? {
        let items = items
        let row = row(items)
        switch id {
        case CrateEnd.leading: return row.place(of: .leadingEnd)
        case CrateEnd.trailing: return row.place(of: .trailingEnd)
        default: return items.firstIndex { $0.id == id }.flatMap { row.place(of: .record($0)) }
        }
    }

    private func row(_ items: [ForYouCard]) -> CrateRow {
        CrateRow(records: items.count, hasLeadingEnd: showsLeadingEnd, hasTrailingEnd: showsTrailingEnd)
    }

    /// A record in the row: in front, a click or tap opens or plays it; beside it, brings it
    /// to the front.
    private func recordView(_ card: ForYouCard, side: CGFloat, spacing: CGFloat, depth: Double, stillness: Bool, distance: Int) -> some View {
        let record = record(for: card)
        let isFront = front == card.id
        return Button {
            if isFront { open(record) } else { move(to: card.id) }
        } label: {
            record.cover(side)
                // Flattened first, so the shadow falls from the cover's outline
                // rather than from each of the layers drawn on it.
                .compositingGroup()
                .shadow(color: .black.opacity(0.26), radius: Self.shadowRadius, y: Self.shadowDrop)
        }
        .buttonStyle(CrateCoverStyle(isFront: isFront))
        .frame(width: side, height: side)
        #if os(iOS)
        // Lifted on a long press as the cover itself, square and upright, not the room
        // around it for its shadow.
        .contentShape(.contextMenuPreview, .rect(cornerRadius: CoverImage.radius(for: side), style: .continuous))
        #endif
        .contextMenu { CrateMenu(record: record, showsTuner: $showsTuner) }
        // Room for the shadow, inside the scroll view's clip.
        .padding(.vertical, Self.shadowRoom)
        .visualEffect { content, proxy in
            content.fanned(by: Self.turn(of: proxy, side: side, spacing: spacing), side: side, spacing: spacing, depth: depth, reduceMotion: stillness)
        }
        // The record in front is on top of the stack, and each behind it lower.
        .zIndex(-Double(abs(distance)))
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
    }
}

/// The crate's shape while Play's mixes are made: blank records fanned just as the real ones
/// will be, and the lines under them, so nothing on the page moves when they arrive. Nothing
/// made up on them.
struct CratePlaceholder: View {
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = Crate.side(for: width)
        let (spacing, stillness) = (Crate.spacing, reduceMotion)
        let depth = Int(CrateFan.depth(width: width, side: side))
        let shape = RoundedRectangle(cornerRadius: CoverImage.radius(for: side), style: .continuous)
        VStack(spacing: Crate.detailsGap) {
            ZStack {
                ForEach(-depth...depth, id: \.self) { distance in
                    // On the page's own colour first, so where one tucks behind another the
                    // fills don't add up to a darker band.
                    shape.fill(.background)
                        .overlay { shape.fill(Color.placeholderFill) }
                        .frame(width: side, height: side)
                        .visualEffect { content, _ in
                            content.fanned(by: Double(distance), side: side, spacing: spacing, depth: Double(depth), reduceMotion: stillness, dimming: 0.3)
                        }
                        // Where the row would have laid it, which the fan moves it in from.
                        .offset(x: Double(distance) * (side + spacing))
                        .zIndex(-Double(abs(distance)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: side)
            .mask { Crate.edgeFade }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            VStack(spacing: 6) {
                CrateCaption(eyebrow: "Weekend Morning", title: "Morning Mix", reason: "What you play most on weekend mornings")
                Button {} label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(minWidth: 96)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .hidden()
                .overlay { Capsule().fill(Color.placeholderFill) }
                .padding(.top, 8)
            }
            // Redacted lines are drawn fainter than their colour: as strong as the records.
            .foregroundStyle(.secondary)
            .redacted(reason: .placeholder)
            .padding(.horizontal, PlayMetrics.margin)
            // Where the page dots go.
            Color.clear.frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Crate Loading") {
    ScrollView {
        CratePlaceholder()
    }
}

/// Where the crate is scrolled to, with the sizes that tell a scroll from the row or the
/// window changing under it.
private struct CrateScroll: Equatable {
    let position: CratePosition
    let rowWidth: CGFloat
    let width: CGFloat

    func isSameSize(as other: CrateScroll) -> Bool {
        rowWidth == other.rowWidth && width == other.width
    }
}

/// How the crate comes to rest: with a record in the middle. A flick riffles through a few,
/// each felt as it passes; a slow drag moves them one at a time.
struct CrateSnap: ScrollTargetBehavior {
    /// From one record's place to the next.
    let pitch: CGFloat
    /// The place in the middle when the finger came down, which a flick goes a few from.
    let start: Int?

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // A record asked for by name, to go to the middle: already where it should rest.
        guard target.anchor == nil else { return }
        let last = max(0, context.contentSize.width - context.containerSize.width)
        target.rect.origin.x = CrateRest.offset(for: target.rect.minX, from: start, pitch: pitch, last: last)
    }
}

/// What the crate feels like to flip: a detent as each record settles in the middle, as a
/// picker's wheel has, and a firmer knock against either end. On the Mac they come through
/// a Force Touch trackpad, while fingers are on it.
enum CrateHaptics {
    enum Kind { case detent, end }

    #if os(macOS)
    /// Played in the frame the record reaches the middle, not once the view has updated: the
    /// trackpad is felt only while fingers are on it, and a swipe lifts off moments later.
    @MainActor static func play(_ kind: Kind) {
        NSHapticFeedbackManager.defaultPerformer.perform(kind == .detent ? .alignment : .levelChange, performanceTime: .now)
    }
    #else
    static let detent = SensoryFeedback.selection
    static let end = SensoryFeedback.impact(flexibility: .rigid, intensity: 0.7)
    #endif
}

/// The ids of the quiet records at either end.
enum CrateEnd {
    static let leading = "end.leading"
    static let trailing = "end.trailing"

    static func isEnd(_ id: String) -> Bool { id == leading || id == trailing }
}

private extension VisualEffect {
    /// The records fan out from the one in front, as a hand of records held up: each one
    /// behind the one nearer the front, turned a touch away, and each further out a step
    /// smaller and darker. Scrolling slides a record out from behind the others and up to
    /// the front. Under Reduce Motion nothing turns.
    ///
    /// - Parameter dimming: How much darker each step out gets, from the covers' own 1. Blank
    ///   records, already grey, take a touch: darkened as much, they'd go black in Dark Mode.
    nonisolated func fanned(by distance: Double, side: CGFloat, spacing: CGFloat, depth: Double, reduceMotion: Bool, dimming: Double = 1) -> some VisualEffect {
        let a = min(abs(distance), depth + 1)
        let sign: Double = distance < 0 ? -1 : 1
        let near = min(a, 1)
        let far = max(0, a - 1)
        let shift = sign * CrateFan.reach(a) * side - distance * (side + spacing)
        // Turned and scaled about its own centre first, then moved: moved first, the scale
        // would draw the move in toward where the record is laid out, and the records farther
        // out would land nowhere near where the fan puts them.
        return self
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -sign * near * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(CrateFan.scale(a))
            .brightness(max(-0.4, -0.1 * near - 0.07 * far) * dimming)
            // The last that fits in full; the one past it fading as it comes or goes.
            .opacity(min(1, max(0, depth + 1 - abs(distance))))
            .offset(x: shift)
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
            // A record clicked to the front slides out from under the pointer, which hasn't
            // moved to say so: it comes to the front unlifted, until the pointer is over it.
            .onChange(of: isFront) { isHovering = false }
    }
}

/// Under the crate: why the front record is there, what it's called, and Play.
private struct CrateDetails: View {
    let record: CrateRecord
    @Binding var showsTuner: Bool
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(spacing: 6) {
            CrateCaption(eyebrow: record.eyebrow, title: record.title, reason: record.reason)
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

    private var primaryTitle: LocalizedStringKey {
        guard record.isPlayingThis else { return "Play" }
        return player.isPlaying ? "Pause" : "Resume"
    }
}

/// The words under the crate: why the front record is there, its name, and a line about it.
/// The same height whichever record is in front, so flipping never moves the buttons or the
/// page below: the name on one line, cut short as Music's Now Playing is, and room for two
/// about it. At the largest text sizes nothing is cut short, and the page moves instead.
private struct CrateCaption: View {
    let eyebrow: String
    let title: String
    let reason: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        VStack(spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(isLarge ? nil : 1)
            Text(title)
                .font(Self.titleFont)
                .lineLimit(isLarge ? nil : 1)
            Group {
                if isLarge {
                    Text(reason)
                } else {
                    Text(reason).lineLimit(2, reservesSpace: true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360)
        }
        .multilineTextAlignment(.center)
    }

    private static var titleFont: Font {
        #if os(macOS)
        .system(size: 26, weight: .bold)
        #else
        .title2.bold()
        #endif
    }
}

/// Under the quiet record at an end: the same shape as a record's details, so the page
/// doesn't move, saying what's coming.
private struct CrateEndDetails: View {
    var body: some View {
        VStack(spacing: 6) {
            CrateCaption(
                eyebrow: String(localized: "New to You"),
                title: String(localized: "Finding More Songs"),
                reason: String(localized: "Songs you've never played, like the ones you do")
            )
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
        HStack(spacing: 0) {
            ForEach(ids, id: \.self) { id in
                Button {
                    select(id)
                } label: {
                    Circle()
                        .fill(id == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                        // Easy to hit, where each dot is so small: the gap to the next and a
                        // finger's height, the dots as far apart as ever.
                        .padding(.horizontal, 8)
                        .padding(.vertical, Self.verticalRoom)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        // The dots' room above and below is for fingers, not for the page's rhythm.
        .padding(.vertical, 4 - Self.verticalRoom)
    }

    #if os(macOS)
    private static let verticalRoom: CGFloat = 4
    #else
    private static let verticalRoom: CGFloat = 12
    #endif
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
