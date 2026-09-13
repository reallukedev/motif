import SwiftUI
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

    func includes(_ capture: Capture) -> Bool {
        switch self {
        case .all: true
        case .radio: capture.kind == .radio
        case .onDemand: capture.kind == .onDemand
        case .recovered: capture.kind == .imported
        }
    }
}
