import SwiftUI

/// Cards side by side when there's room for each to be at least `minimumWidth`, otherwise
/// stacked, and always stacked at accessibility text sizes. Side by side, every card is as
/// tall as the tallest, so a row never ends raggedly.
///
/// Each card reports `minimumWidth` as its ideal width, so the choice depends on the space
/// rather than on how long a line of text in the card happens to be.
struct CardPair<Content: View>: View {
    var minimumWidth: CGFloat = 320
    var spacing: CGFloat = Metrics.cardSpacing
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(subviews: content) { card in
                        card.frame(minWidth: minimumWidth, idealWidth: minimumWidth, maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(spacing: spacing) {
            content
        }
    }
}
