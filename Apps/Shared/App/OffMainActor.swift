import Foundation

/// Work that walks the whole listening history, moved off the main actor.
///
/// A view's `task` runs on the main actor, so a statistic worked out inside one blocks
/// scrolling and taps until it's done. In a long history that's hundreds of milliseconds to
/// seconds. Take the values the work needs out of the view first, then hand them over here.
nonisolated enum OffMainActor {
    @concurrent
    static func run<Value: Sendable>(_ work: @Sendable () -> Value) async -> Value {
        work()
    }
}
