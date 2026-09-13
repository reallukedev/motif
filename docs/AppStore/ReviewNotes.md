# Notes for App Review

App Store Connect has a Notes box under **App Review Information** (4,000 characters). The two
blocks below are written to be pasted straight in, one per platform. The rest of this file is
background for the maintainer: why each thing is built the way it is, what App Review is likely
to ask, and the decisions that are still open.

Sign-in information: leave **"Sign-in required"** unticked. Motif has no accounts. Last.fm is
optional and nothing in the app is locked behind it.

## iOS notes to paste (2873/4000 characters)

```text
No sign-in is needed to review Motif. It has no accounts and no servers.

WHAT IT DOES
Motif keeps a history of what the user plays in Apple Music and shows statistics about it. It records songs played on demand, songs heard on Apple Music radio (Apple Music does not count radio listens as plays), and songs it reads from Apple Music's Recently Played list when it was not open.

MUSICKIT
Motif asks for Apple Music access on first launch (NSAppleMusicUsageDescription: "Motif reads what Apple Music is playing so it can keep your listening history, scrobble it to Last.fm, and save songs you hear on the radio to your library."). It uses MusicKit to read the system player's queue, read Recently Played, search the catalog, create a library playlist named "Heard on Radio" and add radio songs to it (can be turned off in Settings), and play songs with Play Back.

APPLE MUSIC SUBSCRIPTION
Radio, Heard on Radio and Play Back need an Apple Music subscription. Please review on a device signed in to an Apple Account with an active Apple Music subscription.

PLAY BACK
Play Back plays the radio songs heard today again, through the Music app, so they count as the real plays they then are. On iPhone and iPad it starts only when the user taps Play Back, uses the Play Back Today shortcut, or presses the Control Center control. Playback is always audible: Motif never mutes, lowers the volume, or plays silently. A song is marked as played back only once the player actually reaches it.

LAST.FM (OPTIONAL)
Settings > Last.fm > Connect opens last.fm in an in-app web sheet to approve access. Motif never sees the Last.fm password and nothing is sent to Last.fm until the user connects. Songs read from Recently Played are not sent unless a separate setting, off by default, is turned on. No Last.fm account is needed to review anything else.

HOW TO SEE POPULATED SCREENS
A new install has no history. The empty Summary screen has an "Explore with Sample Data" button that fills every screen with invented listening, clearly labelled "Sample Data", so all of the app can be reviewed without a subscription. Tap Done on the banner (or Settings > About > Show Sample Data) to go back. Nothing in sample mode is saved, synced or sent to Last.fm. To see real data on a device signed in to Apple Music: play a few songs in the Music app, then open Motif; it imports them from Recently Played. Playing a station (Music > Radio) with Motif open shows radio capture and the Heard on Radio playlist.

WIDGETS AND SHORTCUTS
Widgets: Listening (the last seven days, also on the Lock Screen), Last Played, and Today (with what Play Back will play next). A Control Center control starts Play Back. App Shortcuts: "Save Current Radio Song" and "Play Back Today".

DATA
The history is stored on device and synced through the user's private iCloud database. No analytics, ads or tracking.
```

## macOS notes to paste (2977/4000 characters)

```text
No sign-in is needed to review Motif. It has no accounts and no servers.

WHAT IT DOES
Motif keeps a history of what the user plays in Apple Music and shows statistics about it. It records songs played on demand, songs heard on Apple Music radio (Apple Music does not count radio listens as plays), and songs it reads from Apple Music's Recently Played list when it was not running. It opens a normal window with a Dock icon, and also puts a Motif item in the menu bar with what's playing now. Either can be turned off in Settings > General.

MUSICKIT
Motif asks for Apple Music access on first launch (NSAppleMusicUsageDescription). It uses MusicKit to read Recently Played, search the catalog to identify the playing song, and create a library playlist named "Heard on Radio" and add radio songs to it (can be turned off in Settings).

APPLE EVENTS (MUSIC AND SPOTIFY)
On macOS there is no MusicKit API for the system player, so Motif asks Music what is playing and sends it playback commands with Apple events. NSAppleEventsUsageDescription: "Motif asks Music and Spotify what is playing, and controls playback from the menu bar." Entitlements: com.apple.security.automation.apple-events, and com.apple.security.scripting-targets limited to the access groups the two apps declare: com.apple.Music.playback and com.apple.Music.library.read (artwork), and com.spotify.playback and com.spotify.library. No temporary exceptions. Spotify is only shown in the menu bar and can be paused or skipped there; Spotify listening is never recorded. Play Back hands songs to Music.app because only Music.app's own playback updates its play count.

APPLE MUSIC SUBSCRIPTION
Radio, Heard on Radio and Play Back need an Apple Music subscription. Please review on a device signed in to an Apple Account with an active Apple Music subscription.

PLAY BACK
Play Back plays the radio songs heard today again in Music, so they count as the real plays they then are. It starts when the user clicks Play Back or uses the shortcut, widget or Control Center control. An optional setting, off by default, starts Play Back two minutes after a station stops, and only if the keyboard or mouse was used in the last five minutes (CGEventSource idle time), so music never starts in an empty room. Playback is always audible: never muted, never silent. A song is marked played only once Music is actually playing it.

LAST.FM (OPTIONAL)
Settings > Last.fm > Connect opens last.fm in an in-app web sheet to approve access. Nothing is sent to Last.fm until the user connects.

HOW TO SEE POPULATED SCREENS
A new install has no history, so the screens show empty states that explain what will appear. To fill them: play a few songs in Music, then open Motif; it imports them from Recently Played, and records anything played while it is running. Allow the Automation prompt for Music when it appears.

DATA
Stored on device and synced through the user's private iCloud database. No analytics, ads or tracking.
```

## Background

### MusicKit

MusicKit is enabled for the App ID under **App Services** in the developer portal. There is no
MusicKit entitlement key; the developer token is issued automatically once the service is
ticked. What Motif uses it for:

| Use | Where |
|---|---|
| Watching the system player's queue (iOS) | `MotifCore/Sources/MotifMusic/Capture/SystemMusicPlayerSource.swift` |
| Recently Played import | `MotifCore/Sources/MotifMusic/Capture/RecentlyPlayedSource.swift` |
| Catalog search to identify a Mac song, which has no catalog id | `MotifCore/Sources/MotifMusic/Playlist/CatalogLookup.swift` |
| Creating "Heard on Radio" and adding tracks (Apple Music API through `MusicDataRequest`) | `MotifCore/Sources/MotifMusic/Playlist/MusicKitPlaylistWriter.swift` |
| Play Back on iOS (`SystemMusicPlayer`, `affectsListeningHistory = true`) | `MotifCore/Sources/MotifMusic/Playback/MusicKitPlaybackService.swift` |

Guideline 4.5.2 is the one App Review will read Motif against. How each part is met:

- **(i) Playback is user-initiated:** on iOS it always starts from a button, a shortcut or the
  Control Center control. On the Mac the one exception is automatic play-back, discussed below.
- **(i) No payment for access to Apple Music:** Motif doesn't charge for Apple Music access,
  sell anything in-app, or show ads.
- **(ii) Artwork appears only next to the music it belongs to:** covers appear next to the
  songs in history, statistics and widgets. App Store screenshots showing the app in use are
  allowed by the guideline; see `Screenshots.md`.
- **(iii) Apple Music data shared with a third party:** scrobbling sends listening to Last.fm.
  That is the user's own account, connected on purpose, and named in the purpose string
  ("…scrobble it to Last.fm…"), which is what 4.5.2(iii) asks for. It's not used to identify
  anyone or for advertising. Songs taken from Apple's Recently Played list are held back from
  Last.fm unless the user turns on a second, clearly labelled setting, which is off by default.

### Apple events on the Mac

`SystemMusicPlayer` is unavailable on macOS, and `ApplicationMusicPlayer` plays inside Motif's
own process, which reaches listening history but not Music.app's play count. So the Mac app
talks to Music.app with Apple events, both to read what is playing and to play songs back.

From `Apps/macOS/Resources/Motif.entitlements`:

- `com.apple.security.automation.apple-events`: the hardened runtime / TCC side.
- `com.apple.security.scripting-targets`: the sandbox side, scoped to access groups:
  - `com.apple.Music`: `com.apple.Music.playback` (transport, current track, stream title)
    and `com.apple.Music.library.read` (artwork and library lookups).
  - `com.spotify.client`: `com.spotify.playback` and `com.spotify.library`.
- No `com.apple.security.temporary-exception.apple-events`. The Mac App Store asks for a
  justification for that entitlement and often refuses it; the scoped targets avoid the
  question.

`NSAppleEventsUsageDescription` (`Apps/macOS/Resources/Info.plist`):
"Motif asks Music and Spotify what is playing, and controls playback from the menu bar."

Music's access groups were checked against `sdef /System/Applications/Music.app` on macOS 27
(`com.apple.Music.playback` and `com.apple.Music.library.read` are both declared). **Spotify's
were not**, because Spotify wasn't installed on the machine this was written on, and
`docs/PlatformNotes.md` records that Spotify support has never been run against a real client.
If Spotify's dictionary doesn't declare `com.spotify.playback` / `com.spotify.library`, the
sandbox refuses every event with a silent -1743 and App Review may ask why the entitlement is
there. Check before submitting:

```sh
sdef /Applications/Spotify.app | grep -o 'access-group identifier="[^"]*"' | sort -u
```

If a reviewer asks why Motif controls Spotify: the menu bar is a now-playing display, and a
person listening to Spotify would otherwise see nothing there, or a stale Apple Music song.
Motif shows the Spotify track labelled as not recorded and lets them pause or skip it. It never
records Spotify listening; `SpotifyNowPlaying` has no conversion into a capture at all.

### Play Back and the presence guard

The rule the app is built around: a play only counts because someone really heard it. Nothing
in Motif plays music silently, muted, at low volume, or to an empty room.

- **Manual Play Back** (button, "Play Back Today" shortcut, Today widget button, Control Center
  control) starts because a person asked for it. `PlayBackTodayIntent` runs in the foreground
  (`supportedModes = .foreground`), so the app opens and the user sees it play.
- **Songs are marked played back only as the player reaches them**, not when they are queued.
  A queue that never started claims nothing.
- **Automatic play-back (Mac only, opt-in):** `CaptureService.considerAutoPlayback()`
  (`Apps/Shared/Capture/CaptureService.swift`) starts Play Back when:
  1. the "Play back automatically" setting is on (`CaptureSettings.autoPlayBack`, default
     **off**);
  2. nothing has been playing for 120 seconds;
  3. `UserPresence.isPresent()` is true: HID idle time under 300 seconds, from
     `CGEventSource.secondsSinceLastEventType`. If idle time can't be read, the answer is
     "absent" and nothing plays;
  4. it hasn't already run in this listening session; and
  5. there is something unplayed to play.

  This is the one place Motif starts playback without a click at that moment, and it's the
  part of the app most likely to draw a 4.5.2(i) question ("users must initiate playback").
  The answer is that the user initiated it by turning the setting on, it's off by default, it
  never runs unattended, and nothing plays that the user can't hear and stop. See the decision
  below.

### Apple Music subscription

Radio needs a subscription, so Heard on Radio and Play Back do too. App Review's test accounts
usually have one, but not always. The paste-in notes ask for a subscribed device.

### Last.fm

Optional. The desktop authentication flow: Motif asks Last.fm for a token, opens
`https://www.last.fm/api/auth/?api_key=…&token=…` in the browser, and polls `auth.getSession`
for up to three minutes while the user approves it. The session key goes in the Keychain.

Sign in with Apple isn't required (guideline 4.8): Motif has no account of its own, and Last.fm
is a client connection to a specific third-party service, which 4.8 exempts.

A production Last.fm API key must be in the build. Without one the Connect button reports
"This build has no Last.fm API key. See Config/Motif.xcconfig.", a developer message App Review
would see and could reject under 2.1. `docs/Releasing.md` checks the archived Info.plist for it.

### How a reviewer sees populated screens

The empty Summary screen offers **Explore with Sample Data**, which opens a separate in-memory
store filled with invented listening and shows a "Sample Data" banner until it's turned off.
Play Back, deleting and Last.fm are switched off in that mode, and the real store is never
touched. The same data is available to developers with the `-MotifDemoData YES` launch
argument, which also hides the banner for screenshots.

### Things App Review sometimes asks, with answers

- *"Does Play Back manipulate play counts or charts?"* No. Every play is an ordinary,
  audible playback of a song the user heard on the radio earlier that day, in the Music app,
  with the user present. It counts because it is a play.
- *"Why is there a Last.fm secret in the app bundle?"* Last.fm's desktop authentication
  requires the app to sign requests with its shared secret; every Last.fm desktop client ships
  one. It identifies the app, not the user.
- *"Why does the Mac app use Apple events rather than MusicKit?"* MusicKit has no system player
  on macOS, and Music.app's play count only moves when Music.app itself plays the song.

## Decisions that came out of this review

These were open when the notes were first written and have since been settled in the code:

1. **In-app sample data.** Added, as described above, so review doesn't depend on the
   reviewer's listening history or subscription.
2. **Automatic play-back** stays opt-in and off by default, and the comment that said
   otherwise has been corrected.
3. **First launch on the Mac** opens the main window with a Dock icon. The menu bar extra is
   still there, and either can be turned off (not both).
4. **The `--headless` diagnostics** are compiled into Debug builds only.
5. **Last.fm sign-in on iPhone and iPad** happens in an in-app web authentication sheet; the
   Mac still opens the default browser.
