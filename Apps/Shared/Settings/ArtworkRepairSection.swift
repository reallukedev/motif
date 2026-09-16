import SwiftUI
import MotifCore

/// Finds covers that no longer load and fetches them again.
///
/// Covers go missing for two reasons: a `musicKit://` address MusicKit hands out for radio,
/// which nothing can load, and an Apple address that has since been taken down. Neither heals
/// on its own, because the backfill only fills rows that have no cover at all.
struct ArtworkRepairSection: View {
    @Environment(AppModel.self) private var model
    @State private var isRepairing = false
    @State private var report: ArtworkRepairReport?

    var body: some View {
        Section {
            Button(action: repair) {
                // An `HStack` rather than `LabeledContent`, which would style the row as a
                // read-out and lose the button's tint. The spinner sits where a disclosure
                // would, so the title doesn't move when it appears.
                HStack {
                    Text("Repair Artwork")
                    Spacer()
                    if isRepairing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(isRepairing || model.isShowingSampleData || model.capture == nil)

            if let report {
                Text(summary(report))
                    .font(.callout)
                    .foregroundStyle(report.foundNothingWrong ? .secondary : .primary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("Artwork")
        } footer: {
            Text("Checks every cover in your history and asks Apple Music again for the ones that no longer load. It leaves the covers that are fine alone, and can take a minute over a long history.")
        }
    }

    private func repair() {
        // The capture service, not the environment: the Mac's Settings window is its own
        // scene and only ever gets the model.
        guard let capture = model.capture else { return }
        isRepairing = true
        report = nil
        Task {
            let result = await capture.repairArtwork()
            // Artists Apple Music had no picture for are back in the queue now.
            model.library.refreshArtistArtwork()
            report = result
            isRepairing = false
        }
    }

    private func summary(_ report: ArtworkRepairReport) -> LocalizedStringKey {
        guard !report.foundNothingWrong else {
            return "Checked ^[\(report.checked) cover](inflect: true). They all load."
        }
        return "Replaced ^[\(report.restored) cover](inflect: true) of the ^[\(report.cleared) song](inflect: true) that had a broken one."
    }
}
