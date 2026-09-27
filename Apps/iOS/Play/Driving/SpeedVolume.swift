import CoreLocation
import MotifCore

/// Louder at Speed: while you drive, your own music comes up as the car speeds up and goes
/// back down as it slows, so it stays as loud as the road, as a car's own speed-sensitive
/// volume does.
///
/// It works on Motif's own player level, never the phone's volume: the loudest it goes is
/// the volume you set, reached at motorway speed, and it eases a few decibels under that when
/// stopped. Changes take a few seconds, so braking hard never makes the music drop. Apple Music
/// plays in the system's player, whose level apps can't change, so this is for your own music.
@MainActor
@Observable
final class SpeedVolume {
    static let shared = SpeedVolume()

    /// The car's speed, smoothed, in metres a second, while it's being followed.
    private(set) var speed: Double?
    private(set) var authorization: CLAuthorizationStatus

    /// The level when stopped: about 5 dB under the volume you set.
    static let quietest: Float = 0.56
    /// Full level from here up: 110 km/h.
    static let fullSpeed = 30.5

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var gliding: Task<Void, Never>?
    @ObservationIgnored private var session: CLServiceSession?
    @ObservationIgnored private var background: CLBackgroundActivitySession?
    @ObservationIgnored private var level: Float = 1

    private init() {
        authorization = manager.authorizationStatus
    }

    /// Follows the setting, the drive and the player from launch on.
    func start(_ model: AppModel) {
        guard watching == nil else { return }
        let player = model.player
        watching = Task { [weak self] in
            let wanted = Observations {
                PlayPreferences.volumeFollowsSpeed && player.drive.isDriving
                    && model.musicSource == .yourMusic && player.hasQueue
            }
            for await isWanted in wanted {
                self?.follow(isWanted, player: player)
            }
        }
    }

    /// Asks for location when the setting is turned on, while someone's looking at the phone,
    /// rather than on the road.
    func askForLocation() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
        Task {
            // The answer comes back through the system's sheet; look again once it's gone.
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                authorization = manager.authorizationStatus
                if authorization != .notDetermined { return }
            }
        }
    }

    func refreshAuthorization() {
        authorization = manager.authorizationStatus
    }

    private func follow(_ isWanted: Bool, player: PlayerModel) {
        if isWanted, following == nil {
            session = CLServiceSession(authorization: .whenInUse)
            // Keeps the updates coming with the phone locked in a pocket, for this drive only.
            background = CLBackgroundActivitySession()
            following = Task { [weak self] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                        guard let self, !Task.isCancelled else { return }
                        guard let location = update.location, location.speed >= 0,
                              location.speedAccuracy >= 0, location.speedAccuracy < 5 else { continue }
                        self.hear(location.speed, player: player)
                    }
                } catch {
                    return
                }
            }
        } else if !isWanted, following != nil {
            following?.cancel()
            following = nil
            session = nil
            background?.invalidate()
            background = nil
            speed = nil
            glide(to: 1, player: player)
        }
    }

    private func hear(_ metresPerSecond: Double, player: PlayerModel) {
        // Smoothed over several seconds: a hard stop at a light shouldn't make the music drop.
        let smoothed = speed.map { $0 + (metresPerSecond - $0) * 0.15 } ?? metresPerSecond
        speed = smoothed
        let share = min(1, smoothed / Self.fullSpeed)
        glide(to: Self.quietest + (1 - Self.quietest) * Float(pow(share, 0.8)), player: player)
    }

    /// Moves the level a little every tenth of a second, so no change is heard as a step.
    private func glide(to target: Float, player: PlayerModel) {
        gliding?.cancel()
        gliding = Task { [weak self] in
            while let self, !Task.isCancelled, abs(level - target) > 0.004 {
                level += max(-0.015, min(0.015, target - level))
                player.setLevel(level)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
