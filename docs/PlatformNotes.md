# Platform notes

These notes record how Apple's frameworks, Music.app and the Apple Music API behave in
practice. They were measured on an iPhone 17 Pro Max running iOS 27 and a Mac running
macOS 27, against a live Apple Music account, and several of them contradict what the
documentation suggests.

Treat them as settled and don't re-derive them. Most took hours to find and none showed up
in the compiler or the tests. If Apple changes something in a later release, measure it
again, update the note with the date and the evidence, and change the code and its test in
the same commit.

The raw captures behind the radio rules are in [`ProbeResults/`](ProbeResults/):

- [`ios-2026-09-08.md`](ProbeResults/ios-2026-09-08.md): radio and on-demand on iOS
- [`macos-comparison-2026-09-08.md`](ProbeResults/macos-comparison-2026-09-08.md): radio and
  on-demand on macOS, plus a live broadcast
- [`macos-radio-2026-09-08.txt`](ProbeResults/macos-radio-2026-09-08.txt): the raw probe log
- [`macos-transport-2026-09-08.md`](ProbeResults/macos-transport-2026-09-08.md): transport
  commands sent to a station

Some identifiers are older than the name Motif and stay as they are: the bundle id
`dev.luke.Backtrack`, the App Group and `iCloud.dev.luke.Backtrack` container derived from
it, the Keychain service and a few defaults keys. Renaming any of them resets what people
already have on their devices. Each one has a comment where it's declared.

## Contents

- [The model](#the-model)
- [The integrity rule](#the-integrity-rule)
- [Radio detection](#radio-detection)
- [macOS playerInfo](#macos-playerinfo)
- [Apple Music API limits](#apple-music-api-limits)
- [What Apple counts as a play](#what-apple-counts-as-a-play)
- [Playing back through Music.app](#playing-back-through-musicapp)
- [Transport control on a station](#transport-control-on-a-station)
- [Catalog matching on macOS](#catalog-matching-on-macos)
- [Store, processes and signing](#store-processes-and-signing)
- [iCloud sync](#icloud-sync)
- [Last.fm](#lastfm)
- [macOS 27 behaviour](#macos-27-behaviour)
- [SwiftUI and Swift Charts](#swiftui-and-swift-charts)
- [Features the platform rules out](#features-the-platform-rules-out)
- [Measurements](#measurements)
- [Not yet verified](#not-yet-verified)
- [Headless diagnostics on macOS](#headless-diagnostics-on-macos)

## The model

Motif keeps every song: heard on a station, played on demand, or recovered from Apple's
Recently Played for times it wasn't running. Only radio rows go into the "Heard on Radio"
playlist and the play-back queue, because Apple already counts the other two.

`CaptureKind` records which is which. `.imported` is a third value on purpose. Apple's
history says what played but not how, so calling an import radio or on-demand would invent
the one fact it can't know.

A song's identity is its title and artist. Catalog ids don't work as a key: Recently Played
reports the same song under a catalog id and a library id, and a macOS capture gets its id
from a search that may match neither. Keying on the id once imported five songs that were
already recorded, one of them twice. `HistoryImport.key` is the only
identity, and the cross-device merge uses it too.

`CaptureCoordinator` checks for a duplicate and inserts in one synchronous step, before any
`await`. The 10-second poll sees the same song over and over, and with an `await` in between
two observations of one song would both pass the check. A test runs two concurrent handles
through it.

## The integrity rule

Nothing may raise a play count unless the user heard the song. That rules out silent
playback, muted playback and faked counts. It has been broken once by accident already.

Captures used to be marked played back when they were queued, so a queue that never started
claimed plays that never happened. The player's queue is now followed, and each capture is
marked only when playback reaches it. Keep it that way.

Automatic play-back starts a couple of minutes after a station stops, and only if someone is
at the device (`UserPresence`, from HID idle time). If presence can't be determined, it
counts as absent.

On macOS a song counts as played back once Music.app confirms it's audibly playing it. A
successful Apple event proves nothing, because Music.app accepts commands and then ignores
them (see [transport control](#transport-control-on-a-station)).

## Radio detection

| Platform | Signal |
|---|---|
| iOS | `MusicPlayer.Queue.Entry.id` has the form `<queue>::<item>`, and the item half is the literal `STREAM` for radio. The queue half stays the same within a station and changes with it. |
| macOS | A radio track has no duration. `playerInfo` omits `Total Time`, AppleScript's `duration of current track` returns `missing value`, and `player position` stays at `0.0`. |

Ids from the iOS capture:

| Source | `entry.id` |
|---|---|
| Apple Music Chill | `Jzb4lWyve::STREAM` |
| Apple Music 1 | `PxDIf4ejk::STREAM` |
| Artist station | `o6C8OJs7I::STREAM` |
| Album, track 1 | `PRhKeIIy0::6ostOUDHU` |
| Album, track 2 | `PRhKeIIy0::EHYCyckzc` |

The `::STREAM` form is undocumented, so it lives behind `QueueEntryIdentifier`, and its tests
use these ids.

**Never port the macOS rule to iOS.** Once an entry resolves, MusicKit on iOS reports a real
`Song.duration` for a radio track (223 seconds in the capture, matching
`MPMediaItem.playbackDuration`), so "no duration" would call a station on-demand. When an
entry id exists, it's the only thing consulted.

iOS entries resolve in two steps about a second apart. The first has a title and no item,
and at a station change that title is the station's name, which is the only place iOS gives
one. Capturing it would put the station in the playlist as a song, so an unresolved entry
isn't treated as an observation.

These were tested and discriminate nothing:

- `Entry.isTransient`, which is `false` for radio and albums alike.
- `playParameters`, which says `{"kind":"song"}` for both. There's no `radioStation` kind.
- On iOS: `persistentID` (0), `mediaType` (0), `isCloudItem`, `hasProtectedAsset`,
  `repeatMode` and `shuffleMode`. `playbackStoreID` is empty until the entry resolves and
  then equals `song.id`.
- On macOS: `cloud status`, `current playlist`, `current stream title` and `URL`,
  `media kind`, and whether `database ID` increments. `Composer` is absent on radio, but
  plenty of catalog tracks have no composer, so it can support a decision and never make one.

`MPMediaLibrary.authorizationStatus()` can read `notDetermined` while MusicKit is
`.authorized`. They're separate permissions, and Motif doesn't need the MediaPlayer one.

## macOS playerInfo

The notification has exactly 16 keys: `Player State`, `Name`, `Artist`, `Album`, `Genre`,
`Composer`, `Grouping`, `Description`, `Year`, `Track Number`, `Track Count`,
`Disc Number`, `Disc Count`, `Total Time` (ms), `PersistentID` and `Library PersistentID`.

There is no `Store URL`. That key belongs to the iTunes Library XML exporter, a different
part of the Music binary. macOS gives no catalog identifier at all, so identity comes from a
catalog search.

Music posts every event twice, as `com.apple.Music.playerInfo` and
`com.apple.iTunes.playerInfo`. Observe one of them. Register with `.deliverImmediately`: the
default, `.coalesce`, suspends delivery while the app is inactive, and a menu bar app is
inactive nearly all the time.

Integer keys with a value of zero are left out of the payload. That's why a missing
`Total Time` means radio.

**Don't wait for a heartbeat.** One early capture showed a notification about every 16
seconds, probably at HLS segment boundaries. Later the same day `playerInfo` went quiet for
4 minutes 19 seconds across a track change, and the one notification that arrived for the
new track said `Player State = Paused`, which the capture policy correctly rejects. The app
showed a song from minutes earlier until the user paused and played again. So macOS capture
polls `PlayerInfoSource.currentObservation()` every 10 seconds, and the notification only
makes it faster.

Scripting reads the live radio track reliably. Two of the 13 properties fail (`current
playlist` can't be coerced to text), and `name` and `artist` aren't among them, which is what
makes polling possible. With the player stopped, nine of 13 reads fail with `«class pTrk»`
coercion errors; that just means there's no current track. AppleScript's `current track` was
reported broken for streamed tracks on macOS 26 (error -1728, FB19908171). On 27 the name
and artist reads held up on radio, but every read is still handled as one that can fail.

At tune-in, Music announces the station as a track: `Name` is the station, with no artist or
album. It's the only source of a station name on macOS, since `current stream title` was
empty in every capture. It must never be kept as a song, or the playlist gets a track called
"Apple Music 1" by nobody. Some notifications carry only `Player State`; there's nothing to
capture in those.

An early claim that the radio payload lags one track behind was withdrawn. On demand, the
notification matched the poll to the millisecond, and the single radio transition behind the
claim coincided with a manual skip. The capture loop re-reads after each notification anyway.

## Apple Music API limits

`MusicLibrary`'s write methods are `@available(macOS, unavailable)`. Playlists go through the
REST API with `MusicDataRequest`, which works on both platforms, so don't bring back
`MusicLibrary.add(_:to:)`. `POST /v1/me/library/playlists` creates a playlist, and
`POST /v1/me/library/playlists/{id}/tracks` adds to one, answering 204 with no body.

The API can create playlists and add tracks. It can't delete a playlist (`DELETE` returns 401
with tokens that create fine), and there is no endpoint for removing a track. Removing a song
in Motif removes it from Motif's history, and "Show in Music" handles the rest. Don't ship a
control that looks like it takes a track out of a playlist.

`SystemMusicPlayer` is unavailable on macOS. `ApplicationMusicPlayer` plays in-process and
stops when the app quits, which is why macOS play-back goes through Music.app instead (see
[below](#playing-back-through-musicapp)). `Queue.affectsListeningHistory = true` is what puts
a play-back into listening history.

There is no `com.apple.developer.music-kit` entitlement. MusicKit is switched on by ticking it
under App Services for an Explicit App ID, and developer tokens are then issued with no JWT
code. A wildcard App ID can't carry it, and an ad-hoc signed build has no provisioning
profile. Either way the result is `developerTokenRequestFailed`, a setup problem rather than
a transient error.

The sandboxed Mac app needs `com.apple.security.personal-information.media-library`,
`com.apple.security.automation.apple-events` and `com.apple.security.scripting-targets`, with
the access groups that Music (`com.apple.Music.playback`, `com.apple.Music.library.read`) and
Spotify declare. The sandbox check runs before TCC, so a misspelled access group gives no
prompt at all, only a silent -1743 that looks exactly like the user saying no.

## What Apple counts as a play

Apple tracks two separate things. Measured against a real library on 2026-09-08:

| | Recently Played / listening history | Music.app `played count` |
|---|---|---|
| Heard on radio | yes | no (0) |
| Played in-process with `ApplicationMusicPlayer` | yes | no (0) |
| Played by Music.app | n/a | yes, immediately (0 → 1) |

Radio gives no play count. All fifteen captures from that day read 0, while 144 of the
library's 843 tracks had a non-zero count, so the field works and the zeros mean something.

Radio does reach Recently Played. Apple knows what the station played; it just doesn't count
it. The app must not claim that Apple has no record of radio listening.

Play-back reaches Recently Played too. After three songs were played back, they were the top
three entries, in order. An earlier check couldn't have shown this, because it looked for
captures in Recently Played, and radio had already put every capture there.
`--headless playone <id>` avoids that problem: it plays one song and touches nothing else.

Radio also shows up in third-party listening apps, tens of minutes later. Seven radio
captures appeared in one while none of them had been played back (`playedBackAt == nil`). A
check earlier that evening found them missing because it came too soon.
`MusicRecentlyPlayedRequest` has them within seconds. Play-back isn't needed for those apps.
Its purpose is play counts, Replay and Apple's recommendations, none of which radio feeds.

Nothing played in-process moves `played count`, with either the catalog song or the library
copy (`--headless playlib <title>`). Music.app playing the same kind of track moved it from 0
to 1 within seconds, so it isn't sync lag. On macOS the counter belongs to Music.app.

## Playing back through Music.app

macOS play-back goes through Music.app (`MusicAppPlaybackService`). Music.app owns the play
counter, the songs are already in the library because Motif added them, and the app already
has the `com.apple.Music.playback` scripting entitlement. Verified end to end: "Play back
today" made Music.app play, `played count` went from 1 to 2, and the capture was marked. iOS
uses `MusicKitPlaybackService`, where `SystemMusicPlayer` is the Music app. That it counts
there is an inference.

Motif has to run the queue itself. Playing a track from a playlist makes that playlist
Music.app's context, but Music.app leaves it after one track and carries on into Autoplay.
The service plays one song at a time and moves on when Music.app stops playing it.

Two small bugs came out of this. A playlist name of a single space had been saved, and
play-back asked for `playlist " "` because the guard was `!name.isEmpty`; blank names now
count as unset. A song in the library but not in the playlist couldn't be played, and the
lookup now falls back to the whole library.

Automatic play-back was verified on 2026-09-08. A station stopped at 19:44:56 and play-back
began at 19:47:12 with the oldest unplayed capture, using the library copy. The gap is 136
seconds, not 120, because the delay starts at the first poll that sees silence.

`--headless playone` stops songs part-way because the headless path never runs a run loop.
The app itself played a 213-second track to the end, checked against the `coreaudiod`
audio-out power assertion.

## Transport control on a station

Measured on 2026-09-08 against an Apple Music live broadcast. The details are in
[`ProbeResults/macos-transport-2026-09-08.md`](ProbeResults/macos-transport-2026-09-08.md).

| Command | Effect on a station | Error returned |
|---|---|---|
| `playpause` | works | none |
| `next track` | nothing | none |
| `previous track` | nothing | none |
| `back track` | nothing | none |

Music accepts a command it won't carry out and reports success, so `NSAppleScript`'s error
can't distinguish the two cases. The only reliable check is `database ID of current track`
before and after: it stays the same on a no-op and increments on a real track change.

The menu bar disables both skip buttons whenever Music is playing radio. Only live broadcasts
have been measured; algorithmic stations are listed under
[Not yet verified](#not-yet-verified).

macOS shows no help tag on a disabled control, so the reason the buttons are off is printed
as a caption.

## Catalog matching on macOS

With no song id, macOS matches metadata against a catalog search. Each rule here fixed a real
mismatch.

- Title and artist must match after normalisation.
- A trailing parenthetical is stripped only if it's cosmetic. `(Remastered)` and `(feat. …)`
  are the same performance. `(Live)`, `(Remix)`, `(Rework)` and `(Mixed)` are different
  recordings, and stripping them puts the wrong one in someone's library.
- Several ids for one song is normal, since a recording can be on a single, an album and an
  EP. One search returned four ids for the same 163-second song. Candidates are grouped by
  length and the bigger group wins. An even split is real ambiguity, and the match is refused.
- On radio, which reports no duration, the album is what breaks ties.

## Store, processes and signing

An unsigned Mac build has no App Group entitlement, and the app quietly falls back to an
in-memory store. It opens and looks normal with nothing in it. Unsigned builds are fine for
checking that the code compiles, which is all CI does with them. To run the app, use
`./build.sh mac`, which signs it and then checks that the App Group and iCloud entitlements,
and the embedded, entitled widget extension, made it into the product.

App Group identifiers differ by platform: `group.<bundle id>` on iOS, and the same with the
team ID in front on macOS. An App Group shares data between an app and its extensions on one
device and never across devices.

SwiftData refuses a second read-write open of the store and allows a read-only one. A
headless command that writes while the app is running falls back to an empty in-memory store.
A read-only open (`MotifStore(readOnly: true)`, which sets `allowsSave: false`) works while
the app has the store open, and widgets depend on that. `--headless readonly` checks it.

SwiftData `@Model` objects never cross an isolation boundary. Pass `CaptureSnapshot` or
`SessionSnapshot` instead.

## iCloud sync

The store is mirrored to the user's private CloudKit database, so the Mac and the iPhone share
one history and it survives a lost device. Automatic signing creates the container on the
first build, which needs `-allowProvisioningUpdates` (`build.sh` passes it). Without it the
build fails with "no profiles were found", and nothing in that message mentions iCloud.

Sync failing must never cost the local data. The store tries three configurations in order:
App Group with CloudKit, App Group alone, then in-memory. No iCloud account, a container the
profile doesn't grant, and a schema CloudKit rejects are all ordinary situations where the
local store is fine. Dropping to in-memory on a CloudKit error would throw the user's history
away.

The schema follows CloudKit's rules: every non-optional property has a default, nothing uses
`@Attribute(.unique)`, and every relationship is optional with an inverse. That's why turning
on mirroring needed no migration.

Two repairs only matter once there are two devices:

- The playlist queue is per device. `needsPlaylistWrite` syncs, and so does the playlist, so
  a row from the iPhone that still owed a write would look owed on the Mac as well and both
  would add it. `Capture` carries `capturedByDeviceID`, and
  `pendingPlaylistWrites(deviceID:)` filters on it.
- Stations get duplicated and are merged afterwards. Two devices hearing one station each
  create a `Station` row, and CloudKit has no unique constraint to stop that.
  `mergeDuplicateStations()` merges them by normalised name, keeping the oldest row so every
  device reaches the same result on its own. It runs at launch and on the 60-second
  housekeeping timer. Sessions are moved to the surviving row before the duplicate is
  deleted, and that order matters: `Station.sessions` cascades, so deleting a duplicate that
  still owns sessions deletes listening history.

## Last.fm

`LastFMSignature` is pure and tested because the server gives the same answer, "Invalid
method signature supplied", for a bad signature, key, secret or parameter. Two details are
easy to get wrong: `format` is sent but not signed, and the string to sign is each `name`
followed by its `value` with no separators, then the secret.

The session key doesn't expire and is enough to scrobble as the user, so it's kept in the
Keychain and not in the App Group's defaults.

The API key and secret come from the gitignored `Config/Secrets.xcconfig`. Without them the
app runs and says it has no Last.fm application, instead of failing the first request with a
signature error.

Scrobbles are sent when a song is kept and on the 60-second housekeeping timer. They used to
be sent only at launch, so an account connected mid-session scrobbled nothing until the next
restart.

## macOS 27 behaviour

- `UIDesignRequiresCompatibility` is ignored with the 27 SDK. You can't opt out of Liquid
  Glass.
- Menu items hide their symbol images by default, the reverse of macOS 26. A menu item that
  needs its icon needs `.labelStyle(.titleAndIcon)`.
- `NSApp.activate()` opens an accessory app's window behind the frontmost app. Motif uses the
  deprecated `activate(ignoringOtherApps:)` on purpose.
- `statusItem.button.state`, `.target` and `.action` read as `.off` or nil whatever the real
  state is. Don't read them.
- A `ScrollView` inside a `.window`-style `MenuBarExtra` needs a definite height. It has no
  intrinsic height and the window sizes to its content, so `.frame(maxHeight:)` alone
  collapses it to zero and the menu shows only its footer.
- `MenuBarExtra(isInserted:)` is the only supported way to show and hide the extra at run
  time. `if show { MenuBarExtra … }` doesn't compile because `SceneBuilder` has no
  `buildEither`. Bind it to `@AppStorage`; `MenuBarExtra` content doesn't re-render for
  `@State`.
- The menu bar extra's window isn't exposed to accessibility, so it can't be opened by script
  or reliably screenshotted. Look at it yourself. Two logic bugs were found only from a
  screenshot taken by hand.
- Menu commands and their shortcuts still work in an `.accessory` app with no visible menu
  bar. ⌘3 switched panes with the Dock icon off.

## SwiftUI and Swift Charts

- Swift Charts crashes if a `RectangleMark` has no band to size against. Making the x axis
  categorical with `.chartXScale(domain: Array(0...23))` crashed during layout with
  `EXC_BREAKPOINT` inside Charts. Nothing was printed to stderr or logged, and the crash
  report had only four unsymbolicated Charts frames. It crashed with automatic mark sizes and
  with `.ratio(1)`. Use `RectangleMark(xStart:xEnd:y:height: .fixed(h))` over a continuous
  `0...24` scale.
- `MarkDimension.ratio` is a fraction of the mark's default size, not of the band. `.ratio(1)`
  left heat-map cells and ranking bars floating in gaps. `.fixed` fills the band.
- An axis label at the top of the domain gets clipped at the plot's edge. A chart of five
  artists with one play each was labelled only "0". Counts are drawn as trailing annotations
  instead, with some headroom added to the domain.
- Inflection (`^[\(n) song](inflect: true)`) only works in a string literal passed to `Text`.
  Wrapping a built string in `LocalizedStringKey(someString)` skips inflection and renders
  "13 song", so a helper that returns `String` can't carry it; take a `LocalizedStringKey`.
- `@State` is a macro in SDK 27. If a view fails with "used before being initialized", remove
  the initial value from the declaration. Reordering the assignments in `init` won't help.

## Features the platform rules out

Removing a track from "Heard on Radio". The API can't remove tracks or delete playlists, so
removal only affects Motif's history.

A discovery rate based on the user's library. The idea was the share of songs that weren't
already in the library, and MusicKit on macOS 27 can't answer it. `LibrarySongFilter` only
offers `id` (a library id), `title`, `artistName`, `albumTitle`, `composerName`, `albums`,
`artists` and `genres`, and `Song` has no `catalogID`, so catalog and library songs can't be
matched exactly. Fuzzy title-and-artist matching is the only option, and `CatalogMatcher`
needs three rules and a refusal case to get that right. Motif shows "first time heard"
instead: songs Motif itself had never recorded. That figure is exact, and the app says it
doesn't know what was in your library. Don't relabel it. If someone does build the library
version, the REST API through `MusicDataRequest` is the route to try, and the answer has to be
recorded before Motif writes to its playlist, because adding a song to a library playlist
adds it to the library.

A keyboard shortcut that opens the menu bar extra. `Scene.keyboardShortcut` doesn't apply to
`MenuBarExtra`, and macOS 27 has no public API to open its window; the one library that does
it uses private API. A global hotkey bound to an action, such as saving the current radio
song, would work.

## Measurements

Statistics are computed on demand. Five thousand captures, years of heavy listening, take a
few milliseconds, so `StatsSnapshot` is deliberately unused: a cached figure can go stale.
`StatsCalculatorTests` holds the measurement. Revisit caching only if that test gets slow.

Tests use real observed values, such as the actual entry ids and payloads, so if Apple's
behaviour changes a test fails instead of capture quietly going wrong.

The iOS build has been signed, installed and launched on a physical iPhone, with the App
Group and iCloud entitlements confirmed, so it runs on the real store.

## Not yet verified

Mark these as unverified in code and in the UI where it matters, and move each one up into
the notes above once it's measured.

- Spotify. It wasn't running when its support was written, so notification parsing,
  scripting reads and artwork lookup haven't been checked against a real client, and the
  code and `SpotifyNowPlayingTests` say so. Spotify is shown in the menu bar and never
  captured: `SpotifyNowPlaying` is a separate type with no conversion to what the capture
  coordinator accepts.
- `next track` on an algorithmic station. Only a live broadcast was tested. To check, tune to
  an artist station or Apple Music Chill, read `database ID of current track`, run
  `tell application id "com.apple.Music" to next track`, wait two seconds and read it again.
  If it changed, `TransportRouting.capabilities(for:presence:)` should allow `.next` on radio
  and still refuse `.previous`. It's a one-line change, and `TransportRoutingTests` has the
  rule it would replace.
- Sync between two devices. Mirroring opens against a live account and Settings reports it,
  but nobody has watched records arrive on a second device. Things to confirm: captures show
  up on both, a station heard on both ends up as one row, and a song kept on the iPhone isn't
  added to the playlist again by the Mac.
- A station changing track on the iPhone. iOS relies on the `::STREAM` signal and no catalog
  search, so the macOS checks don't carry over. iOS has no polling fallback;
  `SystemMusicPlayerSource` watches the queue directly and may not have the macOS gap, but
  that's untested.
- Radio reaching third-party apps with Motif quit. Motif adds each capture to a library
  playlist, and Recently Played entries switch from catalog ids to library ids (`i.…`) after
  that, so the library add might be what makes them visible. Test by playing a station with
  Motif closed and checking an hour later.
- Play counts on iOS. That `SystemMusicPlayer` play-back increments them is assumed.
- Live Activities. ActivityKit is iOS-only and needs a device with a live session.

## Headless diagnostics on macOS

The Mac app has a headless mode with no window or Dock icon that prints to stdout:

```sh
./build.sh mac
BIN="$(ls -d ~/Library/Developer/Xcode/DerivedData/Motif-*/Build/Products/Debug/Motif.app)/Contents/MacOS/Motif"
"$BIN" --headless env
```

Commands: `env`, `catalog <term>`, `write [songID]`, `sample [secs]`, `captures`,
`playlists`, `play`, `recent`, `reset-playback`, `retry-unresolved`, `cleanup`,
`autoplay [on|off]`, `playone <id> [secs]`, `playlib <title>`, `readonly`, `stats`,
`lastfm`, `scrobble`, `stations`, `forget <text>`, `menubar <style>`.

Quit the app before running a command that writes, or it will open an empty in-memory store.

Run `autoplay` before deciding automatic play-back is broken. It declines on purpose most of
the time, and it prints every guard it checked.

`write` creates a real playlist in your library. The API can't delete it, so remove it by hand
in Music; `cleanup` lists the ones to delete.
