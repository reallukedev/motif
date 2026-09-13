# Changelog

All notable changes to Motif are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first public release, planned as 1.0.

### Added

- Listening history of everything played in Apple Music on iPhone and Mac: songs played on
  demand, songs heard on Apple Music radio (which Apple does not count as plays), and songs
  recovered from Apple Music's Recently Played that played while Motif wasn't running.
- A song is kept only after it has played for a while, so skips don't count.
- Statistics and insights: estimated listening time, scrobble trends, top songs, artists
  and albums by week, month, year and all time, a listening clock, a weekday rhythm, streaks,
  discoveries, and plain-language highlights.
- Last.fm scrobbling of everything Motif keeps, with the session key stored in the
  Keychain.
- Radio extras: a "Heard on Radio" library playlist; Play Back, which replays radio songs
  through Apple Music so Apple counts them, only when someone is there to hear them and never
  silently; and per-station exclusions.
- iPhone and iPad app with Summary, History, Charts and Search tabs, and artist and song
  pages.
- Mac app with a sidebar window (dashboard Summary, a sortable history table with an
  inspector, top charts), a menu bar extra showing what's playing with today's listening and
  streak, and a Settings window.
- Widgets on both platforms (Listening, Last Played, and Today with the radio songs up next),
  Lock Screen versions of Listening on iPhone, and a Control Center control to play back
  today's radio songs.
- Shortcuts actions: Save Current Radio Song and Play Back Today.
- iCloud sync of the listening history between devices, through the user's private
  CloudKit database.
- Sample data: "Explore with Sample Data" on the empty Summary (or the `-MotifDemoData YES`
  launch argument) fills a separate in-memory store with invented history, so every screen
  can be explored without an Apple Music account.

### Changed

- Renamed from Backtrack. The bundle identifier, App Group, iCloud container and Keychain
  entries keep their original names, so existing installs keep their history and sign-ins.

### Fixed

- Songs recovered from Recently Played were imported again at each launch once they were
  more than a day old, inflating play counts for light listeners.
- The comparison with the previous period measured a week in progress against a whole week.
- A song heard on both iPhone and Mac could appear twice in charts, because each device
  identified it differently.

### Security

- No servers and no analytics. Listening history stays on the device and in the user's
  private iCloud database; Last.fm receives scrobbles only if the user connects it.
- Last.fm API credentials are read from a gitignored `Config/Secrets.xcconfig` and are never
  committed.

[Unreleased]: https://github.com/reallukedev/motif/commits/main
