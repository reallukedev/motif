import SwiftUI
import Combine
import GroupActivities
import MusicKit
import MotifCore
import MotifMusic

/// Motif's SharePlay sessions, for the whole process: hosting, where this iPhone plays and
/// takes songs from the group, and joining someone else's, where this iPhone only picks.
///
/// The host tells the group what's on whenever it changes; a guest asks for a song, the host
/// looks it up the way its player would play it and answers. The rules for what goes in live
/// in MotifCore (``SharePlayGate``, ``SharePlayGuest``); this is the plumbing around them.
@MainActor
@Observable
final class SharePlayController {
    static let shared = SharePlayController()

    enum Role: Equatable {
        case idle
        /// This iPhone started SharePlay and plays for the group.
        case host
        /// This iPhone joined someone else's and picks songs for it.
        case guest
    }

    private(set) var role: Role = .idle

    // MARK: Host

    /// People who've joined, across every session this iPhone started.
    private(set) var guestCount = 0
    /// Which songs in Up Next someone at SharePlay added.
    private(set) var ledger = SharePlayLedger()

    // MARK: Guest

    private(set) var guest = SharePlayGuest()
    /// The guest page is up. Set as a session arrives and cleared as it's left.
    var showsGuestPage = false
    /// Joined, but the host hasn't answered for a while.
    private(set) var isSlowToConnect = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var hostLinks: [ObjectIdentifier: Link] = [:]
    @ObservationIgnored private var guestLink: Link?
    @ObservationIgnored private var snapshotFollower: Task<Void, Never>?
    @ObservationIgnored private var gate = SharePlayGate()
    @ObservationIgnored private var broadcast = SharePlayBroadcast()
    #if DEBUG
    /// Sample data's pretend sessions, which the simulator can't run for real.
    @ObservationIgnored private(set) var demo: SharePlayDemo?
    #endif

    /// One session and what listens to it.
    private final class Link {
        let session: GroupSession<SharePlayActivity>
        let messenger: GroupSessionMessenger
        var tasks: [Task<Void, Never>] = []

        init(session: GroupSession<SharePlayActivity>) {
            self.session = session
            messenger = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        }

        func cancel() {
            tasks.forEach { $0.cancel() }
            tasks = []
        }
    }

    /// Starts listening for sessions, once per process: one this iPhone started from the
    /// share sheet, or one it was invited to and joined in Messages.
    func start(model: AppModel) {
        guard listener == nil else { return }
        self.model = model
        #if DEBUG
        if model.isDemoLaunch, let scene = LaunchScene.sharePlayDemo {
            demo = SharePlayDemo(scene: scene)
            demo?.start(in: self, model: model)
            listener = Task {}
            return
        }
        #endif
        listener = Task { [weak self] in
            for await session in SharePlayActivity.sessions() {
                self?.receive(session)
            }
        }
    }

    private func receive(_ session: GroupSession<SharePlayActivity>) {
        if session.isLocallyInitiated {
            host(session)
        } else {
            joinAsGuest(session)
        }
    }

    // MARK: - Hosting

    /// Whether a song in Up Next came from SharePlay, for the glyph on its row.
    func isFromSharePlay(_ track: PlayerTrack) -> Bool {
        role == .host && ledger.contains(track.songIdentity)
    }

    /// Ends SharePlay for everyone.
    func endHosting() {
        for link in hostLinks.values {
            link.session.end()
        }
        #if DEBUG
        if demo != nil { stopHosting() }
        #endif
    }

    private func host(_ session: GroupSession<SharePlayActivity>) {
        // Hosting and picking for someone else at once would mix up whose queue is whose.
        if role == .guest { leave() }
        let link = Link(session: session)
        let key = ObjectIdentifier(session)
        hostLinks[key] = link
        role = .host
        link.tasks.append(Task { [weak self, weak link] in
            guard let link else { return }
            for await (message, context) in link.messenger.messages(of: SharePlayMessage.self) {
                self?.hostReceived(message, from: context.source, on: link)
            }
        })
        link.tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                self?.participantsChanged(participants, in: session)
            }
        })
        link.tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state {
                    self?.hostSessionEnded(key)
                    break
                }
            }
        })
        session.join()
        followPlayer()
    }

    private func participantsChanged(_ participants: Set<Participant>, in session: GroupSession<SharePlayActivity>) {
        let joined = participants.subtracting([session.localParticipant]).count
        let before = guestCount
        guestCount = hostLinks.values.reduce(0) { total, link in
            total + (link.session === session ? joined : link.session.activeParticipants.subtracting([link.session.localParticipant]).count)
        }
        // Someone new hears what's on straight away, even if they don't ask.
        if guestCount > before {
            broadcast.resend()
            sendSnapshot()
        }
    }

    private func hostSessionEnded(_ key: ObjectIdentifier) {
        hostLinks.removeValue(forKey: key)?.cancel()
        guard hostLinks.isEmpty else { return }
        stopHosting()
    }

    private func stopHosting() {
        role = .idle
        guestCount = 0
        ledger = SharePlayLedger()
        gate = SharePlayGate()
        broadcast = SharePlayBroadcast()
        snapshotFollower?.cancel()
        snapshotFollower = nil
    }

    /// Tells the group what's on each time it changes.
    private func followPlayer() {
        guard snapshotFollower == nil, let player = model?.player else { return }
        snapshotFollower = Task { [weak self] in
            let snapshots = Observations { [weak self] in self?.currentSnapshot() }
            for await snapshot in snapshots {
                guard let self, let snapshot else { continue }
                // Songs from SharePlay that have played and gone are no longer marked.
                ledger.prune(keeping: snapshot.queuedIdentities.union(Set(player.upNext.map(\.songIdentity))))
                sendSnapshot(snapshot)
            }
        }
    }

    private func sendSnapshot(_ snapshot: SharePlaySnapshot? = nil) {
        guard let snapshot = snapshot ?? currentSnapshot(), let next = broadcast.next(snapshot) else { return }
        for link in hostLinks.values {
            let messenger = link.messenger
            Task { try? await messenger.send(SharePlayMessage.snapshot(next)) }
        }
    }

    /// What's on, as the group sees it.
    func currentSnapshot() -> SharePlaySnapshot? {
        guard let model else { return nil }
        let player = model.player
        let entry = { (track: PlayerTrack) in
            SharePlayTrack(
                id: track.id,
                title: track.title,
                artistName: track.artistName,
                artworkURL: Self.shareableArtwork(track.cover),
                isFromSharePlay: self.ledger.contains(track.songIdentity)
            )
        }
        return SharePlaySnapshot(
            nowPlaying: player.current.map(entry),
            isPlaying: player.isPlaying,
            upNext: player.upNext.prefix(SharePlaySnapshot.upNextLimit).map(entry),
            upNextCount: player.upNext.count,
            source: playsYourMusic ? .yourMusic : .appleMusic,
            isStation: player.context?.isStation == true,
            allowsExplicit: PlayPreferences.allowsExplicit
        )
    }

    /// Your own music is what's playing, or what will play.
    private var playsYourMusic: Bool {
        guard let model else { return false }
        if let current = model.player.current { return current.local != nil }
        return model.musicSource == .yourMusic
    }

    private func hostReceived(_ message: SharePlayMessage, from participant: Participant, on link: Link) {
        switch message {
        case .hello:
            guard let snapshot = currentSnapshot() else { return }
            let messenger = link.messenger
            Task { try? await messenger.send(SharePlayMessage.snapshot(snapshot), to: .only(participant)) }
        case .add(let request):
            Task { await add(request, from: participant.id) { [messenger = link.messenger] reply in
                Task { try? await messenger.send(SharePlayMessage.reply(reply), to: .only(participant)) }
            } }
        case .snapshot, .reply:
            // Only the host says these.
            break
        }
    }

    /// Adds a guest's song to Up Next, or says why not.
    func add(_ request: SharePlayAddRequest, from participant: UUID, reply: @escaping (SharePlayAddReply) -> Void) async {
        guard let model else { return }
        let player = model.player
        let answer = { (outcome: SharePlayAddOutcome) in reply(SharePlayAddReply(requestID: request.id, outcome: outcome)) }
        let queued = Set(([player.current].compactMap(\.self) + player.upNext).map(\.songIdentity))
        switch gate.check(request, from: participant, at: .now, queued: queued, isStation: player.context?.isStation == true) {
        case .ignore:
            return
        case .refuse(let refusal):
            answer(.refused(refusal))
            return
        case .accept:
            break
        }
        if let refusal = await findProblem(with: request.song) {
            gate.release(request, from: participant)
            answer(.refused(refusal))
            return
        }
        // Adding to a station replaces it (see `PlayerModel.enqueue`): the driver's radio would
        // stop for one passenger's song. So a station refuses, and says so on the guest's row.
        // Checked again here, since a station may have started while the song was looked up.
        guard player.context?.isStation != true else {
            gate.release(request, from: participant)
            answer(.refused(.station))
            return
        }
        let song = request.song
        player.enqueue(
            .history([HistorySong(songID: song.catalogID, title: song.title, artistName: song.artistName, albumTitle: song.albumTitle, artworkURL: song.artworkURL)]),
            next: request.placement == .next,
            title: song.title
        )
        if await arrives(song.identity) {
            ledger.record(song.identity)
            // After the player's own "Added to Queue", so this is what stays up.
            player.confirm(String(localized: "Added by SharePlay"))
            answer(.added(request.placement))
        } else {
            gate.release(request, from: participant)
            answer(.refused(.unavailable))
        }
    }

    /// Why the host's player couldn't play a song, found before it's asked to: a failure there
    /// would stop the driver with an alert about someone else's pick.
    private func findProblem(with song: SharePlaySong) async -> SharePlayRefusal? {
        guard let model else { return .unavailable }
        let player = model.player
        // Just switched between Apple Music and your music: the next thing added would
        // replace what's playing rather than join it.
        if let current = player.current, (current.local != nil) != (model.musicSource == .yourMusic) {
            return .unavailable
        }
        if player.isDemo { return nil }
        if model.musicSource == .yourMusic {
            let history = HistorySong(songID: song.catalogID, title: song.title, artistName: song.artistName, albumTitle: song.albumTitle)
            return model.yourMusic.track(for: history) == nil ? .notFound : nil
        }
        guard MusicAuthorization.currentStatus == .authorized else { return .unavailable }
        do {
            guard let found = try await MusicKitPlaybackService.songs(for: [song.catalogID]).first else { return .notFound }
            if found.contentRating == .explicit, !PlayPreferences.allowsExplicit { return .explicit }
            return nil
        } catch {
            return .unavailable
        }
    }

    /// Waits for a song to show up on or after the one playing: the player adds in the
    /// background and doesn't say when.
    private func arrives(_ identity: String) async -> Bool {
        guard let player = model?.player else { return false }
        for _ in 0..<32 {
            if player.current?.songIdentity == identity || player.upNext.contains(where: { $0.songIdentity == identity }) {
                return true
            }
            if player.problem != nil { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// A cover another iPhone can load: Apple Music's, never one from your server, whose
    /// address carries its password.
    static func shareableArtwork(_ cover: CoverArt) -> String? {
        let url: String? = switch cover {
        case .artwork(let artwork): artwork.url(width: 300, height: 300)?.absoluteString
        case .url(let address, _): address
        }
        guard let url, url.hasPrefix("https://"), !url.contains("/rest/") else { return nil }
        return url
    }

    // MARK: - Joining someone else's

    private func joinAsGuest(_ session: GroupSession<SharePlayActivity>) {
        if role == .host {
            // Someone else's invitation while hosting: stay the host.
            session.leave()
            return
        }
        leaveQuietly()
        let link = Link(session: session)
        guestLink = link
        guest = SharePlayGuest()
        isSlowToConnect = false
        role = .guest
        showsGuestPage = true
        link.tasks.append(Task { [weak self, weak link] in
            guard let link else { return }
            for await (message, _) in link.messenger.messages(of: SharePlayMessage.self) {
                self?.guestReceived(message)
            }
        })
        link.tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                switch state {
                case .joined:
                    self?.sayHello()
                case .invalidated:
                    self?.guestSessionEnded()
                    return
                default:
                    break
                }
            }
        })
        session.join()
    }

    /// Asks the host for what's on until it answers: its side may still be getting ready.
    private func sayHello() {
        guard let link = guestLink else { return }
        let messenger = link.messenger
        link.tasks.append(Task { [weak self] in
            for attempt in 0..<30 {
                guard let self, guest.phase == .joining, !Task.isCancelled else { return }
                // Ten seconds without a word: likely one of the two is offline.
                isSlowToConnect = attempt >= 5
                try? await messenger.send(SharePlayMessage.hello)
                try? await Task.sleep(for: .seconds(2))
            }
        })
    }

    private func guestReceived(_ message: SharePlayMessage) {
        switch message {
        case .snapshot(let snapshot): guest.receive(snapshot)
        case .reply(let reply): guest.receive(reply)
        case .hello, .add: break
        }
    }

    /// Sends a song to the host, once, however many times it's pressed.
    func add(_ song: SharePlaySong, placement: SharePlayPlacement) {
        guard let request = guest.add(song, placement: placement, at: .now) else { return }
        #if DEBUG
        if let demo {
            demo.answer(request, in: self)
            return
        }
        #endif
        guard let messenger = guestLink?.messenger else {
            guest.failedToSend(request.id)
            return
        }
        Task {
            do {
                try await messenger.send(SharePlayMessage.add(request))
            } catch {
                guest.failedToSend(request.id)
            }
            // Gives up on it if the host never answers.
            try? await Task.sleep(for: .seconds(SharePlayGuest.answerTimeout))
            guest.expire(at: .now)
        }
    }

    /// Leaves someone else's SharePlay and closes its page. Their queue keeps what was added.
    func leave() {
        leaveQuietly()
        showsGuestPage = false
        if role == .guest { role = .idle }
    }

    private func leaveQuietly() {
        guard let link = guestLink else { return }
        link.cancel()
        link.session.leave()
        guestLink = nil
        if role == .guest { role = .idle }
    }

    /// The host ended it: the page stays, saying so, until it's closed.
    private func guestSessionEnded() {
        guestLink?.cancel()
        guestLink = nil
        guest.end()
    }

    /// Closes the page of a SharePlay that has ended.
    func closeEnded() {
        showsGuestPage = false
        if role == .guest { role = .idle }
    }

    #if DEBUG
    /// For sample data's pretend sessions.
    func pretend(role: Role, guestCount: Int = 0, ledger: SharePlayLedger = SharePlayLedger()) {
        self.role = role
        self.guestCount = guestCount
        self.ledger = ledger
        if role == .guest { showsGuestPage = true }
    }

    func pretendGuest(_ change: (inout SharePlayGuest) -> Void) {
        change(&guest)
    }
    #endif
}
