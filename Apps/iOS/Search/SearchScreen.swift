import SwiftUI
import MotifCore

extension View {
    /// Search under the large title, as Music and Settings do, with a toolbar button for
    /// people who don't know to pull down. While it's active, results replace the page.
    ///
    /// - Parameters:
    ///   - scopeKey: where the chosen scope is remembered, per screen.
    ///   - defaultScope: where a first search looks: History on Summary, Apple Music on Play.
    ///   - source: whose library "Your Library" searches, and so which scopes there are.
    func motifSearch(isPresented: Binding<Bool>, scopeKey: String, defaultScope: SearchScope, source: MusicSource = .appleMusic) -> some View {
        modifier(MotifSearch(isPresented: isPresented, scope: AppStorage(wrappedValue: defaultScope, scopeKey), source: source))
    }
}

private struct MotifSearch: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage var scope: SearchScope
    let source: MusicSource
    @State private var query = ""
    #if DEBUG
    @State private var typesLaunchText = true
    @FocusState private var isFieldFocused: Bool
    #endif

    init(isPresented: Binding<Bool>, scope: AppStorage<SearchScope>, source: MusicSource) {
        _isPresented = isPresented
        _scope = scope
        self.source = source
    }

    func body(content: Content) -> some View {
        let scopes = SearchScope.scopes(for: source)
        SearchSwap(query: query, scope: scope, source: source, search: { query = $0 }) {
            content
        }
        .searchable(
            text: $query,
            isPresented: $isPresented,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: scope.prompt(for: source)
        )
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(scopes) { scope in
                Text(scope.title(for: source)).tag(scope)
            }
        }
        #if DEBUG
        // `-MotifSearchText`, for screenshots of results.
        .task {
            guard typesLaunchText, let text = LaunchScene.searchText, isPresented else { return }
            typesLaunchText = false
            try? await Task.sleep(for: .milliseconds(600))
            query = text
            // Out of the way of the results, as after scrolling them.
            try? await Task.sleep(for: .milliseconds(300))
            isFieldFocused = false
        }
        .searchFocused($isFieldFocused)
        #endif
        // Keeps the large title where it is while the field opens.
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        // A scope remembered from the other source falls back to the first this one has.
        .onAppear { keepScope(in: scopes) }
        .onChange(of: source) { keepScope(in: SearchScope.scopes(for: source)) }
        .onChange(of: isPresented) { _, isPresented in
            // Closing search forgets it, so the next search starts clean.
            if !isPresented { query = "" }
        }
    }
}

private extension MotifSearch {
    func keepScope(in scopes: [SearchScope]) {
        if !scopes.contains(scope) { scope = scopes[0] }
    }
}

/// The page, or the results while search is active. Reads `isSearching`, which only a view
/// inside the searchable one can.
private struct SearchSwap<Page: View>: View {
    let query: String
    let scope: SearchScope
    let source: MusicSource
    let search: (String) -> Void
    @ViewBuilder var page: Page
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        if isSearching {
            switch scope {
            case .history:
                SearchResultsList(query: query)
            case .library where source == .yourMusic:
                YourMusicSearchResults(query: query, search: search)
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
