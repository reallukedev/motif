import SwiftUI
import MotifCore

struct SearchScreen: View {
    @State private var query = ""

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Songs, Artists and Albums")
    }
}
