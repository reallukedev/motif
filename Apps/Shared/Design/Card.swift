import SwiftUI

/// A rounded panel for Summary content.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CardBackground())
    }
}

struct CardBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        #if os(iOS)
        shape.fill(Color(.secondarySystemGroupedBackground))
        #else
        shape
            .fill(.background.secondary)
            .overlay { shape.strokeBorder(.separator.opacity(0.6), lineWidth: 0.5) }
        #endif
    }
}

/// The background behind a column of cards.
struct GroupedBackground: View {
    var body: some View {
        #if os(iOS)
        Color(.systemGroupedBackground).ignoresSafeArea()
        #else
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #endif
    }
}

/// A section title with an optional trailing link, in the style of Health and Fitness.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Small grey caption above a card's main value, like "LISTENING" in Screen Time.
struct CardLabel: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
    }
}
