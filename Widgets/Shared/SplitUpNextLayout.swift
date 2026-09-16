import SwiftUI

/// The medium Today widget with Up Next on: the song just heard beside what plays next.
///
/// Side by side because a medium widget is only three rows tall. The leading half matches
/// a small Last Played widget.
struct SplitUpNextLayout: View {
    let latest: WidgetCapture
    let upNext: UpNextQueue

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Link(destination: DeepLink.song(title: latest.title, artistName: latest.artistName).url) {
                LastPlayedCard(capture: latest)
            }
            UpNextSection(queue: upNext, rowStyle: .compact, showsRemainingCount: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
