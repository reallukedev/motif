import SwiftUI
import SwiftData
import MotifCore

/// Every play as a sortable table, with the selected song in an inspector.
///
/// The store filters, sorts and pages the rows. The table reads a page at a time, and the
/// next as its last row scrolls into view, so neither opening History nor clicking a column
/// header costs more in a long history.
struct MacHistoryView: View {
    @State private var sortOrder = [SortDescriptor(\Capture.capturedAt, order: .reverse)]
    @State private var filter: HistoryFilter = .all
    @State private var limit = HistoryPage.size
    private var sources = SourceScopeSetting()

    var body: some View {
        MacHistoryTable(
            filter: $filter,
            sortOrder: $sortOrder,
            source: sources.scope,
            sourceSelection: sources.isOffered ? sources.selection : nil,
            limit: limit,
            loadMore: { limit += HistoryPage.size }
        )
        // A different filter or order starts again from the top.
        .onChange(of: filter) { limit = HistoryPage.size }
        .onChange(of: sources.scope) { limit = HistoryPage.size }
        .onChange(of: sortOrder) { limit = HistoryPage.size }
    }
}

private struct MacHistoryTable: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Binding var filter: HistoryFilter
    @Binding var sortOrder: [SortDescriptor<Capture>]
    let source: SourceScope
    /// Apple Music or Your Music alone, when the person has asked to see them apart.
    let sourceSelection: Binding<SourceScope>?
    let limit: Int
    let loadMore: () -> Void

    /// Animated, so a song that just finished slides in at the top.
    @Query private var rows: [Capture]
    @State private var selection = Set<PersistentIdentifier>()
    @State private var showsInspector = false
    @State private var pendingDelete: Capture?
    /// Plays waiting on the multiple-selection delete confirmation.
    @State private var pendingBulkDelete: Set<PersistentIdentifier> = []
    /// Every play the filter matches, not just the ones loaded, for the subtitle.
    @State private var total: Int?
    /// Bumped by each save and each batch of synced changes, so the total follows them.
    @State private var storeChanges = 0
    @State private var isScrobbling = false
    /// Written last when Settings connects or disconnects Last.fm, so the column follows it.
    @AppStorage(LastFMSessionStore.usernameDefaultsKey, store: CaptureSettings.sharedDefaults)
    private var lastFMUsername: String?
    @Environment(\.modelContext) private var context

    init(
        filter: Binding<HistoryFilter>,
        sortOrder: Binding<[SortDescriptor<Capture>]>,
        source: SourceScope,
        sourceSelection: Binding<SourceScope>?,
        limit: Int,
        loadMore: @escaping () -> Void
    ) {
        _filter = filter
        _sortOrder = sortOrder
        self.source = source
        self.sourceSelection = sourceSelection
        self.limit = limit
        self.loadMore = loadMore
        _rows = Query(
            filter.wrappedValue.descriptor(sortBy: sortOrder.wrappedValue, source: source, limit: limit),
            animation: .default
        )
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", sortUsing: SortDescriptor(\Capture.title, comparator: .localizedStandard)) { capture in
                HStack(spacing: 8) {
                    ArtworkView(url: capture.artworkURL, seed: capture.albumTitle ?? capture.title, size: 26)
                    Text(capture.title)
                }
                .onAppear {
                    if rows.count >= limit, capture.persistentModelID == rows.last?.persistentModelID {
                        loadMore()
                    }
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Artist", sortUsing: SortDescriptor(\Capture.artistName, comparator: .localizedStandard)) { capture in
                Text(capture.artistName)
            }
            .width(min: 110, ideal: 160)

            TableColumn("Album", sortUsing: SortDescriptor(\Capture.albumTitle, comparator: .localizedStandard)) { capture in
                Text(capture.albumTitle ?? "")
            }
            .width(min: 100, ideal: 150)

            TableColumn("Source", sortUsing: SortDescriptor(\Capture.kindRawValue)) { capture in
                // A song you chose from your own music says so, rather than "On Demand".
                if capture.kind == .onDemand, capture.source == .yourMusic {
                    Label(SourceScope.yourMusic.title, systemImage: SourceScope.yourMusic.symbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Label(capture.kind.label, systemImage: capture.kind.symbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(capture.kind == .onDemand ? .secondary : capture.kind.tint)
                        .lineLimit(1)
                }
            }
            .width(min: 118, ideal: 124)

            TableColumn("Played", sortUsing: SortDescriptor(\Capture.capturedAt, order: .reverse)) { capture in
                Text(Format.shortDateTime(capture.capturedAt))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Last.fm") { capture in
                scrobbleState(capture)
            }
            .width(56)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if let capture = single(ids) {
                PlayActions(capture: capture, onDelete: { pendingDelete = capture })
            } else if !ids.isEmpty, !model.isShowingSampleData {
                Button("Delete ^[\(ids.count) Play](inflect: true)…", role: .destructive) {
                    pendingBulkDelete = ids
                }
            }
        } primaryAction: { ids in
            if single(ids) != nil { showsInspector = true }
        }
        .onDeleteCommand {
            guard !model.isShowingSampleData else { return }
            if let capture = single(selection) {
                pendingDelete = capture
            } else if !selection.isEmpty {
                pendingBulkDelete = selection
            }
        }
        .overlay {
            if rows.isEmpty, total != nil {
                if filter == .all, source != .all {
                    ContentUnavailableView("Nothing from \(Text(source.title))", systemImage: source.symbol)
                } else if filter == .all {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Songs you play in Music will collect here.")
                    )
                } else {
                    ContentUnavailableView("No \(Text(filter.title))", systemImage: filter.symbol)
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let capture = single(selection) {
                    SongDetailView(songID: HistoryImport.key(title: capture.title, artistName: capture.artistName))
                } else if selection.isEmpty {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "music.note",
                        description: Text("Select a song to see its plays.")
                    )
                } else {
                    ContentUnavailableView("^[\(selection.count) Song](inflect: true) Selected", systemImage: "music.note.list")
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .navigationTitle("History")
        .navigationSubtitle(String(AttributedString(localized: "^[\(total ?? rows.count) play](inflect: true)").characters))
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { filter in
                            Label(filter.title, systemImage: filter.symbol).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelStyle(.titleAndIcon)
                    if let sourceSelection {
                        Section("Music") {
                            Picker("Music", selection: sourceSelection) {
                                ForEach(SourceScope.allCases) { scope in
                                    Label(scope.title, systemImage: scope.symbol).tag(scope)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelStyle(.titleAndIcon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all && source == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .help(sourceSelection == nil
                    ? "Show only radio, on demand or recovered songs"
                    : "Show only radio, on demand or recovered songs, or Apple Music or Your Music alone")
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    showsInspector.toggle()
                }
                .help("Show or hide the song inspector")
            }
        }
        .deleteConfirmation(for: $pendingDelete)
        // No undo, so the confirmation is the safeguard. The store's one context is shared
        // with capture and sync: with an undo manager left attached, undo also reverts their
        // saves, and detaching it after the delete throws the registration away.
        .confirmationDialog(
            "Delete ^[\(pendingBulkDelete.count) Play](inflect: true)?",
            isPresented: Binding(
                get: { !pendingBulkDelete.isEmpty },
                set: { if !$0 { pendingBulkDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete ^[\(pendingBulkDelete.count) Play](inflect: true)", role: .destructive) {
                deleteAll(pendingBulkDelete)
            }
            // Return cancels, so a keyboard confirmation can't delete by accident.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("This can't be undone. Scrobbles already sent stay on Last.fm.")
        }
        // A count query uses the kind and date index, so it stays quick in a long history.
        .task(id: "\(filter.rawValue)|\(source.rawValue)|\(storeChanges)") {
            total = try? context.fetchCount(filter.descriptor(source: source))
        }
        .onStoreChange(of: context) { storeChanges += 1 }
        .onChange(of: lastFMUsername, initial: true) {
            isScrobbling = LastFMSessionStore.current != nil
        }
    }

    private func single(_ ids: Set<PersistentIdentifier>) -> Capture? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return rows.first { $0.persistentModelID == id }
    }

    private func deleteAll(_ ids: Set<PersistentIdentifier>) {
        for capture in rows where ids.contains(capture.persistentModelID) {
            try? model.store?.deletePlay(capture)
        }
        selection.removeAll()
    }

    @ViewBuilder
    private func scrobbleState(_ capture: Capture) -> some View {
        if !isScrobbling {
            EmptyView()
        } else if capture.scrobbledAt != nil {
            Image(systemName: "checkmark")
                .foregroundStyle(.secondary)
                .help("Scrobbled")
                .accessibilityLabel("Scrobbled")
        } else if capture.scrobbleAttempts >= MotifStore.maxScrobbleAttempts {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .help(capture.lastScrobbleError ?? "Last.fm didn't accept this one")
                .accessibilityLabel("Not scrobbled")
                .accessibilityValue(capture.lastScrobbleError ?? "Last.fm didn't accept this one")
        } else {
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .help("Waiting to be scrobbled")
                .accessibilityLabel("Waiting to be scrobbled")
        }
    }
}
