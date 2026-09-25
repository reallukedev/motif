import SwiftUI
import MusicKit
import MotifCore

/// What's known about a song beyond your listening, for the foot of its page, as Music's
/// footer tells you about a record: when it came out, its genre, who wrote it, how long it
/// is, how it's mastered, and the album it's from. Only what's there, never a blank row.
struct SongAbout: Equatable {
    /// The album it's from, opening that album's page.
    struct AlbumLink: Hashable {
        let title: String
        /// "Album · 2024".
        let detail: String
        let artworkURL: String?
        /// A ``CaptureStat/albumIdentity``.
        let id: String
    }

    /// How it's mastered, as Apple Music badges a song.
    enum Quality: Equatable {
        case lossless, hiResLossless, dolbyAtmos

        var label: String {
            switch self {
            case .lossless: String(localized: "Lossless")
            case .hiResLossless: String(localized: "Hi-Res Lossless")
            case .dolbyAtmos: String(localized: "Dolby Atmos")
            }
        }

        var symbol: String {
            switch self {
            case .lossless, .hiResLossless: "waveform"
            case .dolbyAtmos: "hifispeaker.2.fill"
            }
        }
    }

    var album: AlbumLink?
    var note: String?
    var released: Date?
    /// For a song known only by its year: a file's tags, or the history's lookup.
    var year: Int?
    var genre: String?
    var composer: String?
    var length: TimeInterval?
    var qualities: [Quality] = []
    /// A file of your own: its codec and resolution.
    var format: AudioFormat?

    /// Nothing worth a section: no album to open and no fact to state.
    var isEmpty: Bool {
        album == nil && note == nil && released == nil && year == nil && genre == nil
            && composer == nil && length == nil && qualities.isEmpty && format == nil
    }
}

extension SongAbout {
    /// Apple Music's word on a song.
    init(song: Song) {
        note = AboutNote.clean(song.editorialNotes?.standard ?? song.editorialNotes?.short)
        released = song.releaseDate
        genre = SongMetadata.primaryGenre(from: song.genreNames)
        composer = song.composerName.flatMap { $0.isEmpty ? nil : $0 }
        length = song.duration
        qualities = Self.qualities(song.audioVariants ?? [])
    }

    /// A song of yours: what its file's tags or its server say.
    init(track: LocalTrack) {
        year = track.year
        genre = track.genre.flatMap { $0.isEmpty ? nil : $0 }
        length = track.duration
        format = track.format
    }

    /// Hi-Res Lossless in place of Lossless, and Dolby Atmos, in the order Music shows them.
    static func qualities(_ variants: [AudioVariant]) -> [Quality] {
        var qualities: [Quality] = []
        if variants.contains(.highResolutionLossless) {
            qualities.append(.hiResLossless)
        } else if variants.contains(.lossless) {
            qualities.append(.lossless)
        }
        if variants.contains(.dolbyAtmos) {
            qualities.append(.dolbyAtmos)
        }
        return qualities
    }
}

/// Finds what there is to say about a song: from your own music when it's yours, from Apple
/// Music when it's in the catalog and Motif may ask, and from the history's own lookup of
/// its genre and year otherwise. Offline or without access, it says what it already knows.
enum SongAboutLookup {
    @MainActor
    static func about(for profile: SongProfile, model: AppModel) async -> SongAbout? {
        let song = profile.song
        var about: SongAbout
        if let track = model.yourMusic.index.tracks.first(where: { $0.identity == song.id }) {
            about = SongAbout(track: track)
        } else if let found = await catalogSong(id: song.songID, isDemo: model.isDemoLaunch, tally: song) {
            about = SongAbout(song: found)
        } else {
            about = SongAbout()
        }
        about.genre = about.genre ?? profile.metadata?.genre
        if about.released == nil {
            about.year = about.year ?? profile.metadata?.releaseYear
        }
        if let title = song.albumTitle, !title.isEmpty {
            let year = about.released.map { Calendar.current.component(.year, from: $0) } ?? about.year
            about.album = SongAbout.AlbumLink(
                title: title,
                detail: [String(localized: "Album"), year.map(Format.year)].compactMap(\.self).joined(separator: " · "),
                artworkURL: song.artworkURL,
                id: "\(StatsCalculator.folded(title))\u{1F}\(profile.artistID)"
            )
        }
        return about.isEmpty ? nil : about
    }

    /// The song in Apple Music's catalog, with how it's mastered. Nil for a song that isn't
    /// there, or when Motif can't ask.
    @MainActor
    private static func catalogSong(id: String, isDemo: Bool, tally: SongTally) async -> Song? {
        #if DEBUG
        if isDemo { return AboutSamples.song(title: tally.title, artist: tally.artistName, album: tally.albumTitle) }
        #endif
        guard !isDemo, !id.isEmpty, id.allSatisfy(\.isNumber),
              MusicAuthorization.currentStatus == .authorized
        else { return nil }
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        request.properties = [.audioVariants]
        return try? await request.response().items.first
    }
}

/// "About This Song" at the foot of a song's page: the album it's from as a row that opens
/// it, then its facts as rows of a label and its value, and how it's mastered.
struct AboutSongSection: View {
    let about: SongAbout
    let title: String

    /// One part of the card, each only where there's something to show.
    private enum Part: Hashable {
        case album(SongAbout.AlbumLink)
        case note(String)
        case fact(label: String, value: String)
        case qualities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("About This Song")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.element) { index, part in
                        if index > 0 {
                            Divider().padding(.leading, Metrics.cardPadding)
                        }
                        view(for: part)
                    }
                }
            }
        }
    }

    private var parts: [Part] {
        var parts: [Part] = []
        if let album = about.album { parts.append(.album(album)) }
        if let note = about.note { parts.append(.note(note)) }
        if let released = about.released {
            parts.append(.fact(label: String(localized: "Released"), value: released.formatted(date: .long, time: .omitted)))
        } else if let year = about.year {
            parts.append(.fact(label: String(localized: "Year"), value: Format.year(year)))
        }
        if let genre = about.genre {
            parts.append(.fact(label: String(localized: "Genre"), value: genre))
        }
        if let composer = about.composer {
            parts.append(.fact(label: String(localized: "Composer"), value: composer))
        }
        if let length = about.length, length > 0 {
            let pattern: Duration.TimeFormatStyle.Pattern = length >= 3_600 ? .hourMinuteSecond : .minuteSecond
            parts.append(.fact(label: String(localized: "Length"), value: Duration.seconds(length).formatted(.time(pattern: pattern))))
        }
        if !about.qualities.isEmpty || about.format != nil { parts.append(.qualities) }
        return parts
    }

    @ViewBuilder
    private func view(for part: Part) -> some View {
        switch part {
        case .album(let album):
            albumRow(album)
        case .note(let note):
            AboutNote(title: title, text: note)
                .font(.subheadline)
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.vertical, 12)
        case .fact(let label, let value):
            factRow(label, value)
        case .qualities:
            qualityRow
        }
    }

    private func albumRow(_ album: SongAbout.AlbumLink) -> some View {
        NavigationLink(value: Route.album(album.id)) {
            HStack(spacing: 12) {
                ArtworkView(url: album.artworkURL, seed: album.title, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(album.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the album")
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var qualityRow: some View {
        HStack(spacing: 6) {
            if let format = about.format {
                FormatBadge(format: format, showsDetail: true)
            }
            ForEach(about.qualities, id: \.label) { quality in
                AboutQualityBadge(quality: quality)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 12)
    }
}

/// "Lossless", "Dolby Atmos": how a song's mastered, drawn as a song of your own shows its
/// format.
struct AboutQualityBadge: View {
    let quality: SongAbout.Quality

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: quality.symbol)
                .font(.caption2.weight(.bold))
            Text(quality.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.secondary)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
