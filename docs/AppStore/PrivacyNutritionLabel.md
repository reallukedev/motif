# App Privacy answers and privacy manifests

Answers for the App Privacy section of App Store Connect (the "privacy nutrition label"), the
reasoning behind them, and the audit behind the four `PrivacyInfo.xcprivacy` files. The answers
are the same for the iOS and macOS versions.

Line numbers below were correct when this was written (September 2026). Re-run the audit
commands at the end before each release. The commands stay correct when the files move.

## The answers

**Do you or your third-party partners collect data from this app?**
→ **No, we do not collect data from this app.**

That single answer completes the questionnaire. The App Store page will show
**"Data Not Collected"**.

**Tracking:** Motif does not track. There is no advertising identifier, no third-party SDK of
any kind (the Swift package has no dependencies), and no data is combined with anyone else's.

## Why "Data Not Collected" is the accurate answer

Apple defines collecting as transmitting data off the device "in a way that allows you and/or
your third-party partners to access it for a period longer than necessary to service the
transmitted request in real time". Third-party partners are analytics tools, ad networks, SDKs
and other vendors whose code you add to the app. The test is who can get at the data, so each
thing that leaves the device is taken in turn.

### Listening history synced through iCloud: not collected

The history is mirrored with SwiftData into the user's **private** CloudKit database
(`ModelConfiguration(cloudKitDatabase: .private(…))` in
`MotifCore/Sources/MotifCore/Store/MotifStore.swift`, around line 150). A private database
belongs to the user's iCloud account. The developer has no access to its records through the
CloudKit Console or any API; only the schema is visible. Apple is acting as the user's storage
provider. Data the developer can never access is not collected.

### Apple Music requests: not collected

MusicKit calls (what's playing, Recently Played, catalog search, creating the "Heard on Radio"
playlist and adding to it) go from the device to Apple, authorised by the user's own Music user
token, and the results come back to the device. The developer receives nothing. Artwork comes
from Apple's CDN in the same way.

### Last.fm scrobbles: not collected by the developer

This is the one judgement call, so the reasoning is spelled out.

What is sent: artist, track, album and timestamp for each scrobble, plus "now playing" updates,
signed with the user's session key (`MotifCore/Sources/MotifCore/LastFM/LastFMClient.swift`).
It goes over HTTPS straight from the device to `ws.audioscrobbler.com`.

Why it isn't collection by the developer:

1. **The developer never receives it.** There is no Motif server in the path, and nothing is
   copied anywhere else.
2. **Last.fm isn't the developer's partner.** It is a service the user has their own account
   with, under their own agreement and Last.fm's own privacy policy. Motif contains none of
   Last.fm's code; it's a client for the user's account, like a mail app sending mail through
   the user's own mail provider. Apple's definition of third-party partners (vendors whose code
   the developer added to the app) doesn't cover this.
3. **It happens only at the user's request, to a destination the user chose.** Nothing is sent
   until the user connects their own Last.fm account in Settings and approves it on last.fm.
   They can switch scrobbling off or disconnect at any time. Songs recovered from Apple's
   Recently Played list are only scrobbled if a second setting, off by default, is turned on
   (`CaptureSettings.scrobblesImported`, `MotifCore/Sources/MotifCore/Capture/CaptureSettings.swift`
   around line 227).
4. **The developer can't access the result.** What arrives on Last.fm is the user's own public
   or private profile, which the developer has no more access to than anyone else.

The conservative alternative, for the maintainer to choose instead if preferred: declare
**Usage Data → Product Interaction** (Apple's definition explicitly lists "music listening
data"), **Linked to the user** (it is attached to their Last.fm account), used for **App
Functionality** only, **not used for tracking**. Nothing else would need declaring (the Last.fm
username is typed by the user into Last.fm's own site, never into Motif). That answer
over-discloses, because the developer still never sees the data, and it would put "Data Linked
to You" on a page for an app with no servers. It is a defensible answer; I think it's the less
accurate one.

**Recommendation: "Data Not Collected"**, with the reasoning above kept here in case App Review
asks.

If the privacy manifests and the App Store Connect answers ever disagree, App Store Connect
wins on the store page, but they should match: the manifests' `NSPrivacyCollectedDataTypes` is
empty for the same reasons. If the conservative answer is chosen, add the same entry to all four
manifests too:

```xml
<dict>
    <key>NSPrivacyCollectedDataType</key>
    <string>NSPrivacyCollectedDataTypeProductInteraction</string>
    <key>NSPrivacyCollectedDataTypeLinked</key>
    <true/>
    <key>NSPrivacyCollectedDataTypeTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypePurposes</key>
    <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
    </array>
</dict>
```

### Spotify artwork on the Mac: not collected

When Spotify is playing, the menu bar loads the cover from the URL Spotify's own scripting
interface reports (`SpotifyScripting.artworkURL()`). That's an image download from Spotify's
CDN, the same one the Spotify app makes. Nothing about the user is sent, and Spotify listening
is never recorded (`SpotifyNowPlaying` has no conversion into a capture).

### Things that stay on the device

- The local SwiftData store in the App Group container.
- Settings in the App Group's `UserDefaults` suite and the app's own defaults.
- The Last.fm session key in the Keychain (`kSecClassGenericPassword`,
  `kSecAttrAccessibleAfterFirstUnlock`, not synchronizable), and the Last.fm username in the
  App Group defaults.
- The HID idle time read by `UserPresence` on the Mac (seconds since the last input event,
  used only to decide whether automatic play-back may start). Read, compared, discarded.
- `DeviceIdentity`: a random UUID Motif generates (`MotifCore/Sources/MotifCore/Store/CloudSync.swift`).
  It does sync, as a field on each capture, but only into the user's private database, and it
  is not a device identifier in Apple's sense (it isn't derived from hardware, IDFV or IDFA,
  and is never sent to the developer or anyone else).

### Crash reports

Apple's own crash and usage reports, from people who opted in to share with developers, are
collected by Apple, not by the app, and are not declared on the label. Motif has no crash
reporting SDK. **If one is ever added, this whole page must be revisited**: third-party crash
reporting is "Diagnostics → Crash Data" and must be declared.

## Privacy manifests

One per shipped bundle, because each app and each extension is audited as its own binary:

| File | Bundle |
|---|---|
| `Apps/iOS/Resources/PrivacyInfo.xcprivacy` | Motif.app (iOS) |
| `Apps/macOS/Resources/PrivacyInfo.xcprivacy` | Motif.app (macOS), at `Contents/Resources/` |
| `Widgets/iOS/Resources/PrivacyInfo.xcprivacy` | MotifWidgets.appex (iOS) |
| `Widgets/macOS/Resources/PrivacyInfo.xcprivacy` | MotifWidgets.appex (macOS) |

All four are identical:

| Key | Value |
|---|---|
| `NSPrivacyTracking` | `false` |
| `NSPrivacyTrackingDomains` | empty |
| `NSPrivacyCollectedDataTypes` | empty (see above) |
| `NSPrivacyAccessedAPITypes` | `NSPrivacyAccessedAPICategoryUserDefaults` with reasons `CA92.1` and `1C8F.1` |

No `project.yml` change is needed to ship them. Each file sits under a directory that is
already a source path of its target (`Apps/iOS`, `Apps/macOS`, `Widgets/iOS`, `Widgets/macOS`),
and XcodeGen puts files with an extension it doesn't compile into Copy Bundle Resources. The
release runbook checks that each built bundle actually contains one.

App Store Connect enforces required-reason declarations for iOS and iPadOS. macOS reads the
manifest (Xcode's privacy report includes it) but hasn't been enforcing it; the Mac files are
there so both platforms say the same thing and nothing changes when enforcement arrives.

### Required-reason API audit

Every Swift file compiled into a shipped target was searched: `Apps/`, `Widgets/`, and both
modules of `MotifCore/Sources/` (linked into all four bundles, including the widgets). There are
no third-party dependencies to audit.

| Category | Used? | Where | Declared reason |
|---|---|---|---|
| User defaults | **Yes** | See below | `CA92.1`, `1C8F.1` |
| File timestamp | No | No `creationDate`, `modificationDate`, `attributesOfItem`, `stat`, `getattrlist` or `URLResourceKey` date keys anywhere | none |
| System boot time | No | No `systemUptime`, `mach_absolute_time`, `ProcessInfo` or `sysctl` | none |
| Disk space | No | No `volumeAvailableCapacity…`, `systemFreeSize`, `statfs` | none |
| Active keyboard | No | No `activeInputModes` | none |

#### User defaults in detail

- **`1C8F.1`: read and write data shared within the App Group.** This is the main use, in every
  bundle. `CaptureSettings` (`MotifCore/Sources/MotifCore/Capture/CaptureSettings.swift`,
  lines 39 to 51), `LastFMSessionStore.defaults` (`LastFM/LastFMSession.swift`, line 31),
  `CloudSync.defaults` and `DeviceIdentity` (`Store/CloudSync.swift`, lines 26 and 71) all use
  `UserDefaults(suiteName: <App Group>)`, and `@AppStorage(…, store: CaptureSettings.sharedDefaults)`
  binds SwiftUI to the same suite (`Apps/Shared/Settings/SettingsScreen.swift`,
  `Apps/macOS/App/MotifApp.swift`). The widgets read it too: `showsUpNextInWidget`, the playlist
  name and the rest of `CaptureSettings`. Only Motif and its own extensions are members of the
  group, which is exactly what 1C8F.1 permits.
- **`CA92.1`: read and write the app's own defaults.** `@AppStorage("showMenuBarExtra")` with no
  store (`Apps/Shared/Settings/SettingsScreen.swift` line 15, compiled into the iOS app as well
  as the Mac one, and `Apps/macOS/App/MotifApp.swift` line 9), and `UserDefaults.standard` for
  the Dock icon setting (`Apps/macOS/App/MacAppBehaviour.swift`, lines 15 and 23). Launch
  arguments such as `-MotifDemoData YES` are also read through the standard defaults' argument
  domain. In the widgets, CA92.1 covers the `?? .standard` fallback compiled in from MotifCore,
  taken when no App Group is configured (Xcode previews, unit tests).

#### Not on the list, checked anyway

- `CGEventSource.secondsSinceLastEventType` (`MotifCore/Sources/MotifCore/Capture/UserPresence.swift`,
  line 20, macOS only). Not a required-reason API. Disclosed in `PRIVACY.md` regardless, because
  it is the kind of thing a careful reader would want to know about.
- Keychain (`SecItem…`), `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`,
  `DistributedNotificationCenter`, `NSAppleScript`, `SMAppService`. None are required-reason
  APIs.
- SwiftData, CloudKit, MusicKit, WidgetKit and Swift Concurrency's clocks are system code;
  Apple's own frameworks carry their own manifests.

### Re-running the audit

```sh
g() { grep -rn -E "$1" Apps Widgets MotifCore/Sources --include='*.swift'; }
g 'UserDefaults|@AppStorage|SceneStorage'                                    # user defaults
g 'creationDate|modificationDate|attributesOfItem|getattrlist|[^a-zA-Z]stat\(|fstat|lstat|resourceValues|URLResourceKey'  # file timestamps
g 'systemUptime|mach_absolute_time|mach_continuous|ProcessInfo|sysctl|boottime' # boot time
g 'volumeAvailableCapacity|systemFreeSize|systemSize|statfs|statvfs|FileSystemFreeSize' # disk space
g 'activeInputModes|UITextInputMode'                                         # keyboard
```

Anything new in the last four lines needs a new entry in all four manifests. Validate after
editing:

```sh
for f in Apps/*/Resources/PrivacyInfo.xcprivacy Widgets/*/Resources/PrivacyInfo.xcprivacy; do plutil -lint "$f"; done
```

Then, on an archive, Xcode's Organizer → **Generate Privacy Report** shows what App Store
Connect will see, merged across the app and its extension.
