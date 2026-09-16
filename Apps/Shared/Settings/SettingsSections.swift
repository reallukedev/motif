import SwiftUI
import WidgetKit
import AuthenticationServices
import MusicKit
import MotifCore
#if os(macOS)
import AppKit
#endif

// The pieces of Settings. The iPhone shows them in one sheet and the Mac spreads them over
// the tabs of its Settings window, so each section stands on its own.

/// Connecting a Last.fm account, and what gets sent.
struct LastFMSection: View {
    @State private var connection = LastFMConnection()
    @Environment(\.webAuthenticationSession) private var webAuthentication
    @AppStorage(CaptureSettings.scrobblesToLastFMKey, store: CaptureSettings.sharedDefaults)
    private var scrobbles = true
    @AppStorage(CaptureSettings.scrobblesImportedKey, store: CaptureSettings.sharedDefaults)
    private var scrobblesImported = true

    var body: some View {
        Section {
            switch connection.state {
            case .connected(let username):
                LabeledContent("Account") {
                    Label(username, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                }
                Toggle("Scrobble What You Play", isOn: $scrobbles)
                Toggle("Include Recovered Songs", isOn: $scrobblesImported)
                Button("Disconnect", role: .destructive) { connection.disconnect() }

            case .waitingForBrowser:
                LabeledContent("Account") {
                    ProgressView().controlSize(.small)
                }
                Text("Approve Motif on Last.fm, then come back here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .failed(let message):
                connectButton
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)

            case .idle:
                connectButton
            }
        } header: {
            Text("Last.fm")
        } footer: {
            // On the setting, not on being connected: before you connect, the footer should
            // still describe what will happen, and recovered songs are included by default.
            if scrobblesImported {
                Text("Every song Motif keeps is scrobbled, radio and recovered songs included. Recovered songs are scrobbled with the time Motif found them, because Apple's Recently Played list doesn't say when you played them.")
            } else {
                Text("Every song Motif keeps is scrobbled, radio included. Songs recovered from Recently Played are left out, so nothing reaches Last.fm with an approximate time.")
            }
        }
    }

    private var isIOS: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var connectButton: some View {
        Button("Connect to Last.fm") {
            connection.connect(waitsForPage: isIOS) { url in
                #if os(iOS)
                // Last.fm doesn't redirect back after approval, so this returns when the
                // person closes the sheet (or when we cancel it after the poll succeeds).
                _ = try? await webAuthentication.authenticate(
                    using: url,
                    callbackURLScheme: "motif",
                    preferredBrowserSession: .shared
                )
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }
}

extension LastFMSessionStore {
    /// The defaults key holding the connected username, in `CaptureSettings.sharedDefaults`.
    /// The same string as MotifCore's internal `usernameKey`, which can't be renamed without
    /// signing everyone out.
    ///
    /// Views watch it with `@AppStorage` to follow connecting and disconnecting. Saving and
    /// clearing a session write it after the Keychain, so when it changes, ``current`` is
    /// already up to date.
    static let usernameDefaultsKey = "MotifLastFMUsername"
}

/// How long a song has to play to count, and how close together two plays can be.
struct ListeningRulesSection: View {
    private let settings = CaptureSettings()
    @State private var dedupeMinutes: Double = 10
    @State private var minimumListen: Double = 30

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                LabeledContent("Counts After") {
                    Text(minimumListen == 0 ? "Straight Away" : "^[\(Int(minimumListen)) second](inflect: true)")
                        .monospacedDigit()
                }
                Slider(value: $minimumListen, in: 0...120, step: 5) {
                    Text("Counts After")
                } minimumValueLabel: {
                    Text("0s")
                } maximumValueLabel: {
                    Text("2m")
                }
                .labelsHidden()
                .accessibilityValue(minimumListen == 0 ? "Straight away" : "\(Int(minimumListen)) seconds")
            }
            VStack(alignment: .leading) {
                LabeledContent("Same Song Again Within") {
                    Text("^[\(Int(dedupeMinutes)) minute](inflect: true)")
                        .monospacedDigit()
                }
                Slider(value: $dedupeMinutes, in: 1...60, step: 1) {
                    Text("Same Song Again Within")
                } minimumValueLabel: {
                    Text("1m")
                } maximumValueLabel: {
                    Text("60m")
                }
                .labelsHidden()
                .accessibilityValue("\(Int(dedupeMinutes)) minutes")
            }
        } header: {
            Text("Counting Plays")
        } footer: {
            Text("A song has to play for a little while before it's kept, so skipping through doesn't fill your history. Hearing the same song again inside the window counts once.")
        }
        .onAppear {
            dedupeMinutes = settings.dedupePolicy.window / 60
            minimumListen = settings.minimumListenSeconds
        }
        .onChange(of: dedupeMinutes) { _, minutes in
            settings.setDedupeWindow(seconds: minutes * 60)
        }
        .onChange(of: minimumListen) { _, seconds in
            settings.minimumListenSeconds = seconds
        }
        .onSettingsChangedRemotely {
            dedupeMinutes = settings.dedupePolicy.window / 60
            minimumListen = settings.minimumListenSeconds
        }
    }
}

/// Apple Music access: what it's for, and asking for it or turning it back on.
struct AppleMusicAccessSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false

    var body: some View {
        Section {
            LabeledContent("Access", value: statusText)
            switch model.musicAuthorization {
            case .authorized:
                EmptyView()
            case .notDetermined:
                Button("Allow Apple Music Access") {
                    isRequesting = true
                    Task {
                        await model.requestMusicAccess()
                        isRequesting = false
                    }
                }
                .disabled(isRequesting || model.isShowingSampleData)
            default:
                Button(openSettingsTitle) {
                    if let url = settingsURL { openURL(url) }
                }
            }
        } header: {
            Text("Apple Music")
        } footer: {
            Text("Motif keeps what you play either way. Access lets it fill in songs from Recently Played, find artwork, and add radio songs to your playlist.")
        }
        .onAppear(perform: model.refreshMusicAuthorization)
    }

    private var statusText: String {
        switch model.musicAuthorization {
        case .authorized: String(localized: "Allowed")
        case .denied: String(localized: "Off")
        case .restricted: String(localized: "Restricted")
        default: String(localized: "Not Asked Yet")
        }
    }

    #if os(iOS)
    private var openSettingsTitle: LocalizedStringKey { "Open Settings" }
    private var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }
    #else
    private var openSettingsTitle: LocalizedStringKey { "Open System Settings" }
    /// Privacy & Security › Media & Apple Music.
    private var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")
    }
    #endif
}

/// What gets kept besides radio.
struct HistorySourcesSection: View {
    @State private var capturesOnDemand = CaptureSettings().capturesOnDemand
    @State private var importsRecentlyPlayed = CaptureSettings().importsRecentlyPlayed

    var body: some View {
        Section {
            Toggle("Keep Songs Played on Demand", isOn: $capturesOnDemand)
                .onChange(of: capturesOnDemand) { _, value in CaptureSettings().capturesOnDemand = value }
            Toggle("Recover from Recently Played", isOn: $importsRecentlyPlayed)
                .onChange(of: importsRecentlyPlayed) { _, value in CaptureSettings().importsRecentlyPlayed = value }
            #if os(iOS)
            BackgroundRefreshNotice()
            #endif
        } header: {
            Text("History")
        } footer: {
            #if os(iOS)
            Text("Motif only sees music while it's open. The rest comes from Apple Music's Recently Played, which doesn't say how or exactly when you played them. Motif checks it whenever it opens, and now and then in the background, unless you swipe it away in the app switcher.")
            #else
            Text("When Motif starts, it fills in what you played while it was closed from Apple Music's Recently Played, which doesn't say how or exactly when you played them.")
            #endif
        }
        .onSettingsChangedRemotely {
            capturesOnDemand = CaptureSettings().capturesOnDemand
            importsRecentlyPlayed = CaptureSettings().importsRecentlyPlayed
        }
    }
}

/// The radio playlist and the rule for spotting radio.
struct RadioPlaylistSection: View {
    private let settings = CaptureSettings()
    @State private var playlistName = ""
    @State private var autoAdd = CaptureSettings().autoAddToPlaylist
    @State private var forceCapture = CaptureSettings().forceCapture
    @State private var limitsSize = CaptureSettings().limitsPlaylistSize
    @State private var sizeLimit = CaptureSettings().playlistSizeLimit

    var body: some View {
        Section {
            TextField("Playlist Name", text: $playlistName, prompt: Text(CaptureSettings.defaultPlaylistName))
                .onSubmit(save)
            Toggle("Add Radio Songs Automatically", isOn: $autoAdd)
                .onChange(of: autoAdd) { _, value in settings.autoAddToPlaylist = value }
            if autoAdd {
                Toggle("Limit Playlist Size", isOn: $limitsSize)
                    .onChange(of: limitsSize) { _, value in settings.limitsPlaylistSize = value }
                if limitsSize {
                    Stepper(
                        value: $sizeLimit,
                        in: PlaylistSizeLimit.allowed,
                        step: PlaylistSizeLimit.step
                    ) {
                        LabeledContent("Most Songs") {
                            Text(sizeLimit.formatted())
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(sizeLimit)))
                        }
                    }
                    .accessibilityValue("^[\(sizeLimit) song](inflect: true)")
                    .onChange(of: sizeLimit) { _, value in settings.playlistSizeLimit = value }
                }
            }
            Toggle("Treat Everything as Radio", isOn: $forceCapture)
                .onChange(of: forceCapture) { _, value in settings.forceCapture = value }
        } header: {
            Text("Radio Playlist")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Songs you hear on Apple Music radio are added to this playlist in your library. Turn on Treat Everything as Radio if Motif ever misses a station.")
                if autoAdd, limitsSize {
                    Text("Motif stops adding once the playlist holds \(sizeLimit.formatted()) songs. Apple Music has no way to take a track back out, so make room by deleting songs from the playlist yourself; the songs that were waiting go in next time.\(fullness)")
                }
            }
        }
        .animation(.default, value: autoAdd)
        .animation(.default, value: limitsSize)
        .onAppear { playlistName = settings.playlistName }
        .onDisappear(perform: save)
        .onSettingsChangedRemotely {
            // `forceCapture` is deliberately left out: it's a diagnostic override that
            // belongs to the machine it's switched on, so it doesn't mirror.
            playlistName = settings.playlistName
            autoAdd = settings.autoAddToPlaylist
            limitsSize = settings.limitsPlaylistSize
            sizeLimit = settings.playlistSizeLimit
        }
    }

    /// " It holds 128 right now." once something has counted the playlist. Nothing before
    /// then, rather than a zero that would read as an empty playlist.
    private var fullness: String {
        guard let count = settings.playlistTrackCount else { return "" }
        return " It holds \(count.formatted()) right now."
    }

    private func save() {
        // Blank means "use the default"; a single space once got saved and Music could
        // never find a playlist called " ".
        let trimmed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.playlistName = trimmed
    }
}

/// Play Back, which replays radio songs so Apple counts them.
struct PlayBackSection: View {
    @State private var autoPlayBack = CaptureSettings().autoPlayBack

    var body: some View {
        Section {
            Toggle("Play Back Automatically", isOn: $autoPlayBack)
                .onChange(of: autoPlayBack) { _, value in CaptureSettings().autoPlayBack = value }
                .onSettingsChangedRemotely { autoPlayBack = CaptureSettings().autoPlayBack }
        } header: {
            Text("Play Back")
        } footer: {
            Text("Apple Music doesn't count radio as plays, so those songs never reach your play counts, Replay or recommendations. A couple of minutes after a station stops, Motif can play them again so they do. It only starts when you're at your Mac, and never over music you chose.")
        }
    }
}

/// What the Today widget shows.
struct WidgetSection: View {
    @AppStorage(CaptureSettings.showsUpNextInWidgetKey, store: CaptureSettings.sharedDefaults)
    private var showsUpNext = true

    var body: some View {
        Section {
            Toggle("Show Up Next", isOn: $showsUpNext)
                .onChange(of: showsUpNext) {
                    // Otherwise the widget waits for its next scheduled refresh.
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.today)
                }
        } header: {
            Text("Widgets")
        } footer: {
            Text("The Today widget can list the radio songs Play Back will play next.")
        }
    }
}

/// Version and links.
struct AboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            Link(destination: URL(string: "https://github.com/reallukedev/motif")!) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: URL(string: "https://github.com/reallukedev/motif/blob/main/PRIVACY.md")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://github.com/reallukedev/motif/issues")!) {
                Label("Report a Problem", systemImage: "exclamationmark.bubble")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Motif has no servers and no analytics. Your history stays on your devices and in your iCloud account.")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
