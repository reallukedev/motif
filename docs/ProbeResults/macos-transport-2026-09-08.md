# macOS: what transport commands do to a radio station, 2026-09-08

Run against live Music.app on macOS 27, on an **Apple Music live broadcast station**, via
`osascript` outside the sandbox. Automation permission was already granted, and the reads
that framed each test all succeeded, so nothing here is a permission artefact.

## Result

| Command | Paused | Playing | AppleScript error |
|---|---|---|---|
| `playpause` | **works** (paused → playing) | n/a | none |
| `next track` | no effect | **no effect** | **none** |
| `previous track` | no effect | **no effect** | **none** |
| `back track` | no effect | n/a | **none** |

Evidence for "no effect" is `database ID of current track`, which held at `8579` across
every command. That field increments on a genuine track change (the phase 0 radio capture
watched it step 8383 → 8399 → 8415), so an unchanged value is a real negative, not a stale
read. `name` and `artist` were also unchanged, and `player position` stayed pinned at `0.0`
throughout, re-confirming the radio signal.

## The part that matters for the UI

**A refused transport command returns no error.** Music accepts the event, answers success,
and does nothing. So the return value of `NSAppleScript.executeAndReturnError` cannot be used
to tell a command that worked from one that was ignored. The only way to know is to compare
`database ID` before and after.

This is why the menu bar disables the skip controls on radio rather than sending the command
and reporting what came back: there is nothing useful to report.

## What this does *not* establish

The station under test was a **live broadcast**, which cannot be skipped by design; Music's
own UI offers no skip button for one. So this run says nothing about an **algorithmic or
artist station**, where the UI does offer skip-forward.

The app currently disables both skips for *any* radio, which is correct for the case measured
and possibly over-strict for the other. The test to settle it:

1. Tune to an algorithmic station (an artist station, or Apple Music Chill).
2. Record `database ID of current track`.
3. `tell application id "com.apple.Music" to next track`.
4. Wait two seconds and read `database ID` again.

If it changes, `TransportRouting.capabilities(for:presence:)` should allow `.next` on radio
while continuing to refuse `.previous`. That is a one-line change, and
`TransportRoutingTests` names the rule it would replace.
