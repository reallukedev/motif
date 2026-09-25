import SwiftUI
import MotifCore

// Your devices as one player, as Spotify Connect makes them: what each is playing, a remote for
// any of them, and a tap to move the music from one to another, over Motif's own connection
// between your devices on the same network and iCloud account.

/// The button for your devices: the Mac's window toolbar, and Play's on iPhone. While another
/// device plays, it says which, with the music moving in it.
struct DevicesButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingPanel = LaunchScene.opensDevices

    var body: some View {
        let playing = model.nearby.devices.first { $0.state?.isPlaying == true }
        Button {
            isShowingPanel = true
        } label: {
            if let playing {
                HStack(spacing: 6) {
                    Image(systemName: NearbyDevices.symbol(for: playing.platform))
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                }
                .foregroundStyle(.tint)
            } else {
                Image(systemName: "laptopcomputer.and.iphone")
            }
        }
        .help(playing.map { "Playing on \($0.name)" } ?? "Your Devices")
        .accessibilityLabel(playing.map { Text("Your Devices, playing on \($0.name)") } ?? Text("Your Devices"))
        #if os(macOS)
        .popover(isPresented: $isShowingPanel, arrowEdge: .bottom) {
            DevicesPanel { isShowingPanel = false }
                .frame(width: 360)
        }
        #else
        .sheet(isPresented: $isShowingPanel) {
            NavigationStack {
                ScrollView {
                    DevicesPanel { isShowingPanel = false }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .navigationTitle("Your Devices")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPanel = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
    }
}

/// Where the music is and where it can go: a remote for the device playing, then every device,
/// this one first. Choosing one moves the music there.
struct DevicesPanel: View {
    /// Closes the popover or sheet it's in.
    let close: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let device = featured {
                RemoteDeviceCard(device: device, close: close)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your Devices")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ThisDeviceRow(isListening: model.controlledDevice == nil && player.hasQueue) {
                        if let device = model.controlledDevice, device.state?.hasSong == true {
                            // Back here, with the song from there.
                            Task { _ = await model.playHere(from: device) }
                        }
                        model.control(nil)
                    }
                    ForEach(model.nearby.devices) { device in
                        Divider().padding(.leading, 50)
                        DeviceRow(device: device, isListening: model.controlledDevice?.id == device.id) {
                            choose(device)
                        }
                    }
                }
                .background(Color.cardFill, in: .rect(cornerRadius: 14, style: .continuous))
                footer
            }
        }
        .padding(.top, platformTop)
        .padding(.horizontal, platformInset)
        .padding(.bottom, platformInset)
        .animation(.snappy, value: model.nearby.devices.map(\.id))
    }

    #if os(macOS)
    private let platformTop: CGFloat = 16
    private let platformInset: CGFloat = 16
    #else
    private let platformTop: CGFloat = 8
    private let platformInset: CGFloat = 0
    #endif

    /// The device whose remote leads: the one the player's showing, or else the first playing,
    /// or the first with a song.
    private var featured: NearbyDevices.Device? {
        model.controlledDevice
            ?? model.nearby.withSongs.first
    }

    /// A device chosen: the music goes there if it's playing here; otherwise the player shows
    /// what's playing there, to control from here.
    private func choose(_ device: NearbyDevices.Device) {
        if player.hasQueue, model.controlledDevice == nil {
            model.sendMusic(to: device)
        } else if device.state?.hasSong == true {
            model.control(device)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.nearby.needsLocalNetwork {
            Label("Motif can't see your other devices until Local Network is on for it in Settings, under Privacy & Security.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if model.nearby.devices.isEmpty {
            Text("Open Motif on your iPhone, iPad or Mac, on the same Wi-Fi and signed in to the same iCloud account, and it shows up here. Choose one to play there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Choose a device to play there. Songs pick up where they were.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// This device, first in the list.
private struct ThisDeviceRow: View {
    let isListening: Bool
    let choose: () -> Void
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                DeviceSymbol(systemImage: NearbyDevices.thisDeviceSymbol, isListening: isListening)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.name)
                        .font(.body.weight(isListening ? .semibold : .regular))
                    Text(player.current.map { "\($0.title) · \($0.artistName)" } ?? String(localized: "Not Playing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isListening {
                    ListeningMark(isPlaying: player.isPlaying)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isListening ? .isSelected : [])
    }

    private static var name: String {
        #if os(macOS)
        String(localized: "This Mac")
        #else
        String(localized: "This iPhone")
        #endif
    }
}

/// Another of your devices, and what it's playing.
private struct DeviceRow: View {
    let device: NearbyDevices.Device
    let isListening: Bool
    let choose: () -> Void

    var body: some View {
        let state = device.state
        Button(action: choose) {
            HStack(spacing: 12) {
                DeviceSymbol(systemImage: NearbyDevices.symbol(for: device.platform), isListening: isListening || state?.isPlaying == true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.body.weight(isListening ? .semibold : .regular))
                        .lineLimit(1)
                    Text(line(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isListening || state?.isPlaying == true {
                    ListeningMark(isPlaying: state?.isPlaying == true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isListening ? .isSelected : [])
    }

    private func line(_ state: NearbyState?) -> String {
        guard let state, state.hasSong else { return String(localized: "Not Playing") }
        let song = [state.title, state.artist].compactMap(\.self).joined(separator: " · ")
        return state.isPlaying ? song : String(localized: "Paused · \(song)")
    }
}

private struct DeviceSymbol: View {
    let systemImage: String
    let isListening: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.medium))
            .foregroundStyle(isListening ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 30, height: 30)
            .background(isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
    }
}

/// The music's here: the tint's waveform, moving while it plays.
private struct ListeningMark: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .foregroundStyle(.tint)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying && !reduceMotion)
            .accessibilityHidden(true)
    }
}

// MARK: - A remote for another device

/// Another device's song as a small Now Playing: its cover blurred behind it, where it's
/// playing, the song, a scrubber to move it, its controls, and the way to bring it here or show
/// it in the player.
struct RemoteDeviceCard: View {
    let device: NearbyDevices.Device
    var close: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMoving = false
    @State private var couldNotMove = false
    @State private var tint: Color?

    var body: some View {
        let state = device.state ?? NearbyState()
        let cover = CoverArt.url(state.artworkURL, seed: state.album ?? state.title ?? device.name)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(device.name, systemImage: NearbyDevices.symbol(for: device.platform))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 24)
                    .background(.white.opacity(0.16), in: .capsule)
                Spacer(minLength: 0)
                Text(state.isPlaying ? "Playing" : "Paused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 12) {
                CoverImage(cover: cover, size: 56)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            RemoteScrubber(device: device, state: state)
            RemoteTransport(device: device, state: state, size: .large)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                #if os(macOS)
                if model.controlledDevice?.id != device.id {
                    Button {
                        model.control(device)
                        close?()
                    } label: {
                        Label("Show in Player", systemImage: "rectangle.bottomhalf.inset.filled")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(.white.opacity(0.18), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                }
                #endif
                Button {
                    Task {
                        isMoving = true
                        couldNotMove = !(await model.playHere(from: device))
                        isMoving = false
                        if !couldNotMove { close?() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isMoving {
                            ProgressView().controlSize(.small).tint(.black)
                        } else {
                            Image(systemName: couldNotMove ? "exclamationmark.circle" : NearbyDevices.thisDeviceSymbol)
                        }
                        Text(couldNotMove ? "Couldn't Find It Here" : here)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 30)
                    .frame(maxWidth: .infinity)
                    .background(.white, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .disabled(isMoving)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            ZStack {
                (tint ?? CoverStage.fallback)
                CoverImage(cover: cover, size: 300, isBare: true)
                    .scaleEffect(2.2)
                    .blur(radius: 36)
                    .saturation(1.3)
                    .opacity(0.9)
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .coverTint(of: cover, into: $tint)
        .animation(reduceMotion ? nil : .snappy, value: state.title)
        .sensoryFeedback(.success, trigger: isMoving) { was, now in was && !now && !couldNotMove }
    }

    private var here: LocalizedStringKey {
        #if os(macOS)
        "Play on This Mac"
        #else
        "Play on This iPhone"
        #endif
    }
}

/// Back, play or pause, and next, for another device.
struct RemoteTransport: View {
    enum Size { case compact, large }

    let device: NearbyDevices.Device
    let state: NearbyState
    var size = Size.compact
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: size == .large ? 26 : 4) {
            button("Previous", "backward.fill", .previous, diameter: small)
                .disabled(!state.canSkipBack)
            button(state.isPlaying ? "Pause" : "Play", state.isPlaying ? "pause.fill" : "play.fill", .playPause, diameter: big)
            button("Next", "forward.fill", .next, diameter: small)
                .disabled(!state.canSkipForward)
        }
    }

    private var small: CGFloat { size == .large ? 36 : 30 }
    private var big: CGFloat { size == .large ? 46 : 36 }

    private func button(_ title: LocalizedStringKey, _ symbol: String, _ command: TransportCommand, diameter: CGFloat) -> some View {
        Button {
            model.nearby.send(command, to: device)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

/// How far another device is into its song, to drag to a new place.
struct RemoteScrubber: View {
    let device: NearbyDevices.Device
    let state: NearbyState
    var showsTimes = true
    @Environment(AppModel.self) private var model
    @State private var dragFraction: Double?

    var body: some View {
        if let duration = state.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let live = min(1, max(0, (state.position(at: context.date) ?? 0) / duration))
                let fraction = dragFraction ?? live
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.18))
                            Capsule()
                                .fill(.primary.opacity(dragFraction == nil ? 0.8 : 1))
                                .frame(width: max(0, proxy.size.width * fraction))
                        }
                        .frame(height: dragFraction == nil ? 4 : 7)
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragFraction = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                                }
                                .onEnded { _ in
                                    if let dragFraction { model.nearby.seek(device, to: dragFraction * duration) }
                                    dragFraction = nil
                                }
                        )
                        .animation(.easeOut(duration: 0.13), value: dragFraction == nil)
                    }
                    .frame(height: 14)
                    if showsTimes {
                        HStack {
                            Text(verbatim: Scrubber.format(fraction * duration))
                            Spacer()
                            Text(verbatim: "-" + Scrubber.format(max(0, duration - fraction * duration)))
                        }
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Position")
                .accessibilityValue(Text("\(Scrubber.format(fraction * duration)) of \(Scrubber.format(duration))"))
                .accessibilityAdjustableAction { direction in
                    let step: TimeInterval = direction == .increment ? 15 : -15
                    model.nearby.seek(device, to: min(duration, max(0, fraction * duration + step)))
                }
            }
        }
    }
}

#if os(iOS)
/// The mini player while it's another device's song on show: the song, where it's playing,
/// and its play button. Tapping it opens Your Devices.
struct RemoteMiniPlayer: View {
    let device: NearbyDevices.Device
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var isShowingPanel = false

    var body: some View {
        let state = device.state ?? NearbyState()
        HStack(spacing: 10) {
            Button {
                isShowingPanel = true
            } label: {
                HStack(spacing: 10) {
                    CoverImage(cover: .url(state.artworkURL, seed: state.album ?? state.title ?? device.name), size: placement == .inline ? 26 : 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.title ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if placement != .inline {
                            Label(device.name, systemImage: NearbyDevices.symbol(for: device.platform))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(state.title ?? ""), playing on \(device.name)"))
            .accessibilityHint("Shows Your Devices")
            RemoteTransport(device: device, state: state)
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $isShowingPanel) {
            NavigationStack {
                ScrollView {
                    DevicesPanel { isShowingPanel = false }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                .navigationTitle("Your Devices")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingPanel = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
#endif
