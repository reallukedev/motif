import SwiftUI
import ServiceManagement
import MotifCore

/// The Settings window (⌘,), split into the usual toolbar tabs.
struct MacSettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                SettingsPane {
                    MacBehaviourSection()
                    AppleMusicAccessSection()
                    HistorySourcesSection()
                    ArtworkRepairSection()
                    if let store = model.store, !model.isDemoLaunch {
                        CloudSyncSection(store: store, monitor: model.syncMonitor)
                    }
                    AboutSection()
                }
            }
            Tab("Scrobbling", systemImage: "waveform") {
                SettingsPane {
                    LastFMSection()
                    ListeningRulesSection()
                }
            }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right") {
                SettingsPane {
                    RadioPlaylistSection()
                    PlayBackSection()
                    StationExclusionsSection()
                }
            }
            Tab("Menu Bar", systemImage: "menubar.rectangle") {
                SettingsPane {
                    MenuBarAppearanceSection()
                    WidgetSection()
                }
            }
        }
        .scenePadding()
        .frame(width: 540)
        .frame(minHeight: 420, maxHeight: 720)
        .environment(model)
    }
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

/// What the status item shows. `@AppStorage` so the label redraws the moment this changes.
struct MenuBarAppearanceSection: View {
    @AppStorage(CaptureSettings.menuBarLabelStyleKey, store: CaptureSettings.sharedDefaults)
    private var styleRaw = MenuBarLabelStyle.default.rawValue
    @AppStorage(CaptureSettings.menuBarLabelFormatKey, store: CaptureSettings.sharedDefaults)
    private var format = MenuBarLabelFormat.default
    @AppStorage(CaptureSettings.animatesMenuBarKey, store: CaptureSettings.sharedDefaults)
    private var animates = true

    private var style: MenuBarLabelStyle {
        MenuBarLabelStyle(stored: styleRaw)
    }

    var body: some View {
        Section {
            Picker("Menu Bar Shows", selection: $styleRaw) {
                ForEach(MenuBarLabelStyle.allCases) { style in
                    Text(style.name).tag(style.rawValue)
                }
            }
            Toggle("Animate When the Song Changes", isOn: $animates)

            if style == .custom {
                TextField("Format", text: $format, prompt: Text(MenuBarLabelFormat.default))
                    .font(.body.monospaced())
                LabeledContent("Preview") {
                    // Same function the status item uses, so an empty result looks empty here too.
                    Text(preview.isEmpty ? "(nothing)" : preview)
                        .foregroundStyle(preview.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Status Item")
        } footer: {
            if style == .custom {
                Text("Use \(MenuBarLabelFormat.tokens.joined(separator: ", ")). Long labels are shortened so they can't push other apps off the menu bar.")
            } else {
                Text("What sits in the menu bar while music is playing.")
            }
        }
    }

    private var preview: String {
        MenuBarLabelFormat.render(
            format,
            title: "Saltwater",
            artist: "Mara Solis",
            album: "Tides",
            station: "Chill Station"
        )
    }
}

/// Dock icon, menu bar extra and launch at login.
struct MacBehaviourSection: View {
    @Environment(MacAppBehaviour.self) private var behaviour
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var launchesAtLogin = false

    var body: some View {
        @Bindable var behaviour = behaviour

        Section {
            Toggle("Show in Menu Bar", isOn: $showMenuBarExtra)
                .disabled(showMenuBarExtra && !behaviour.showsDockIcon)
            Toggle("Show in Dock", isOn: $behaviour.showsDockIcon)
                // With both off there'd be no way back into the app.
                .disabled(!showMenuBarExtra && behaviour.showsDockIcon)
            Toggle("Open at Login", isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, wanted in
                    // Only a change the user made. Showing the current status, on appear or
                    // after a failure, writes the value it already has.
                    guard wanted != behaviour.launchesAtLogin else { return }
                    behaviour.setLaunchesAtLogin(wanted)
                    // What actually happened, so a failed attempt puts the switch back.
                    launchesAtLogin = behaviour.launchesAtLogin
                }
            if let error = behaviour.launchAtLoginError {
                Label {
                    Text("Couldn't change Open at Login: \(error)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            } else if behaviour.launchAtLoginNeedsApproval {
                LabeledContent {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                } label: {
                    Text("Allow Motif under Login Items in System Settings to finish turning this on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("App")
        } footer: {
            Text("Motif only notices what's playing while it's running. Opening it at login means nothing gets missed.")
        }
        .onAppear {
            // Reads the status only. Registering happens when the switch is flipped.
            behaviour.refreshLoginItemStatus()
            launchesAtLogin = behaviour.launchesAtLogin
        }
    }
}
