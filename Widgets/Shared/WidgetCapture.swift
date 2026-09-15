import Foundation
import WidgetKit
import MotifCore

/// One capture, reduced to what a widget can draw.
///
/// Artwork is `Data` because a widget can't load images while rendering; the entry has to
/// arrive complete.
struct WidgetCapture: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let capturedAt: Date
    let artwork: Data?

    init(snapshot: CaptureSnapshot, artwork: Data?) {
        self.id = snapshot.id
        self.title = snapshot.title
        self.artistName = snapshot.artistName
        self.capturedAt = snapshot.capturedAt
        self.artwork = artwork
    }

    init(id: String, title: String, artistName: String, capturedAt: Date, artwork: Data? = nil) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.capturedAt = capturedAt
        self.artwork = artwork
    }
}

/// What the timeline hands to the views.
struct CaptureEntry: TimelineEntry {
    let date: Date
    /// The most recent song kept, from any day. What Last Played shows.
    let lastPlayed: WidgetCapture?
    /// Today's listening, newest first, as many as fit.
    let today: [WidgetCapture]
    /// What "Play back" will play next, or nil when Up Next is off in Settings.
    ///
    /// Empty isn't nil: an empty queue still shows the section, or it would look like the
    /// setting was broken.
    let upNext: UpNextQueue?
    /// Tells "no radio today" apart from "couldn't read the database".
    let isStoreReadable: Bool
}

extension CaptureEntry {
    /// The shape of a real entry, for the system to draw redacted while the real one loads.
    static func placeholder(capacity: WidgetCapacity) -> CaptureEntry {
        let songs = (0..<max(capacity.today, capacity.upNext ?? 0, 1)).map { index in
            WidgetCapture(
                id: "placeholder-\(index)",
                title: "Song Title",
                artistName: "Artist Name",
                capturedAt: .now.addingTimeInterval(Double(index) * -600)
            )
        }
        return CaptureEntry(
            date: .now,
            lastPlayed: songs.first,
            today: Array(songs.prefix(capacity.today)),
            upNext: capacity.upNext.map { UpNextQueue(songs: Array(songs.prefix($0)), totalCount: $0) },
            isStoreReadable: true
        )
    }

    /// A made-up afternoon of listening for the widget gallery and previews, shown instead
    /// of an empty store, as Apple's own widgets do.
    static func sample(capacity: WidgetCapacity) -> CaptureEntry {
        let today = sampleSongs(
            [
                ("Northern Lights", "The Lanterns"),
                ("Paper Planes at Dusk", "Mira Vale"),
                ("Slow Burn", "Harbour Club"),
                ("Tidewater", "June Atlas"),
                ("Glasshouse", "Ocean Avenue"),
                ("Long Way Home", "The Lanterns"),
            ],
            prefix: "sample-today",
            firstHue: 0.02
        )
        let upNext = sampleSongs(
            [
                ("Saltwater Summer", "Coastline"),
                ("Neon Letters", "Mira Vale"),
                ("After the Rain", "Quiet Hours"),
                ("Heliotrope", "June Atlas"),
                ("Low Tide", "Harbour Club"),
            ],
            prefix: "sample-next",
            firstHue: 0.55
        )
        return CaptureEntry(
            date: .now,
            lastPlayed: today.first,
            today: Array(today.prefix(capacity.today)),
            upNext: capacity.upNext.map { UpNextQueue(songs: Array(upNext.prefix($0)), totalCount: upNext.count) },
            isStoreReadable: true
        )
    }

    /// Each song gets its own colour, stepping round the wheel from `firstHue`, so the two
    /// sections look different at a glance.
    private static func sampleSongs(
        _ songs: [(String, String)],
        prefix: String,
        firstHue: Double
    ) -> [WidgetCapture] {
        songs.enumerated().map { index, song in
            WidgetCapture(
                id: "\(prefix)-\(index)",
                title: song.0,
                artistName: song.1,
                capturedAt: .now.addingTimeInterval(Double(index) * -240),
                artwork: SampleArtwork.cover(
                    hue: (firstHue + Double(index) * 0.13).truncatingRemainder(dividingBy: 1)
                )
            )
        }
    }
}
