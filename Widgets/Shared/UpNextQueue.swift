/// The songs "Play back" will play next: as many as fit, plus the total waiting.
struct UpNextQueue: Sendable, Hashable {
    /// The first few, in the order they will play.
    let songs: [WidgetCapture]
    /// Every song waiting, usually more than fit.
    let totalCount: Int

    /// Songs waiting beyond the ones shown.
    var remainingCount: Int { max(0, totalCount - songs.count) }

    var isEmpty: Bool { totalCount == 0 }
}
