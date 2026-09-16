import SwiftUI

/// A card's headline figure with the sentence that explains it, like the top of a chart
/// in Health: the takeaway first, the chart after.
struct StatHeadline<Value: View>: View {
    var detail: Text?
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
            if let detail {
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The big number in a ``StatHeadline``.
struct StatValue: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    init(verbatim value: String) {
        self.text = Text(verbatim: value)
    }

    var body: some View {
        text
            .font(Self.font)
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    static let font = Font.system(.title, design: .rounded, weight: .bold)
}
