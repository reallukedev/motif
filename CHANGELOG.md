# What's New in Motif

## Motif 1.0

Motif remembers everything you listen to in Apple Music, including the songs Apple Music
doesn't count. This first release brings your listening history, in-depth statistics and
Last.fm scrobbling to iPhone and Mac.

### Listening History

- Every song you play in Apple Music is added to your history, whether you chose it or
  heard it on a radio station
- Radio songs are kept too, even though Apple Music doesn't count them as plays
- Songs that played while Motif wasn't running are recovered from Apple Music's Recently
  Played
- Skips are left out. A song is kept once it has played for 30 seconds, and you can change
  that in Settings
- Repair Artwork checks every cover in your history and fetches the ones that no longer load
- iCloud sync keeps your history up to date across all your devices, along with your
  settings and the songs you've removed, so a change made on one device holds on
  every device

### Summary

- Listening time for the week, month, year or all time, compared with the same point last
  period, with a bar for every day and a daily average
- Listening Rhythm shows when you listen, with a 24-hour listening clock, weekday and
  weekend averages, and your listening sessions
- Trends tracks your running total against last period, and how much of what you play is
  new to you
- Variety shows your mix of artists, your one-off songs and your deepest dive into a single
  artist
- Top Genres and Decades reveal the styles and eras you return to, with your recent
  releases, median release year and oldest song
- New Favorites, streaks and Records, from your biggest day and longest session to your
  earliest and latest listens
- Highlights sum up your listening in plain language

### Charts and Search

- Top songs, artists and albums for the week, month, year or all time, with how far each
  has moved since last period
- Artist, album and song pages show plays over time, rank, genre, release years, and when
  you first and last heard them
- Tap any album, anywhere it appears, for its own page and the songs you play from it
- Search finds anything you've played, including by genre

### Radio

- Heard on Radio collects the songs you hear on stations into a playlist in your Apple Music
  library
- The playlist stops at 250 songs so a station left running can't fill your library. Change
  the limit, or turn it off, in Settings
- Play Back plays your radio songs again through Apple Music so they count as plays. It only
  runs when you're there to hear it, and never plays silently
- Exclude any station you'd rather not have recorded

### Last.fm

- Connect your Last.fm account and Motif scrobbles every song it keeps, including radio
  songs and songs recovered from Recently Played
- Your Last.fm session key is stored securely in the Keychain

### iPhone

- Summary, History, Charts and Search, each a tap away
- With Background App Refresh, Motif catches up while it's closed, recovering songs, adding
  covers and sending scrobbles. Settings shows when it last did

### Mac

- A sidebar window with a dashboard Summary, a sortable history table with an inspector,
  top charts and a week-by-hour heat map
- A menu bar extra with the current song, its cover and playback controls, plus today's
  listening, your streak and your last few songs
- Show a symbol, the cover, the title, the artist or a format of your own in the menu bar
- A Settings window with General, Scrobbling, Radio and Menu Bar panes

### Widgets, Controls and Shortcuts

- Listening shows your last seven days and your streak, with Lock Screen sizes on iPhone
- Last Played shows the last song Motif kept
- Today shows today's songs and the radio songs lined up for Play Back
- A Control Center control plays back today's radio songs
- Save Current Radio Song and Play Back Today work with Siri, Spotlight and Shortcuts

### Privacy

- Motif has no servers, no account and no analytics
- Your listening history stays on your devices and in your private iCloud database
- Last.fm is contacted only if you connect an account

### For Developers

- Launch with `-MotifDemoData YES` to explore every screen with sample listening history.
  It lives in a separate in-memory store and is never saved, synced or scrobbled
- Last.fm API credentials are read from a gitignored `Config/Secrets.xcconfig` and are never
  committed

Some features require an Apple Music subscription. Motif requires iOS 27 or macOS 27 or
later.
