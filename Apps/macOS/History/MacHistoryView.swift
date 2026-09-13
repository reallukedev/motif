import SwiftUI
import SwiftData
import MotifCore

/// Every play as a sortable table, with the selected song in an inspector.
struct MacHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Query(sort: \Capture.capturedAt, order: .reverse) private var captures: [Capture]
    @State private var selection = Set<PersistentIdentifier>()
    @State private var sortOrder = [KeyPathComparator(\Capture.capturedAt, order: .reverse)]
    @State private var filter: HistoryFilter = .all
    @State private var showsInspector = false
    @State private var pendingDelete: Capture?
    @State private var isScrobbling = LastFMSessionStore.current != nil

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { capture in
                HStack(spacing: 8) {
                    ArtworkView(url: capture.artworkURL, seed: capture.albumTitle ?? capture.title, size: 26)
                    Text(capture.title)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Artist", value: \.artistName)
                .width(min: 110, ideal: 160)

            TableColumn("Album", value: \.albumSortKey) { capture in
                Text(capture.albumTitle ?? "")
            }
            .width(min: 100, ideal: 150)

            TableColumn("Source", value: \.kindRawValue) { capture in
                Label(capture.kind.label, systemImage: capture.kind.symbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(capture.kind == .onDemand ? .secondary : capture.kind.tint)
                    .lineLimit(1)
            }
            .width(min: 118, ideal: 124)

            TableColumn("Played", value: \.capturedAt) { capture in
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
                Button("Delete ^[\(ids.count) Play](inflect: true)", role: .destructive) {
                    deleteAll(ids)
                }
            }
        } primaryAction: { ids in
            if single(ids) != nil { showsInspector = true }
        }
        .onDeleteCommand {
            guard !model.isShowingSampleData else { return }
            if let capture = single(selection) {
                pendingDelete = capture
            } else {
                deleteAll(selection)
            }
        }
        .overlay {
            if captures.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Songs you play in Music will collect here.")
                )
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
        .navigationSubtitle(String(AttributedString(localized: "^[\(rows.count) play](inflect: true)").characters))
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
                } label: {
                    Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Show only radio, on demand or recovered songs")
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    showsInspector.toggle()
                }
                .help("Show or hide the song inspector")
            }
        }
        .deleteConfirmation(for: $pendingDelete)
    }

    private var rows: [Capture] {
        captures.filter(filter.includes).sorted(using: sortOrder)
    }

    private func single(_ ids: Set<PersistentIdentifier>) -> Capture? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return captures.first { $0.persistentModelID == id }
    }

    private func deleteAll(_ ids: Set<PersistentIdentifier>) {
        for capture in captures where ids.contains(capture.persistentModelID) {
            try? model.activeStore?.deletePlay(capture)
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
        } else if capture.scrobbleAttempts >= MotifStore.maxScrobbleAttempts {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .help(capture.lastScrobbleError ?? "Last.fm didn't accept this one")
        } else {
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .help("Waiting to be scrobbled")
        }
    }
}

extension Capture {
    /// Albums sort with blanks last rather than first.
    var albumSortKey: String { albumTitle ?? "\u{10FFFF}" }
}
