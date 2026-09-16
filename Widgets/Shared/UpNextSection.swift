import SwiftUI

/// What the Play button will play, in the order it will play it.
struct UpNextSection: View {
    let queue: UpNextQueue
    let rowStyle: WidgetSongRow.Style
    /// Off in the medium widget, which has no room. VoiceOver gets the count from the header.
    let showsRemainingCount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: rowStyle.spacing) {
            WidgetSectionHeader(
                title: "Up Next",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                accessibilityValue: queue.isEmpty
                    ? nil
                    : Text("^[\(queue.totalCount) song](inflect: true)")
            ) {
                // Nothing to play, so no button.
                if !queue.isEmpty {
                    PlayBackButton()
                }
            }

            if queue.isEmpty {
                UpNextEmptyState()
            } else {
                WidgetSongList(
                    songs: queue.songs,
                    style: rowStyle,
                    totalCount: showsRemainingCount ? queue.totalCount : nil
                )
            }
        }
    }
}
