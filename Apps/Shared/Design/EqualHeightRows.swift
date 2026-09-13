import SwiftUI

/// Lays items out in rows of `columns`, with every card in a row as tall as the tallest.
/// `LazyVGrid` sizes each cell to its own content, which leaves ragged rows of cards.
struct EqualHeightRows<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    var spacing: CGFloat = 12
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[index]) { item in
                        content(item)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    // Keep a short last row's cards the same width as the rest.
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: max(1, columns)).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }
}
