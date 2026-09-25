import SwiftUI
import MusicKit
import MotifCore

/// One of the records in the crate at the top of Play: the mix for this hour, Motif Radio,
/// Discover, and the mixes for the rest of the day. See ``Crate``.
enum ForYouCard: Identifiable {
    case mix(Mix)
    case station
    case discover([Song])

    var id: String {
        switch self {
        case .mix(let mix): mix.id
        case .station: "station"
        case .discover: "discover"
        }
    }
}
