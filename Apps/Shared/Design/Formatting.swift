import Foundation
import SwiftUI

enum Format {
    /// "42m", "3h 5m", "912h". Under a minute reads "0m"; the estimate isn't that precise.
    static func listening(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else {
            return Duration.seconds(0).formatted(.units(allowed: [.minutes], width: .narrow, zeroValueUnits: .show(length: 1)))
        }
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 6_000 ? [.hours] : [.hours, .minutes]
        return Duration.seconds(Double(minutes) * 60)
            .formatted(.units(allowed: allowed, width: .narrow, maximumUnitCount: 2))
    }

    /// Hours and minutes as two parts, for the big number on a card ("18" "hr" "20" "min").
    static func listeningParts(_ seconds: TimeInterval) -> (hours: Int, minutes: Int) {
        let minutes = Int((seconds / 60).rounded())
        return (minutes / 60, minutes % 60)
    }

    /// "+12%", "-8%".
    static func percentChange(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
    }

    /// "9 AM", localised.
    static func hour(_ hour: Int, calendar: Calendar = .current) -> String {
        guard let date = calendar.date(from: DateComponents(hour: hour % 24)) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }

    /// Today → "Today", yesterday → "Yesterday", this week → "Tuesday", else "7 Sep" (with
    /// the year only when it isn't this year).
    static func day(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    /// A time for today, "Yesterday", a weekday within the week, otherwise a short date.
    static func relativeTime(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return shortDate(date, calendar: calendar, now: now)
    }

    /// "Sep 13, 9:24 PM", with the year only for past years.
    static func shortDateTime(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    static func shortDate(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
