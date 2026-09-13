import SwiftUI
import SwiftData
import MotifCore

/// Every play, newest first, grouped by day.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Capture.capturedAt, order: .reverse) private var captures: [Capture]
    @State private var filter: HistoryFilter = .all
    @State private var pendingDelete: Capture?
    @State private var isScrobbling = LastFMSessionStore.current != nil

    var body: some View {
        List {
            ForEach(days, id: \.day) { day in
                Section {
                    ForEach(day.captures) { capture in
                        NavigationLink(value: Route.song(HistoryImport.key(title: capture.title, artistName: capture.artistName))) {
                            CaptureRow(capture: capture, showsScrobbleState: isScrobbling)
                        }
                        .swipeActions(edge: .trailing) {
                            if !model.isShowingSampleData {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = capture
                                }
                            }
                        }
                        .contextMenu { PlayActions(capture: capture, onDelete: { pendingDelete = capture }) }
                    }
                } header: {
                    DayHeader(day: day.day, count: day.captures.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if captures.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Songs you play in Apple Music will collect here.")
                )
            } else if days.isEmpty {
                ContentUnavailableView("No \(Text(filter.title))", systemImage: filter.symbol)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                    Picker("Show", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.symbol).tag(filter)
                        }
                    }
                }
            }
        }
        .deleteConfirmation(for: $pendingDelete)
    }

    private var days: [(day: Date, captures: [Capture])] {
        let calendar = Calendar.current
        var groups: [(day: Date, captures: [Capture])] = []
        for capture in captures where filter.includes(capture) {
            let day = calendar.startOfDay(for: capture.capturedAt)
            if groups.last?.day == day {
                groups[groups.count - 1].captures.append(capture)
            } else {
                groups.append((day, [capture]))
            }
        }
        return groups
    }
}

struct DayHeader: View {
    let day: Date
    let count: Int

    var body: some View {
        AdaptiveStack {
            Text(Format.day(day))
            Spacer(minLength: 0)
            Text("^[\(count) song](inflect: true)")
                .monospacedDigit()
        }
    }
}
