import SwiftUI
import GroupActivities
import CoreTransferable

/// Motif's SharePlay: one iPhone keeps playing, and everyone who joins picks songs for its
/// queue from their own Motif.
///
/// Apple Music's own "SharePlay in the car" belongs to the Music app, and MusicKit's player
/// has no group session of its own, so this is Motif's, and passengers need Motif too. It
/// starts from the share sheet: sent in Messages, or offered to iPhones held close by over
/// AirDrop, which starts a Messages conversation for the group. No FaceTime call is needed.
///
/// The activity carries nothing: the session knows which iPhone started it, and that one is
/// the host.
nonisolated struct SharePlayActivity: GroupActivity, Transferable {
    static let activityIdentifier = "dev.luke.motif.add-songs"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .listenTogether
        metadata.title = String(localized: "Add Songs Together")
        metadata.subtitle = String(localized: "Pick songs for what's playing on this iPhone.")
        // The queue is the host's. Once it leaves, there's nothing to add to.
        metadata.lifetimePolicy = .endsWhenInitiatorLeaves
        return metadata
    }
}

extension SharePlayActivity {
    /// What the share sheet shows above its choices.
    static var preview: SharePreview<Never, Never> {
        SharePreview(String(localized: "Add Songs Together"))
    }
}
