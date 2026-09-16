import SwiftUI

/// As many whole songs as fit, never a row cut in half.
///
/// How much fits depends on the device, widget size and text size (at the largest text a
/// medium widget fits one row, not three), so this tries every count from all of them down
/// to one and takes the first that fits.
struct WidgetSongList: View {
    let songs: [WidgetCapture]
    let style: WidgetSongRow.Style
    /// When set, a line under the rows counts the songs not shown.
    var totalCount: Int?

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: songs.count, through: 1, by: -1)), id: \.self) { shown in
                rows(showing: shown)
            }
        }
    }

    private func rows(showing shown: Int) -> some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            ForEach(songs.prefix(shown)) { capture in
                WidgetSongRow(capture: capture, style: style)
            }
            if let totalCount, totalCount > shown {
                Text("^[\(totalCount - shown) more song](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, style.textInset)
                    // The section header already gives VoiceOver the whole count.
                    .accessibilityHidden(true)
            }
        }
    }
}
