import SwiftUI
import SwiftData
import MotifCore

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, radio, onDemand, recovered

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All Songs"
        case .radio: "Radio"
        case .onDemand: "On Demand"
        case .recovered: "Recovered"
        }
    }

    var symbol: String {
        switch self {
        case .all: "music.note.list"
        case .radio: "dot.radiowaves.left.and.right"
        case .onDemand: "music.note"
        case .recovered: "clock.arrow.circlepath"
        }
    }

    /// The plays a history list shows, filtered and sorted by the store rather than in
    /// memory, and at most `limit` of them.
    ///
    /// The lists used to query every play and filter and sort them in `body`. Sorting a
    /// hundred and fifty thousand plays by title took five seconds on the main actor.
    func descriptor(
        sortBy: [SortDescriptor<Capture>] = [SortDescriptor(\.capturedAt, order: .reverse)],
        in interval: DateInterval? = nil,
        limit: Int? = nil
    ) -> FetchDescriptor<Capture> {
        let kind = self.kind?.rawValue
        let start = interval?.start ?? .distantPast
        let end = interval?.end ?? .distantFuture
        var descriptor = FetchDescriptor<Capture>(sortBy: sortBy)
        if let kind {
            descriptor.predicate = #Predicate {
                $0.kindRawValue == kind && $0.capturedAt >= start && $0.capturedAt < end
            }
        } else if interval != nil {
            descriptor.predicate = #Predicate { $0.capturedAt >= start && $0.capturedAt < end }
        }
        descriptor.fetchLimit = limit
        return descriptor
    }

    private var kind: CaptureKind? {
        switch self {
        case .all: nil
        case .radio: .radio
        case .onDemand: .onDemand
        case .recovered: .imported
        }
    }
}

/// How many plays a history list reads at a time. More are read as the end scrolls into view.
enum HistoryPage {
    static let size = 300
}
