# App Store metadata

Copy for App Store Connect, for the iOS (iPhone and iPad) and macOS versions of Motif. Where a
field is the same on both platforms it appears once. Character counts were measured with a
script (Python `len()` over the exact text in each block, which counts Unicode characters the
way App Store Connect does; the keyword field is also limited to 100 bytes, and every string
here is plain ASCII apart from the bullet character `•`, which App Store Connect counts as one).

Rerun the count after any edit:

```sh
python3 -c 'import sys; s=sys.stdin.read().rstrip("\n"); print(len(s), "chars,", len(s.encode()), "bytes")' < field.txt
```

## Summary of counts

| Field | Limit | iOS | macOS |
|---|---|---|---|
| Name | 30 | 5 | 5 |
| Subtitle | 30 | 27 | 27 |
| Promotional text | 170 | 157 | 160 |
| Description | 4000 | 2152 | 2571 |
| Keywords | 100 | 99 | 99 |
| What's New (1.0) | 4000 | 293 | 293 |

## Name

```text
Motif
```

5 characters. App Store names are unique across the whole store, and "Motif" on its own
is a short dictionary word that another developer may already hold. Reserve it in App Store
Connect before anything else (creating the app record is what reserves it). If it is taken,
use the fallback, which keeps the brand first and puts a search term in the name:

```text
Motif: Listening History
```

24 characters. The name on the Home Screen comes from `CFBundleDisplayName` in
the Info.plists and stays "Motif" either way.

## Subtitle

Three options:

| # | Subtitle | Characters | Notes |
|---|---|---|---|
| 1 | Your listening, remembered. | 27 | The tagline. Distinctive and on brand, but "remembered" is not a word people search for. |
| 2 | Listening history and stats | 27 | Plain and searchable: "listening", "history" and "stats" are all indexed. |
| 3 | Music stats, history and radio | 30 | Adds "radio", at exactly the limit. Reads as a list rather than a line. |

**Chosen: option 1, "Your listening, remembered."** It is the line the product is built around and it says what
the app is for in a way the other two don't. The search terms options 2 and 3 would have carried
("history", "stats", "radio") are in the keyword field instead, so nothing is lost for search.
If App Store search traffic turns out to matter more than the brand line after launch, swap in
option 2; the subtitle can be changed with any new version.

The subtitle is the same on both platforms.

## Promotional text

Can be changed at any time without a new build. Not indexed for search.

### iOS (157/170)

```text
Keep a history of everything you play in Apple Music, radio included, and see where your listening goes: top songs, trends, streaks and your listening clock.
```

### macOS (160/170)

```text
Everything you play in Apple Music, kept and turned into stats. Now playing and playback controls sit in your menu bar, and your history syncs with your iPhone.
```

## Description

The copy sticks to what the app does. Two things in it need care, now and in any later edit:

- **Radio:** Apple Music *does* know what a station played (radio songs reach Recently Played);
  what it doesn't do is count them as plays. The copy says "doesn't count radio listens as
  plays" and never "Apple doesn't know" or "Apple forgets".
- **Play Back:** it plays songs again, audibly, so they count as the real plays they then are.
  The copy never says "boost", "increase" or "inflate" play counts, because Motif never does
  that: nothing plays silently, muted or without someone there to hear it.

Spotify appears only in the Mac description, only as a player the menu bar can show and control,
with the fact that it is never recorded stated in the same sentence.

### iOS (2152/4000)

```text
Motif keeps a history of everything you play in Apple Music and turns it into a clear picture of your listening.

It records the songs you play on demand and the songs you hear on Apple Music radio. Apple Music doesn't count radio listens as plays, so Motif keeps them for you. When Motif hasn't been open, it fills in what you played from Apple Music's Recently Played list the next time you open it.

YOUR LISTENING, IN NUMBERS
• Estimated listening time, and how it compares with the period before
• Top songs, artists and albums for the week, month, year or all time
• A listening clock showing the hours you listen most, and your weekday rhythm
• Streaks, first-time discoveries and highlights written in plain language
• A detail page for every song and artist

HISTORY
• Every song you've played, newest first
• Search everything you've played
• Delete a song and Motif forgets it, so it isn't added back later

RADIO
• Heard on Radio: songs from Apple Music radio are added to a playlist in your library, so you can find them again
• Play Back: play the radio songs you heard today again, on demand, so Apple Music counts them as plays. Songs play out loud, and only when you start them.
• Station exclusions: choose stations Motif shouldn't record

WIDGETS, CONTROLS AND SHORTCUTS
• Widgets for the last song you played, today's listening with what Play Back will play next, and your week
• A Control Center control to start Play Back
• Shortcuts for "Save Current Radio Song" and "Play Back Today", ready for Siri, Spotlight and the Action button

LAST.FM
Connect your Last.fm account to scrobble what you listen to. It's optional, and you can disconnect at any time.

PRIVACY
Your history stays on your devices and syncs through your own iCloud account. Motif has no servers, no ads, no analytics and no tracking, and it doesn't ask you to create an account.

Motif is also available for Mac, where it adds a menu bar with what's playing and playback controls.

Requires iOS 27 or iPadOS 27. An Apple Music subscription is needed to listen to Apple Music radio and to use Heard on Radio and Play Back. iCloud sync requires an iCloud account.
```

### macOS (2571/4000)

```text
Motif keeps a history of everything you play in Apple Music and turns it into a clear picture of your listening.

It records the songs you play on demand and the songs you hear on Apple Music radio. Apple Music doesn't count radio listens as plays, so Motif keeps them for you. Anything you played while Motif wasn't running is filled in from Apple Music's Recently Played list.

IN YOUR MENU BAR
• See what's playing, with the album cover, without switching apps
• Play, pause and skip in Music or Spotify from the menu bar. Spotify is shown, but never recorded.
• Choose what the menu bar shows: an icon, the cover, the song, or your own format
• Open at login, with or without a Dock icon

YOUR LISTENING, IN NUMBERS
• Estimated listening time, and how it compares with the period before
• Top songs, artists and albums for the week, month, year or all time
• A listening clock showing the hours you listen most, and your weekday rhythm
• Streaks, first-time discoveries and highlights written in plain language
• A detail page for every song and artist

HISTORY
• A sortable table of every song, with an inspector for the details
• Search everything you've played
• Delete a song and Motif forgets it, so it isn't added back later

RADIO
• Heard on Radio: songs from Apple Music radio are added to a playlist in your library, so you can find them again
• Play Back: play the radio songs you heard today again in Music, on demand, so Apple Music counts them as plays. Songs always play out loud.
• Optionally, Motif can start Play Back a couple of minutes after a station stops, but only while you're at your Mac
• Station exclusions: choose stations Motif shouldn't record

WIDGETS, CONTROLS AND SHORTCUTS
• Desktop and Notification Center widgets for the last song you played, today's listening with what Play Back will play next, and your week
• A Control Center control to start Play Back
• Shortcuts for "Save Current Radio Song" and "Play Back Today"

LAST.FM
Connect your Last.fm account to scrobble what you listen to. It's optional, and you can disconnect at any time.

PRIVACY
Your history stays on your devices and syncs through your own iCloud account. Motif has no servers, no ads, no analytics and no tracking, and it doesn't ask you to create an account.

Motif is also available for iPhone and iPad.

Requires macOS 27. An Apple Music subscription is needed to listen to Apple Music radio and to use Heard on Radio and Play Back. Motif asks for permission to control Music and Spotify the first time it needs to. iCloud sync requires an iCloud account.
```

If automatic play-back is removed from or disabled in the App Store build (see the decisions in
`ReviewNotes.md`), delete the "Optionally, Motif can start Play Back…" line from the macOS
description.

## Keywords (99/100)

```text
scrobbler,last.fm,history,stats,radio,tracker,top songs,artists,albums,charts,played,diary,insights
```

Comma separated with no spaces after commas; spaces inside a phrase ("top songs") are fine.
Words already in the name or subtitle ("Motif", "listening", "remembered") are left out because
Apple indexes those fields already, and so is "music", the category name. No competitor or
trademarked names: "Last.fm" is included only as a factual statement of compatibility, and
"Apple Music", "Spotify", "Replay" and "Wrapped" are deliberately absent. The same keywords
work for both platforms.

## Categories

| | iOS | macOS |
|---|---|---|
| Primary | Music | Music |
| Secondary | Lifestyle | Lifestyle |

Music matches `LSApplicationCategoryType = public.app-category.music` in both app Info.plists.
Lifestyle is the closest fit for the statistics and "year in listening" side of the app. The
other candidate is Utilities, which suits the Mac menu bar extra but undersells the statistics.

## Age rating

Answers for App Store Connect's age rating questionnaire. Everything is "None" or "No", which
gives the lowest rating (4+).

| Question | Answer | Why |
|---|---|---|
| Parental controls | No | |
| Age assurance | No | |
| Unrestricted web access | No | Motif has no in-app browser. Connecting Last.fm opens the system browser on last.fm's own sign-in page. |
| User-generated content | No | Nothing is shared between users. |
| Messaging and chat | No | |
| Advertising | No | Motif shows no ads. |
| Cartoon or fantasy violence | None | |
| Realistic violence | None | |
| Prolonged graphic or sadistic realistic violence | None | |
| Guns or other weapons | None | |
| Profanity or crude humor | None | See the note below. |
| Mature or suggestive themes | None | |
| Horror or fear themes | None | |
| Medical or treatment information | None | |
| Alcohol, tobacco or drug use or references | None | |
| Sexual content or nudity | None | |
| Graphic sexual content and nudity | None | |
| Simulated gambling | None | |
| Contests | None | |
| Gambling | No | |
| Loot boxes | No | |
| Health or wellness topics | No | |

Note on music content: Motif shows the titles of songs the person chose to play and hands
playback to Apple Music, which applies the account's own explicit-content setting (Screen Time
content restrictions). Motif doesn't provide or curate any content itself, so "None" is the
accurate answer. If App Review disagrees, the fallback is "Infrequent or mild" profanity, which
raises the rating to 9+ without other changes.

The questionnaire's exact wording changes from time to time; answer anything new on the same
principle (Motif contains no content of its own).

## Other fields

| Field | Value |
|---|---|
| Copyright | `2026 Luke` (App Store Connect adds the © itself; replace with the legal name the developer account is registered under) |
| Support URL | https://github.com/reallukedev/motif/issues |
| Marketing URL | https://github.com/reallukedev/motif |
| Privacy policy URL | https://github.com/reallukedev/motif/blob/main/PRIVACY.md |
| Primary language | English (U.K.) or English (U.S.): pick one. The copy uses neutral spelling. |
| SKU | `motif-ios` and `motif-macos` if the platforms are separate app records, or `motif` for a single universal record |
| Content rights | "Yes, it contains, shows or accesses third-party content", and "Yes, I have the necessary rights": Motif shows Apple Music catalog metadata and artwork through MusicKit, under the MusicKit terms. |
| Sign-in required | No |
| Price | Maintainer's decision; see "Pricing and Universal Purchase" in `docs/Releasing.md` |

All three URLs point at GitHub, so **the repository must be public before submission**. App
Review opens the privacy policy and support URLs, and a 404 is a rejection under guideline 1.5
(support) and 5.1.1 (privacy policy).

## What's New in version 1.0 (293/4000)

```text
Welcome to Motif, the first release.

Motif keeps a history of everything you play in Apple Music, including radio, and turns it into statistics and insights. Connect Last.fm if you'd like your listening scrobbled there too.

Found a problem or have an idea? Use the support link on this page.
```

Same text on both platforms. App Store Connect doesn't show a "What's New" field for the very
first version of an app; keep this for the 1.0 TestFlight "What to Test" notes and for the
release announcement, and write the field properly from 1.0.1 on.
