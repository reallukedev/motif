import SwiftUI

/// The large Today widget with Up Next on: what has played, then what plays next.
struct StackedUpNextLayout: View {
    let today: [WidgetCapture]
    let upNext: UpNextQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TodaySection(captures: today, rowStyle: .regular, showsPlayButton: false)
            // Sized first so the queue shows in full; Today gets the rest.
            UpNextSection(queue: upNext, rowStyle: .regular, showsRemainingCount: true)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
