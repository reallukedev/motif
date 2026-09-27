import SwiftUI

/// How Stage lays out the song.
enum StageLayout: String, CaseIterable, Identifiable {
    /// The cover large beside the song's name, as on a record sleeve.
    case cover
    /// The song's name set huge over the background, as on a gig poster.
    case poster
    /// The visualizer at the centre, the song's name small beneath it.
    case visualizer
    /// The time, large, with the song under it: for a nightstand or a desk.
    case clock

    var id: String { rawValue }
    static let storageKey = "stageLayout"

    var title: LocalizedStringKey {
        switch self {
        case .cover: "Cover"
        case .poster: "Poster"
        case .visualizer: "Visualizer"
        case .clock: "Clock"
        }
    }

    var symbol: String {
        switch self {
        case .cover: "square.and.line.vertical.and.square"
        case .poster: "textformat.size.larger"
        case .visualizer: "waveform"
        case .clock: "clock"
        }
    }
}

/// How the visualizer draws the sound.
enum StageVisualizer: String, CaseIterable, Identifiable {
    case bars, wave, orb, off

    var id: String { rawValue }
    static let storageKey = "stageVisualizer"

    var title: LocalizedStringKey {
        switch self {
        case .bars: "Bars"
        case .wave: "Wave"
        case .orb: "Orb"
        case .off: "Off"
        }
    }
}

/// Which way up Stage is on iPhone. Landscape by default: Stage is for a screen propped on
/// its side on a desk or a dock, and turns even with Rotation Lock on, as a video does.
enum StageOrientation: String, CaseIterable, Identifiable {
    case landscape, automatic, portrait

    var id: String { rawValue }
    static let storageKey = "stageOrientation"

    static var current: StageOrientation {
        UserDefaults.standard.string(forKey: storageKey).flatMap(StageOrientation.init) ?? .landscape
    }

    var title: LocalizedStringKey {
        switch self {
        case .landscape: "Landscape"
        case .automatic: "Automatic"
        case .portrait: "Portrait"
        }
    }

    #if os(iOS)
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .landscape: .landscape
        case .automatic: .allButUpsideDown
        case .portrait: .portrait
        }
    }
    #endif
}

/// Stage's other choices, as their stored keys.
enum StageOption {
    /// iPhone stays awake and bright while Stage is up. On by default.
    static let keepsScreenOn = "stageKeepsScreenOn"
    /// How many times the hint about the controls has shown, to stop after a few.
    static let hintsShown = "stageHintsShown"
    static let background = "stageBackground"
    static let showsAlbum = "stageShowsAlbum"
    static let showsProgress = "stageShowsProgress"
    static let showsNext = "stageShowsNext"
    static let showsClock = "stageShowsClock"
}

/// Whether Stage is up on iPhone, so it can be opened from Now Playing's menu, or at launch.
@Observable
final class StagePresenter {
    static let shared = StagePresenter()
    var isShowing = false
}

#if os(iOS)
extension StagePresenter {
    /// Which ways up the app may be: Stage's choice while it's up, and upright otherwise, as
    /// the rest of Motif is.
    var orientations: UIInterfaceOrientationMask {
        isShowing ? StageOrientation.current.mask : .portrait
    }

    /// Turns the screen to suit, after Stage opens, closes, or its choice changes.
    func updateOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        var controller = scene.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}
#endif
