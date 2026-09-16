import SwiftUI

/// A small labelled figure along the bottom of a card, like "Daily Average".
struct StatFootnote: View {
    let title: LocalizedStringKey
    let value: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            value
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}
