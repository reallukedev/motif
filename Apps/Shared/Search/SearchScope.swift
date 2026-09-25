import SwiftUI

/// Where Search looks: Apple Music's catalog, the Apple Music library, or Motif's history.
enum SearchScope: String, CaseIterable, Identifiable {
    case appleMusic, library, history

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .appleMusic: "Apple Music"
        case .library: "Your Library"
        case .history: "History"
        }
    }

    var prompt: Text {
        switch self {
        case .appleMusic: Text("Artists, Songs, Stations and More")
        case .library: Text("Your Library")
        case .history: Text("Songs, Artists and Albums")
        }
    }

    /// The title where the library is your own music rather than Apple Music's.
    func title(for source: MusicSource) -> LocalizedStringKey {
        self == .library && source == .yourMusic ? "Your Music" : title
    }

    func prompt(for source: MusicSource) -> Text {
        self == .library && source == .yourMusic ? Text("Songs, Albums and Artists") : prompt
    }

    /// The scopes Play offers: Apple Music's catalog isn't one when your own music is what
    /// plays.
    static func scopes(for source: MusicSource) -> [SearchScope] {
        source == .yourMusic ? [.library, .history] : allCases
    }
}

/// Puts the cursor in the window's search field, in the scope given: on the Mac, where search
/// is the sidebar's, for "Search Apple Music" on an empty page and for ⌘F.
struct BeginSearchAction {
    let run: @MainActor (SearchScope?) -> Void

    @MainActor
    func callAsFunction(in scope: SearchScope? = nil) { run(scope) }
}

extension EnvironmentValues {
    @Entry var beginSearch = BeginSearchAction { _ in }
}
