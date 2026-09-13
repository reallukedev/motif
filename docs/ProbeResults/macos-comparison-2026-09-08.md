# macOS: radio vs on-demand, 2026-09-08

Two live captures on macOS 27, Music 1.7.0. Radio log is
`macos-radio-2026-09-08.txt`; the on-demand run was captured in the same format.

## `playerInfo` payload

| Key | Radio (`Nostalgia` / Lossapardo) | On demand (`Snatch` / Imani Imani) |
|---|---|---|
| `Player State` | `Playing` | `Playing` |
| `Name`, `Artist`, `Album`, `Genre` | populated | populated |
| **`Total Time`** | **absent** | **`148734`** |
| `Composer` | absent | `Imani Ram & Daan Zinkhaan` |
| `Grouping`, `Description`, `Year` | absent | absent |
| `Track`/`Disc` number and count | absent | absent |
| `PersistentID`, `Library PersistentID` | absent | absent |

## AppleScript

| Property | Radio | On demand |
|---|---|---|
| **`duration of current track`** | **`missing value`** | **`148.733993530273`** |
| `player state` | `playing` | `playing` |
| `database ID` | present, increments (8383, 8399, 8415) | present, increments (8489, 8500, 8510) |
| `cloud status` | `missing value` | `missing value` |
| `media kind` | `song` | `song` |
| `current stream title` / `URL` | `missing value` | `missing value` |
| `current playlist` | not coercible to text | not coercible to text |

## Conclusion

**Duration is the discriminator.** A radio track reports no length at all (`Total Time` is
omitted from the notification and AppleScript answers `missing value`), while an on-demand
track reports it in both places. This is consistent with the mechanism observed in the Music
binary, where integer keys valued zero are omitted from the payload: a station's track has
no known duration to report.

`Composer` correlates too (present on demand, absent on radio) but is far weaker: plenty of
catalogue tracks legitimately have no composer, so it can corroborate and must not decide.

**Everything else is identical between the two cases** and cannot be used: `cloud status`,
`current playlist`, `current stream title`/`URL`, `media kind`, and the presence of a
`database ID` all look the same. Several of these were plausible candidates before the
control run, which is precisely why the control run was necessary.

## Correction to an earlier claim

From the single radio transition I concluded the payload "lags one track". The on-demand
data contradicts that: there, `playerInfo` reports the *new* track, matching the poll to the
millisecond (13:03:01.131 poll `Snatch`, 13:03:01.132 notification `Snatch`, position 0.075).

With one radio transition, during which the deck was also being skipped manually, lag and
a manual skip are indistinguishable. **The lag claim is withdrawn pending more radio
transitions.** The capture loop should still re-read after the notification rather than
trusting its payload, but as cheap insurance, not as an established finding.

## Evidence base

One station and one album. Enough to identify a candidate signal, not enough to ship a
detector on. Still needed: Apple Music 1, an algorithmic artist station, a personal station,
and the whole iOS side.

---

## Third capture: Apple Music 1 (live broadcast)

The detector holds. `Total Time` absent and `duration` `missing value` on every track
(*Lost Boys*, *Difficult Love*), `Composer` absent throughout. A live broadcast behaves the
same as an algorithmic station. This was the case most likely to break it.

Three behaviours the first two captures did not show:

**`playerInfo` fires on a ~16 second heartbeat, not only on track change.** *Lost Boys*
fired at `13:22:01`, `:17`, `:33`, `:49`, `13:23:05`: one track, five notifications, almost
certainly HLS segment boundaries. Dedupe absorbs the repeats, but a naive "notification
means new track" reading would be wrong, and session activity timing has to account for it.
(Later the same day `playerInfo` went silent for over four minutes across a track change, so
this heartbeat cannot be relied on. See `../PlatformNotes.md`.)

**The station is announced as a track at tune-in.** `Name = "Apple Music 1"` with empty
artist and album (`database ID` 8413). Two consequences: this is the only source of the
station name found on macOS (`current stream title` is empty in every capture), and it must
be filtered, or the playlist gains a song called "Apple Music 1" by nobody.

**Some notifications carry a player state and nothing else.** Two arrived back to back at
`13:21:43` with every field absent but `Player State`. Not capturable.

Also: `player position` stays pinned at `0.0` across every radio read and advances on demand
(28.1 → 29.2 → …). That is a **second discriminator independent of duration**. The two rest
on different mechanisms, so both failing together is much less likely than either alone.

Finally, when the player is stopped, nine of thirteen scripting reads fail with `«class pTrk»`
coercion errors. That is the normal shape of "there is no current track", not a fault.
