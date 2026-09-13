# Contributing to Motif

Bug reports, fixes, tests and new measurements of how Apple's frameworks behave are all
welcome, and so are feature ideas with a clear reason behind them. For anything large, open an
issue or a discussion first so we can agree on the approach before you write the code.

## Two rules

The first is that Motif never raises a play count for music nobody heard. In practice:

- No silent, muted or background playback to make a song count.
- A song is marked played back when playback reaches it. Queuing it isn't enough, and neither
  is a command that appeared to succeed.
- Automatic play-back only runs when someone is at the device. If Motif can't tell, it
  assumes nobody is.
- A song has to play for a while before it's kept. Don't loosen that.
- If Motif can't know something, it says so. "First time heard" means Motif hadn't recorded
  the song before. Don't relabel it as "new to your library", which Motif can't check.

The second is to read [`docs/PlatformNotes.md`](docs/PlatformNotes.md) before changing
capture, playback, matching or sync. It records how Music.app, MusicKit and the Apple Music
API behaved when measured on real devices, and a lot of it contradicts the obvious approach.
`playerInfo` has no `Store URL`, radio has no duration on macOS, and Music.app reports success
for transport commands it ignores. If you measure something new, or find that Apple has
changed something, add it to the notes with the date and what you saw.

## Setting up

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Anything beyond the
simulator also needs an Apple Developer account.

```sh
git clone https://github.com/reallukedev/motif.git
cd motif
brew install xcodegen
xcodegen generate
open Motif.xcodeproj
```

For the simulator, run the Motif (iOS) scheme. The simulator has no Apple Music account, so
add `-MotifDemoData YES` under Edit Scheme › Run › Arguments to fill an in-memory store with
generated history.

To run on a device, or to run the Mac app at all, copy `Config/Local.example.xcconfig` to
`Config/Local.xcconfig` and set your team and bundle identifier (see
[Building for a device](README.md#building-for-a-device)). For Last.fm, copy
`Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and add your own application's
key and secret (see [Last.fm](README.md#lastfm)). Both files are gitignored. Don't put your
own team or credentials in `Config/Motif.xcconfig`.

## Project layout

| Path | Contents |
|---|---|
| `Apps/Shared/` | SwiftUI and app logic used on both platforms |
| `Apps/iOS/`, `Apps/macOS/` | Platform code: app entry points, the Mac menu bar extra, headless diagnostics |
| `Widgets/` | Widgets and the Control Center control, shared by both platforms |
| `MotifCore/Sources/MotifCore/` | Models, protocols and pure logic, with no MusicKit import |
| `MotifCore/Sources/MotifMusic/` | MusicKit, Music.app scripting and playback, behind `MotifCore`'s protocols |
| `MotifCore/Tests/` | Swift Testing suites |
| `Config/` | xcconfig files and templates for local overrides |
| `docs/` | Platform notes and the probe results behind them |
| `project.yml` | XcodeGen spec; the `.xcodeproj` is generated and gitignored |

Run `xcodegen generate` whenever you add, remove or rename a file. Until you do, the build
can't see the change, and the error you get (often a linker error about a missing `_main`)
won't point at the cause. Build settings go in `project.yml` or an xcconfig, never in the
generated project.

## Conventions

These come from the existing code.

### Comments

A comment should say why the code is the way it is. Many lines in this project look odd and
exist because something broke without them; their comments say what broke. Don't delete a
comment you don't understand, or tidy the code under it, until you've found out. Comments that
restate the code aren't needed.

### Concurrency

The project uses Swift 6 language mode with complete strict concurrency and approachable
concurrency. Fix concurrency diagnostics instead of silencing them. If `@unchecked Sendable`
is really needed, add a comment saying what makes it safe.

App and widget targets are main-actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`). `MotifCore` isn't, because it's a library and callers should decide where its
work runs. Keep package code `nonisolated`, and `Sendable` where it can be.

SwiftData `@Model` objects must not cross an isolation boundary. Pass a `CaptureSnapshot` or
`SessionSnapshot`, or add a snapshot type.

The capture coordinator checks for a duplicate and inserts in one synchronous step. An
`await` between the two lets two observations of the same song both get in.

### Where code goes

If something can be decided without MusicKit or a device, it goes in `MotifCore` with tests:
whether to keep a song, whether it's radio, which catalog match wins, how a statistic is
calculated, how a Last.fm request is signed. That keeps the app targets small and lets the
logic be tested without a subscription. Code that touches MusicKit or scripting goes in
`MotifMusic`, behind a protocol declared in `MotifCore`.

The SwiftData schema has to stay CloudKit-compatible or sync breaks. Every non-optional
property needs a default, `@Attribute(.unique)` isn't allowed, and every relationship is
optional with an inverse.

Some identifiers live on people's devices: the bundle identifier, App Group, iCloud container,
widget kinds, Keychain service and `UserDefaults` keys. Several still say `Backtrack`, the
app's earlier name, and that's deliberate. Renaming one quietly resets users: they get signed
out of Last.fm, sync switches back on, or scrobbles are stranded under a device id nobody
owns.

### Tests

Write tests with Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), not
XCTest. Where you can, use values captured from a real device, such as an actual queue entry
id or notification payload, and add a comment naming the bug the test guards against. A bug
fix should come with a test that fails without it, when the logic allows.

### Run it

Most of the serious bugs in this project compiled cleanly and passed the tests. They were
found by running the app or reading captured data. Before opening a pull request:

- Run your change. For UI, check light and dark mode and a large Dynamic Type size.
- On the Mac, use a signed build (`./build.sh mac`). An unsigned Mac build runs on an empty
  in-memory store and can look fine while keeping nothing.
- Automation tools can't open or reliably screenshot the menu bar extra's window, so look at
  it yourself.
- In the pull request, say what you checked and what you couldn't check.

## Tests and builds

```sh
cd MotifCore && swift test   # package tests
./build.sh ci                # same as CI: tests, then unsigned iOS and macOS builds
./build.sh test              # package tests, short output
./build.sh mac               # signed Mac build plus entitlement checks (needs Local.xcconfig)
./build.sh ios               # iOS simulator build
```

`build.sh` uses whichever Xcode `xcode-select -p` points at. Set `DEVELOPER_DIR` to use a
different one.

## Commit messages

Match the style in `git log`. The subject is an imperative sentence in sentence case that
says what changes for someone using the app:

```
Require a song to play for a while before it counts
Stop the status item naming a song that is not playing
Actually send the scrobbles, rather than only at launch
Keep every song, and recover the ones Motif was not running to see
```

Leave off the trailing period and any `feat:`-style prefix, and keep it under about 72
characters. Wrap the body at about 80 columns and use it to explain what was wrong, why, and
how you checked the fix, including anything you couldn't check. Keep each commit to one
change.

## Pull requests

Keep them focused and fill in the template. Before asking for review:

- [ ] `cd MotifCore && swift test` passes.
- [ ] `./build.sh ci` passes, or CI is green.
- [ ] New logic in `MotifCore` has tests.
- [ ] You ran the change, and the description says what you checked and what you didn't.
- [ ] Nothing raises a play count or plays music without someone hearing it.
- [ ] You ran `xcodegen generate` after adding, moving or removing files, and didn't commit
      the generated project.
- [ ] No team ID, bundle identifier or credentials of your own are in tracked files.
- [ ] If you measured something new about Apple's behaviour, `docs/PlatformNotes.md` says so.

## Conduct and security

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Report security problems
privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## License

Contributions are accepted under the [MIT License](LICENSE).
