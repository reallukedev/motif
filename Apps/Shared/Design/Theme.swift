import SwiftUI
import MotifCore

extension Insight.Category {
    var tint: Color {
        switch self {
        case .achievement: .orange
        case .trend: .blue
        case .favourites: .pink
        case .discovery: .purple
        case .rhythm: .indigo
        case .radio: .red
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .achievement: "Achievement"
        case .trend: "Trend"
        case .favourites: "Favorites"
        case .discovery: "Discovery"
        case .rhythm: "Rhythm"
        case .radio: "Radio"
        }
    }
}

extension CaptureKind {
    var tint: Color {
        switch self {
        case .onDemand: .accentColor
        case .radio: .pink
        case .imported: .teal
        }
    }

    var symbol: String {
        switch self {
        case .onDemand: "music.note"
        case .radio: "dot.radiowaves.left.and.right"
        case .imported: "clock.arrow.circlepath"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .onDemand: "On Demand"
        case .radio: "Radio"
        case .imported: "Recovered"
        }
    }
}

extension StatsRange {
    var label: LocalizedStringKey {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .allTime: "All Time"
        }
    }

    /// "this week", for sentences.
    var phrase: LocalizedStringKey {
        switch self {
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        case .allTime: "of all time"
        }
    }

    /// "last week", for the comparison under a number.
    var previousPhrase: LocalizedStringKey {
        switch self {
        case .week: "this time last week"
        case .month: "this time last month"
        case .year: "this time last year"
        case .allTime: ""
        }
    }
}

enum Metrics {
    #if os(iOS)
    static let cardRadius: CGFloat = 26
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    #else
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    #endif
}
