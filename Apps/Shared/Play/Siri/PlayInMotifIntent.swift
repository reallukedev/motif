import AppIntents
import MusicKit
import MotifCore

/// What Siri and Shortcuts can start in Motif by name.
enum PlayChoice: String, AppEnum {
    case station
    case forYou
    case discover
    case onRepeat
    case favorites
    case deepCuts
    case radioFinds
    case radio
    case feelGood, energy, workout, focus, chill, love, drive, party, sleep, heartbreak

    /// The mood this choice is, if it's one.
    var mood: Mood? {
        switch self {
        case .feelGood: .feelGood
        case .energy: .energy
        case .workout: .workout
        case .focus: .focus
        case .chill: .chill
        case .love: .love
        case .drive: .drive
        case .heartbreak: .heartbreak
        case .party: .party
        case .sleep: .sleep
        default: nil
        }
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Music"

    static let caseDisplayRepresentations: [PlayChoice: DisplayRepresentation] = [
        .station: DisplayRepresentation(title: "Motif Radio", subtitle: "Your station, picked as it plays", image: .init(systemName: "dot.radiowaves.left.and.right")),
        .forYou: DisplayRepresentation(title: "My Mix", subtitle: "What you play at this time of day", image: .init(systemName: "sun.max")),
        .discover: DisplayRepresentation(title: "Discover", subtitle: "Songs you haven't heard by artists you love", image: .init(systemName: "binoculars")),
        .onRepeat: DisplayRepresentation(title: "On Repeat", image: .init(systemName: "repeat")),
        .favorites: DisplayRepresentation(title: "All-Time Favorites", image: .init(systemName: "heart")),
        .deepCuts: DisplayRepresentation(title: "Deep Cuts", image: .init(systemName: "square.stack.3d.down.right")),
        .radioFinds: DisplayRepresentation(title: "Radio Finds", image: .init(systemName: "dot.radiowaves.left.and.right")),
        .radio: DisplayRepresentation(title: "The Radio", subtitle: "Apple Music 1, live", image: .init(systemName: "antenna.radiowaves.left.and.right")),
        .feelGood: DisplayRepresentation(title: "Feel Good", image: .init(systemName: "sun.max.fill")),
        .energy: DisplayRepresentation(title: "Energy", image: .init(systemName: "bolt.fill")),
        .workout: DisplayRepresentation(title: "Workout", image: .init(systemName: "figure.run")),
        .focus: DisplayRepresentation(title: "Focus", image: .init(systemName: "scope")),
        .chill: DisplayRepresentation(title: "Chill", image: .init(systemName: "leaf.fill")),
        .love: DisplayRepresentation(title: "Love Songs", image: .init(systemName: "heart.fill")),
        .drive: DisplayRepresentation(title: "Drive", image: .init(systemName: "car.fill")),
        .heartbreak: DisplayRepresentation(title: "Heartbreak", image: .init(systemName: "heart.slash.fill")),
        .party: DisplayRepresentation(title: "Party", image: .init(systemName: "party.popper.fill")),
        .sleep: DisplayRepresentation(title: "Sleep", image: .init(systemName: "moon.stars.fill")),
    ]
}

/// "Play music in Motif", "Play my mix in Motif", "Play Discover in Motif".
///
/// An audio playback intent, so it can start the music without bringing Motif forward, and
/// returns only once the music has started, or says why it couldn't.
struct PlayInMotifIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play in Motif"
    static let description = IntentDescription(
        "Plays one of Motif's mixes, Motif Radio, Discover or live radio, and keeps every song you hear.",
        categoryName: "Playback"
    )

    @Parameter(title: "Music", default: .station)
    var choice: PlayChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$choice) in Motif")
    }

    init() {}

    init(choice: PlayChoice) {
        self.choice = choice
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        guard !model.isDemoLaunch else { throw PlayIntentError.sampleData }
        // Siri runs this with no one looking at the phone, so a permission prompt would sit
        // there unanswered. Say what's needed instead.
        guard model.musicSource == .yourMusic || MusicAuthorization.currentStatus == .authorized else {
            throw PlayIntentError.problem(PlayerProblem.accessDenied.message)
        }
        await model.prepareForPlaying()
        await MotifPlayback.start(choice, model: model)
        if let problem = model.player.problem {
            // Answered here, so it isn't shown again the next time the app opens.
            model.player.problem = nil
            throw PlayIntentError.problem(problem.message)
        }
        return .result()
    }
}

/// Starting a Play choice, for Siri, Shortcuts and CarPlay alike.
@MainActor
enum MotifPlayback {
    static func start(_ choice: PlayChoice, model: AppModel) async {
        let player = model.player
        let feed = model.playFeed

        func mix(_ kind: (MixKind) -> Bool) -> Mix? {
            feed.mixes.all.first { kind($0.kind) }
        }

        func playMix(_ mix: Mix?) async {
            guard let mix else {
                // No mix of that kind yet: the station always has something.
                if PlayPreferences.isMotifRadioOn {
                    await player.startMotifRadio()
                } else {
                    player.problem = .failed(String(localized: "Play a few more songs, and Motif will have a mix for you."))
                }
                return
            }
            await player.start(.history(player.songs(in: mix)), from: PlayContext(kind: .mix, title: mix.kind.title))
        }

        if let mood = choice.mood {
            await MoodPlayback.start(mood, model: model)
            return
        }

        switch choice {
        case .station where !PlayPreferences.isMotifRadioOn:
            // With Motif Radio off, "Play music in Motif" still plays something of yours.
            await playMix(feed.mixes.rightNow ?? feed.mixes.mixes.first)
        case .station:
            await player.startMotifRadio()
        case .forYou:
            await playMix(feed.mixes.rightNow ?? feed.mixes.mixes.first)
        case .onRepeat:
            await playMix(mix { $0 == .onRepeat })
        case .favorites:
            await playMix(mix { $0 == .allTimeFavorites })
        case .deepCuts:
            await playMix(mix { $0 == .deepCuts })
        case .radioFinds:
            await playMix(mix { $0 == .radioFinds })
        case .discover:
            await feed.loadFromYourArtists()
            guard !feed.discover.isEmpty else {
                if PlayPreferences.isMotifRadioOn {
                    await player.startMotifRadio()
                } else {
                    player.problem = .failed(String(localized: "Motif has nothing new to suggest yet. Play a few more songs, and it will."))
                }
                return
            }
            await player.start(.songs(feed.discover), from: PlayContext(kind: .mix, title: String(localized: "Discover")), shuffled: true)
        case .radio:
            await feed.loadAppleMusic()
            guard let (request, context) = feed.liveStations.first?.stationRequest else {
                player.problem = .failed(String(localized: "Couldn't reach Apple Music's radio."))
                return
            }
            await player.start(request, from: context)
        case .feelGood, .energy, .workout, .focus, .chill, .love, .drive, .party, .sleep, .heartbreak:
            // Handled above, as moods.
            break
        }
    }
}

enum PlayIntentError: Error, CustomLocalizedStringResourceConvertible {
    case sampleData
    case problem(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .sampleData: "Motif is showing sample data, so it can't play."
        case .problem(let message): "\(message)"
        }
    }
}
