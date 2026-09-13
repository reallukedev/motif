import SwiftUI
import MotifCore

/// Places a navigation stack can push.
enum Route: Hashable {
    case artist(String)
    case song(String)
    case highlights(StatsRange)
    case chart(ChartKind)
}

enum ChartKind: String, CaseIterable, Identifiable, Hashable {
    case songs, artists, albums

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .songs: "Songs"
        case .artists: "Artists"
        case .albums: "Albums"
        }
    }

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .songs: "Top Songs"
        case .artists: "Top Artists"
        case .albums: "Top Albums"
        }
    }
}

extension View {
    /// The destinations every stack in the app understands.
    func motifDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .artist(let id): ArtistDetailView(artistID: id)
            case .song(let id): SongDetailView(songID: id)
            case .highlights(let range): HighlightsList(range: range)
            case .chart(let kind): TopChartView(kind: kind)
            }
        }
    }
}
