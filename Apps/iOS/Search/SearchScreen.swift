import SwiftUI
import MotifCore

extension View {
    /// Search under the large title, as Music and Settings do, with a toolbar button for
    /// people who don't know to pull down. While it's active, results replace the page.
    ///
    /// - Parameters:
    ///   - scopeKey: where the chosen scope is remembered, per screen.
    ///   - defaultScope: where a first search looks: History on Summary, Apple Music on Play.
    func motifSearch(isPresented: Binding<Bool>, scopeKey: String, defaultScope: SearchScope) -> some View {
        modifier(MotifSearch(isPresented: isPresented, scope: AppStorage(wrappedValue: defaultScope, scopeKey)))
    }
}

private struct MotifSearch: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage var scope: SearchScope
    @State private var query = ""

    init(isPresented: Binding<Bool>, scope: AppStorage<SearchScope>) {
        _isPresented = isPresented
        _scope = scope
    }

    func body(content: Content) -> some View {
        SearchSwap(query: query, scope: scope, search: { query = $0 }) {
            content
        }
        .searchable(
            text: $query,
            isPresented: $isPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: scope.prompt
        )
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        // Keeps the large title where it is while the field opens.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: isPresented) { _, isPresented in
            // Closing search forgets it, so the next search starts clean.
            if !isPresented { query = "" }
        }
    }
}

/// The page, or the results while search is active. Reads `isSearching`, which only a view
/// inside the searchable one can.
private struct SearchSwap<Page: View>: View {
    let query: String
    let scope: SearchScope
    let search: (String) -> Void
    @ViewBuilder var page: Page
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        if isSearching {
            switch scope {
            case .history:
                SearchResultsList(query: query)
            case .appleMusic, .library:
                MusicSearchResults(query: query, scope: scope, search: search)
            }
        } else {
            page
        }
    }
}

/// The button that opens search, for the toolbar.
struct SearchToolbarButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button("Search", systemImage: "magnifyingglass") { isPresented = true }
    }
}
