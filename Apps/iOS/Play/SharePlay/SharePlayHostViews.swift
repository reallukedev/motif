import SwiftUI
import MotifCore

/// Starts SharePlay: the share sheet, where the people with you are a tap away in Messages or,
/// held close, over AirDrop. For Now Playing's menu, as Music has it.
struct SharePlayMenuItem: View {
    var body: some View {
        ShareLink(item: SharePlayActivity(), preview: SharePlayActivity.preview) {
            Label("SharePlay", systemImage: "shareplay")
        }
    }
}

/// SharePlay in Up Next's header: a button to start it, and while it's on, a glass pill with
/// how many people have joined, and a menu to invite more or end it.
struct SharePlayQueueControl: View {
    private var sharePlay = SharePlayController.shared

    var body: some View {
        if sharePlay.role == .host {
            Menu {
                Section(peopleLine) {
                    ShareLink(item: SharePlayActivity(), preview: SharePlayActivity.preview) {
                        Label("Invite More…", systemImage: "person.badge.plus")
                    }
                    Button("End SharePlay", systemImage: "xmark", role: .destructive) {
                        sharePlay.endHosting()
                    }
                }
            } label: {
                // On, it lights up as Up Next's other toggles do, and says how many joined.
                HStack(spacing: 5) {
                    Image(systemName: "shareplay")
                    if sharePlay.guestCount > 0 {
                        Text(sharePlay.guestCount, format: .number)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(sharePlay.guestCount)))
                    }
                }
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .frame(minWidth: 32, minHeight: 32)
                .background(.white, in: .capsule)
                .frame(minHeight: 44)
                .contentShape(.capsule)
                .animation(PlayMotion.value, value: sharePlay.guestCount)
            }
            .accessibilityLabel("SharePlay")
            .accessibilityValue(Text(peopleLine))
        } else {
            ShareLink(item: SharePlayActivity(), preview: SharePlayActivity.preview) {
                Image(systemName: "shareplay")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.15), in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .accessibilityLabel("SharePlay")
            .accessibilityHint("Lets the people with you add songs to Up Next from their iPhones")
        }
    }

    private var peopleLine: String {
        switch sharePlay.guestCount {
        case 0: String(localized: "Waiting for People to Join")
        case 1: String(localized: "1 Person Joined")
        case let count: String(localized: "\(count) People Joined")
        }
    }
}

extension View {
    /// Marks a row of Up Next someone at SharePlay added, with SharePlay's glyph at its
    /// trailing edge.
    func sharePlayMark(_ track: PlayerTrack) -> some View {
        modifier(SharePlayMark(track: track))
    }
}

private struct SharePlayMark: ViewModifier {
    let track: PlayerTrack
    private var sharePlay = SharePlayController.shared

    init(track: PlayerTrack) {
        self.track = track
    }

    func body(content: Content) -> some View {
        let isMarked = sharePlay.isFromSharePlay(track)
        // Room made at the end of the row, so a long title stops short of the glyph.
        content
            .padding(.trailing, isMarked ? 28 : 0)
            .overlay(alignment: .trailing) {
                if isMarked {
                    Image(systemName: "shareplay")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(isMarked ? Text("Added by SharePlay") : Text(""))
    }
}
