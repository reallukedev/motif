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
        try store.seedDemoData(DemoLibrary.plays(endingAt: .now))
        return store
    }
}
