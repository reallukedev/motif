import SwiftUI
import MotifCore

/// What you searched for lately, kept as lines in one stored string, newest first.
enum RecentSearches {
    static func list(_ storage: String) -> [String] {
        storage.split(separator: "\n").map(String.init)
    }

    /// The storage with a search added at the front, eight at most, each once.
    static func adding(_ query: String, to storage: String) -> String {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return storage }
        let kept = [term] + list(storage).filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        return kept.prefix(8).joined(separator: "\n")
    }
}

/// Recent searches as chips to search again, with Clear.
struct RecentSearchesSection: View {
    let recents: [String]
    let clear: () -> Void
    let search: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SearchSectionTitle("Recently Searched")
                Spacer()
                Button("Clear") { withAnimation(.snappy) { clear() } }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, PlayMetrics.margin)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(recents, id: \.self) { recent in
                        Button {
                            search(recent)
                        } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(.quaternary, in: .capsule)
                                // A full-height target around the chip.
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .contentMargins(.horizontal, PlayMetrics.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

/// The moods, as tiles to open, for before a search.
struct BrowseByMoodSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchSectionTitle("Browse by Mood")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tile), spacing: 12)], spacing: 12) {
                ForEach(Mood.allCases) { mood in
                    MoodTile(mood: mood, height: 84, fillsWidth: true)
                }
            }
        }
        .padding(.horizontal, PlayMetrics.margin)
    }

    #if os(macOS)
    private static let tile: CGFloat = 170
    #else
    private static let tile: CGFloat = 150
    #endif
}

/// A search section's title.
struct SearchSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

/// Search's songs, in rows: one column on iPhone, two on the Mac, as Music lays them out.
struct SearchSongGrid<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                row(item)
            }
        }
    }

    #if os(macOS)
    private static var columns: [GridItem] { [GridItem(.flexible(), spacing: 28), GridItem(.flexible())] }
    #else
    private static var columns: [GridItem] { [GridItem(.flexible())] }
    #endif
}

/// The best match for a search, whatever it's from: what it's called, what it is, its
/// picture, and what opening and playing it do.
struct SearchTopResult {
    let title: String
    /// "Artist", "Album · Mara Solis", "Song · Mara Solis".
    let kind: String
    let cover: CoverArt?
    /// For an artist: a round picture, or their initials without one.
    var isArtist = false
    let open: () -> Void
    /// Nil when nothing of it can play right now.
    let play: (() -> Void)?
}

/// The best match, large: its picture, what it is, and Play, as Music's Top Result is.
struct TopResultCard: View {
    let result: SearchTopResult
    @State private var tint: Color?

    var body: some View {
        Button(action: result.open) {
            VStack(alignment: .leading, spacing: 14) {
                picture
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(result.kind)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                // Clear of Play in the corner, however large the text.
                .padding(.trailing, 60)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 64)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background {
                CoverStage(tint: tint, deepens: true)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
            }
            .overlay(alignment: .bottomTrailing) {
                if let play = result.play {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(.white, in: .circle)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.pressable)
                .padding(16)
                // Reached as the card's Play action with VoiceOver.
                .accessibilityHidden(true)
                }
            }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.pressable)
        .coverTint(of: result.cover ?? .url(nil, seed: result.title), into: $tint)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Play") { result.play?() }
    }

    @ViewBuilder
    private var picture: some View {
        if result.isArtist {
            ArtistPicture(cover: result.cover, name: result.title, size: 112, onStage: true)
        } else {
            CoverImage(cover: result.cover ?? .url(nil, seed: result.title), size: 112)
        }
    }
}
