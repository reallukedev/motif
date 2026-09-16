import SwiftUI

/// How strongly to tint a cell or wedge for how much was played there, shared by the Listening
/// Clock and the heat map so the two agree.
enum ListeningIntensity {
    /// From a floor for the quietest hour that had any listening up to full strength at the
    /// peak. With Increase Contrast the floor rises, since the faintest tints are the first to
    /// disappear into the background.
    static func opacity(_ fraction: Double, contrast: ColorSchemeContrast) -> Double {
        let floor = contrast == .increased ? 0.5 : 0.3
        return floor + (1 - floor) * min(max(fraction, 0), 1)
    }
}
