import Foundation
import Observation
import MotifCore

/// The playlists you make in Motif, kept on this iPhone beside the rest of your music's records.
@MainActor
@Observable
final class Playlists {
    private(set) var all: [MotifPlaylist] = []
    /// Songs being added to a playlist from a menu anywhere: the sheet to choose one shows while
    /// they're here.
    var picking: PlaylistPick?

    /// Playlists not to merge with Apple Music again, by Motif id or Apple Music id: ones you
    /// stopped merging, or deleted on one side.
    private(set) var unmerged: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Playlists.unmergedKey) ?? [])

    @ObservationIgnored private let isDemo: Bool
    private static let unmergedKey = "unmergedPlaylists"

    init(isDemo: Bool) {
        self.isDemo = isDemo
        guard !isDemo,
              let data = try? Data(contentsOf: Self.recordURL),
              let saved = try? JSONDecoder().decode([MotifPlaylist].self, from: data)
        else { return }
        all = saved
    }

    /// Most recently changed first, as Music lists them.
    var recent: [MotifPlaylist] { all.sorted { $0.updatedAt > $1.updatedAt } }

    /// The ones songs can be added to: not smart ones, whose songs are their rules'.
    var fillable: [MotifPlaylist] { recent.filter { !$0.isSmart } }

    func playlist(id: UUID) -> MotifPlaylist? { all.first { $0.id == id } }

    @discardableResult
    func create(name: String, tracks: [LocalTrack] = [], rules: SmartRules? = nil) -> MotifPlaylist {
        var playlist = MotifPlaylist(name: Self.named(name), rules: rules)
        playlist.add(tracks)
        all.append(playlist)
        save()
        return playlist
    }

    /// Changes a playlist, whatever is changed, and keeps it.
    /// - Parameter touches: counts as a change you made, bringing it to the top of the list.
    ///   A merge noting what it's seen doesn't.
    func update(_ id: UUID, touches: Bool = true, _ change: (inout MotifPlaylist) -> Void) {
        guard let position = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[position])
        if touches { all[position].updatedAt = .now }
        save()
    }

    /// Stops merging a playlist with Apple Music, for good: neither it nor its Apple Music
    /// playlist is merged again, though both keep their songs.
    func stopMerging(_ id: UUID) {
        guard let link = playlist(id: id)?.appleMusic else { return }
        unmerge([id.uuidString, link.playlistID])
        update(id, touches: false) { $0.appleMusic = nil }
    }

    /// Keeps playlists from being merged again.
    func unmerge(_ ids: [String]) {
        unmerged.formUnion(ids)
        guard !isDemo else { return }
        UserDefaults.standard.set(Array(unmerged), forKey: Self.unmergedKey)
    }

    func rename(_ id: UUID, to name: String) {
        update(id) { $0.name = Self.named(name) }
    }

    func add(_ tracks: [LocalTrack], to id: UUID) {
        update(id) { $0.add(tracks) }
    }

    func delete(_ id: UUID) {
        // Its Apple Music playlist stays, and isn't made into a Motif one again.
        if let link = playlist(id: id)?.appleMusic { unmerge([link.playlistID]) }
        all.removeAll { $0.id == id }
        save()
    }

    /// A name, or "New Playlist" for none.
    private static func named(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "New Playlist") : trimmed
    }

    private static var recordURL: URL { LibraryFolders.index.appending(path: "playlists.json") }

    private func save() {
        guard !isDemo, let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: Self.recordURL, options: .atomic)
    }
}

/// Songs on their way into a playlist, for the sheet that asks which.
struct PlaylistPick: Identifiable {
    let id = UUID()
    let tracks: [LocalTrack]
}

extension YourMusic {
    /// A playlist's songs as they are in your music now: one you fill yourself, its songs in
    /// order, each as the library has it since the last sync; a smart one, whichever of yours
    /// match its rules.
    /// - Parameter facts: what's known of each song's plays, by identity, for rules that ask.
    func songs(in playlist: MotifPlaylist, facts: [String: SongFacts]) -> [LocalTrack] {
        if let rules = playlist.rules {
            return rules.songs(
                from: tracks(for: rules.source),
                facts: facts,
                seed: FreshShuffle.dailySeed(for: .now, salt: playlist.id.uuidString)
            )
        }
        return playlist.entries.map { current($0.track) }
    }

    /// A song as your music has it now: moved, re-synced or downloaded since it was noted down.
    func current(_ track: LocalTrack) -> LocalTrack {
        index.track(forSongID: track.id, identity: track.identity) ?? track
    }

    /// The songs a smart playlist takes from: what plays with no connection, or everything.
    func tracks(for source: SmartRules.Source) -> [LocalTrack] {
        switch source {
        case .downloaded: fileTracks + downloads.tracks.map(current)
        case .yourMusic: index.tracks
        }
    }
}
