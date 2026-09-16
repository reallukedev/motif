import Foundation
import MotifCore

enum DemoMode {
    /// `-MotifDemoData YES` on the command line (or in the scheme's arguments).
    static var isRequestedAtLaunch: Bool {
        UserDefaults.standard.bool(forKey: "MotifDemoData")
    }

    /// A fresh in-memory store filled with `DemoLibrary` plays ending now.
    @MainActor
    static func makeStore() throws -> MotifStore {
        let store = try MotifStore(inMemory: true, sync: false)
        try store.seedDemoData(DemoLibrary.plays(endingAt: .now, days: days))
        return store
    }

    /// `-MotifDemoDays 1800` alongside `-MotifDemoData YES`, in a Debug build: years of sample
    /// listening instead of ten months, to see how the screens hold up in a long history.
    private static var days: Int {
        #if DEBUG
        let requested = UserDefaults.standard.integer(forKey: "MotifDemoDays")
        if requested > 0 { return requested }
        #endif
        return 300
    }

    /// `-MotifDemoLive YES` alongside `-MotifDemoData YES`, in a Debug build: a sample song
    /// finishes every few seconds, to watch the screens change as listening arrives.
    static var isLiveRequested: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "MotifDemoLive")
        #else
        false
        #endif
    }

    /// Adds a sample song to the demo store every `interval` until cancelled.
    @MainActor
    static func runLiveFeed(into store: MotifStore, every interval: Duration = .seconds(5)) async {
        var number = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            number += 1
            try? store.seedDemoData([DemoLibrary.livePlay(at: .now, number: number)])
        }
    }
}
