import SwiftUI

/// How a screen changes when new listening arrives: numbers roll to their new value, bars
/// grow, and a new song slides into its place.
///
/// Only for live changes. A screen's first figures, and a switch to another range, appear at
/// once: animating a whole screen in is noise, not news.
enum LiveUpdate {
    /// Nil with Reduce Motion, so the new figures simply appear.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.5)
    }

    /// Runs `body`, animated when `isLive` says the change is new listening on the same
    /// screen rather than a first load or a different selection.
    static func apply(isLive: Bool, reduceMotion: Bool, _ body: () -> Void) {
        withAnimation(isLive ? animation(reduceMotion: reduceMotion) : nil, body)
    }
}
