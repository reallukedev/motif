import SwiftUI
import MotifCore

/// Following a ``DeepLink`` inside the app.
///
/// A file of its own because ``DeepLink`` is also compiled into the widget extension, which
/// has no `AppModel` or `Route`.
extension DeepLink {
    /// The page to push, if the link is for one.
    var route: Route? {
        switch self {
        case .summary, .history:
            nil
        case .song(let title, let artistName):
            // A song's page is keyed the way `CaptureStat.songIdentity` groups its plays.
            .song(HistoryImport.key(title: title, artistName: artistName))
        }
    }

    /// Moves the app to where the link points. A song goes through `pendingRoute`, which the
    /// window pushes and clears, the same way the menu bar opens a song.
    func open(in model: AppModel) {
        switch self {
        case .summary:
            #if os(iOS)
            model.selectedTab = .summary
            #else
            model.sidebarSelection = .summary
            #endif
        case .history:
            #if os(iOS)
            model.selectedTab = .history
            #else
            model.sidebarSelection = .history
            #endif
        case .song:
            model.pendingRoute = route
        }
    }
}

extension View {
    /// Follows `motif://` links from the widgets, and on iPhone takes in songs opened in
    /// Motif from Files or the share sheet, into Your Music.
    func opensDeepLinks(in model: AppModel) -> some View {
        onOpenURL { url in
            #if os(iOS)
            if url.isFileURL {
                model.openInYourMusic([url])
                return
            }
            #endif
            DeepLink(url: url)?.open(in: model)
        }
    }
}
