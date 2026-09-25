import Foundation
import Network
import Observation

/// Whether the iPhone is online, and on a metered connection, so server music that isn't
/// downloaded can be shown as out of reach.
@MainActor
@Observable
final class NetworkStatus {
    private(set) var isOnline = true
    /// Cellular, or a hotspot: where downloads wait unless allowed.
    private(set) var isExpensive = false

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isOnline = online
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.luke.motif.network"))
    }

    deinit {
        monitor.cancel()
    }
}
