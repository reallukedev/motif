import SwiftUI
import Charts
import MotifCore

/// Moving Summary back and forward a week, month or year, handed down to the cards whose
/// charts can be swiped and the header that steps through periods.
struct StatsPeriodPaging: Sendable {
    /// Whether there's an earlier period with history, and a later one than this.
    var canGoBack: Bool
    var canGoForward: Bool
    /// -1 for an earlier period, +1 for a later one.
    var page: @MainActor @Sendable (Int) -> Void

    @MainActor
    func goBack() {
        if canGoBack { page(-1) }
    }

    @MainActor
    func goForward() {
        if canGoForward { page(1) }
    }
}

extension EnvironmentValues {
    /// Set by Summary. Nil elsewhere, where charts keep to the period they were given.
    @Entry var statsPaging: StatsPeriodPaging?
}

/// ‹ September 2026 ›: the period on show, with a step either side. The steps are what the
/// Mac and VoiceOver use; on iPhone the charts can be swiped as well.
struct PeriodPager: View {
    let summary: StatsSummary
    let paging: StatsPeriodPaging

    var body: some View {
        HStack(spacing: 2) {
            Button("Earlier", systemImage: "chevron.backward", action: paging.goBack)
                .disabled(!paging.canGoBack)
                .help(Text("Show the \(Text(summary.range.unitName)) before"))
            Text(summary.periodTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
            Button("Later", systemImage: "chevron.forward", action: paging.goForward)
                .disabled(!paging.canGoForward)
                .help(Text("Show the \(Text(summary.range.unitName)) after"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .imageScale(.small)
        .fontWeight(.semibold)
        .animation(.snappy(duration: 0.2), value: summary.periodTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.periodTitle)
        .accessibilityHint(Text("Swipe up or down to change the \(Text(summary.range.unitName))."))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: paging.goForward()
            case .decrement: paging.goBack()
            @unknown default: break
            }
        }
    }
}

extension View {
    /// Swiping sideways across a chart moves to the period before or after, as in Health and
    /// Screen Time. Reading a bar becomes touch and hold, then drag, so the two don't fight.
    /// The Mac keeps hovering to read, and pages with the steps beside the period's title.
    func periodSwipe(_ paging: StatsPeriodPaging?, selection: Binding<Date?>) -> some View {
        #if os(iOS)
        modifier(PeriodSwipe(paging: paging, selection: selection))
        #else
        chartXSelection(value: selection)
        #endif
    }
}

#if os(iOS)
private struct PeriodSwipe: ViewModifier {
    let paging: StatsPeriodPaging?
    @Binding var selection: Date?

    func body(content: Content) -> some View {
        if let paging {
            content
                .chartXSelection(value: $selection)
                .chartGesture { proxy in
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, let drag?) = value {
                                proxy.selectXValue(at: drag.location.x)
                            }
                        }
                        .onEnded { _ in selection = nil }
                        .exclusively(before: DragGesture(minimumDistance: 24).onEnded { value in
                            let across = value.translation.width
                            // Mostly sideways, and far enough to mean it.
                            guard abs(across) > 44, abs(across) > abs(value.translation.height) * 1.5 else { return }
                            // Content follows the finger: swiping right brings in the past.
                            if across > 0 { paging.goBack() } else { paging.goForward() }
                        })
                }
        } else {
            content.chartXSelection(value: $selection)
        }
    }
}
#endif

/// A period with nothing in it, with the steps still there so an empty month in the middle
/// of a history isn't a dead end.
struct NothingPlayedView: View {
    let summary: StatsSummary
    @Environment(\.statsPaging) private var paging

    var body: some View {
        VStack(spacing: 12) {
            if let paging {
                PeriodPager(summary: summary, paging: paging)
            }
            ContentUnavailableView(
                "Nothing Played \(summary.phrase)",
                systemImage: "waveform",
                description: summary.range == .allTime
                    ? Text("Songs appear here as Motif keeps them.")
                    : Text("Try another \(Text(summary.range.unitName)), or a longer range.")
            )
        }
    }
}
