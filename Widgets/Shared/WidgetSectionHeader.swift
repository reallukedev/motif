import SwiftUI
import WidgetKit

/// A section's title, with an optional control on the trailing edge.
struct WidgetSectionHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Read by VoiceOver after the title (a count, say) but not drawn.
    var accessibilityValue: Text?
    @ViewBuilder let accessory: Accessory

    /// A column for the symbol, so titles line up when symbols differ in width.
    @ScaledMetric(relativeTo: .caption) private var symbolWidth: CGFloat = 18

    var body: some View {
        // When it doesn't fit, the button drops its label first, then the title its symbol.
        ViewThatFits(in: .horizontal) {
            header(showsSymbol: true, compactAccessory: false)
            header(showsSymbol: true, compactAccessory: true)
            header(showsSymbol: false, compactAccessory: true)
        }
    }

    private func header(showsSymbol: Bool, compactAccessory: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if showsSymbol {
                    Image(systemName: systemImage)
                        .frame(width: symbolWidth)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // Takes the accent on a tinted Home Screen, so headers stand out from the songs.
            .widgetAccentable()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(accessibilityValue ?? Text(verbatim: ""))

            Spacer(minLength: 4)

            if compactAccessory {
                accessory.labelStyle(.iconOnly)
            } else {
                accessory
            }
        }
    }
}

extension WidgetSectionHeader where Accessory == EmptyView {
    init(title: LocalizedStringKey, systemImage: String) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() })
    }
}
