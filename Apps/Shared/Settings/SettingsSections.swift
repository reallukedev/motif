import SwiftUI
import WidgetKit
import AuthenticationServices
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
    private var scrobblesImported = false

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
            if connection.isConnected, scrobblesImported {
                Text("Recovered songs are scrobbled with the time Motif found them, because Apple's Recently Played list doesn't say when you played them.")
            } else {
                Text("Every song Motif keeps is scrobbled, radio included. Recovered songs are left out unless you turn them on, since their times are only approximate.")
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
    }
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
        } header: {
            Text("History")
        } footer: {
            #if os(iOS)
            Text("Motif only sees music while it's open. When it opens, it fills in what you played in the meantime from Apple Music's Recently Played, which doesn't say how or exactly when you played them.")
            #else
            Text("When Motif starts, it fills in what you played while it was closed from Apple Music's Recently Played, which doesn't say how or exactly when you played them.")
            #endif
        }
    }
}

/// The radio playlist and the rule for spotting radio.
struct RadioPlaylistSection: View {
    private let settings = CaptureSettings()
    @State private var playlistName = ""
    @State private var autoAdd = CaptureSettings().autoAddToPlaylist
    @State private var forceCapture = CaptureSettings().forceCapture

    var body: some View {
        Section {
            TextField("Playlist Name", text: $playlistName, prompt: Text(CaptureSettings.defaultPlaylistName))
                .onSubmit(save)
            Toggle("Add Radio Songs Automatically", isOn: $autoAdd)
                .onChange(of: autoAdd) { _, value in settings.autoAddToPlaylist = value }
            Toggle("Treat Everything as Radio", isOn: $forceCapture)
                .onChange(of: forceCapture) { _, value in settings.forceCapture = value }
        } header: {
            Text("Radio Playlist")
        } footer: {
            Text("Songs you hear on Apple Music radio are added to this playlist in your library. Turn on Treat Everything as Radio if Motif ever misses a station.")
        }
        .onAppear { playlistName = settings.playlistName }
        .onDisappear(perform: save)
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

/// Version, links, and the sample data switch.
struct AboutSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            if !model.isDemoLaunch {
                Toggle("Show Sample Data", isOn: Binding(
                    get: { model.sampleStore != nil },
                    set: { $0 ? model.showSampleData() : model.hideSampleData() }
                ))
            }
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
