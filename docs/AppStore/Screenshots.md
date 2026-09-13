# Screenshots

What App Store Connect needs for Motif 1.0, which screens to capture, and a caption for each.
Sizes are Apple's current accepted sizes as of September 2026; App Store Connect rejects an
upload with the wrong pixel dimensions and says which sizes it wanted, so check its message
before resizing anything by hand.

## Required sets

Motif ships on iPhone, iPad (`TARGETED_DEVICE_FAMILY = 1,2`) and Mac, so three sets are needed.
Each set takes 1 to 10 images. App Store Connect scales the largest set down for smaller
devices, so the sizes below are the only ones to produce.

| Set | Accepted sizes (portrait; landscape is the same pair swapped) | Simulator or setup that produces it natively |
|---|---|---|
| iPhone 6.9" | **1320 × 2868**, 1290 × 2796 | iPhone 17 Pro Max (1320 × 2868) |
| iPad 13" | **2064 × 2752**, 2048 × 2732 | iPad Pro 13-inch (M5) (2064 × 2752) |
| Mac | **2880 × 1800**, 2560 × 1600, 1440 × 900, 1280 × 800 | A Retina display at "Looks like 1440 × 900" gives 2880 × 1800 |

PNG or JPEG, RGB, no transparency. The bold size in each row is the one to use.

## Setting up

The quick way: `./Tools/screenshots.sh` builds the Debug apps and captures a full iPhone, iPad
and Mac set from sample data into `build/screenshots`, at the sizes above. The rest of this
section is for capturing by hand, and for the shots the script can't take (the menu bar extra
and widgets).

Use sample data rather than a real library, so every screen is full and nothing personal is in
the picture. Launch with the demo argument:

```sh
# iOS Simulator (the app must already be installed on the booted simulator)
xcrun simctl launch booted dev.luke.Backtrack -MotifDemoData YES

# Mac
open -a /path/to/Motif.app --args -MotifDemoData YES
```

Or add `-MotifDemoData YES` under the scheme's Run → Arguments in Xcode.

Before capturing on a simulator, set a clean status bar:

```sh
xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl io booted screenshot ~/Desktop/motif-iphone-01.png
```

Things to check in every image:

- **Album art:** guideline 4.5.2(ii) allows cover art in App Store screenshots that show the app
  working, and forbids it in other marketing. Screenshots of the app in use are fine; don't
  reuse the covers in a banner or an ad.
- **No Spotify:** capture the menu bar while Music is playing. Spotify support is a side
  feature, and another company's name in a screenshot only invites a trademark question.
- **No personal data:** no real Last.fm username, no real iCloud account name in Settings.
  Use a made-up Last.fm name if the Last.fm screen is included.
- **Widgets:** check the widgets show sample data too. They read the shared store directly, so
  if demo mode doesn't reach them, capture them after some real listening on a test account
  instead.
- **One appearance:** light or dark for the whole set, not a mix.

The macOS menu bar extra's window isn't exposed to the accessibility API, so it can't be
captured by script. Open it by hand and use ⇧⌘4, then Space, then click, or ⇧⌘5 for the whole
screen.

## iPhone (6.9", portrait)

Captions are written to be set as a line of text above each screenshot. Keep them short enough
to read at App Store thumbnail size.

| # | Screen | What should be visible | Caption |
|---|---|---|---|
| 1 | Summary | Listening time for the week, trend against last week, top artist, a highlight | See where your listening goes |
| 2 | Top Charts | Top songs for the month, with covers and play counts | Your top songs, artists and albums |
| 3 | Summary, scrolled | Listening clock and weekday rhythm | When you listen, hour by hour |
| 4 | History | A full day of songs, with radio and on-demand songs mixed | Every song you've played |
| 5 | Song detail | A song with several plays, first and last heard | Every song has its own page |
| 6 | Radio / Play Back | Radio songs from today and the Play Back button | Hear today's radio songs again |
| 7 | Home Screen | Today and Last Played widgets next to other apps | Today's listening on your Home Screen |
| 8 | Search | A search with results across songs and artists | Find anything you've heard |

Optional ninth: Settings with Last.fm connected (fake username), caption "Scrobbles to Last.fm,
if you want it to".

## iPad (13")

The same eight, captured in **landscape** wherever the iPad layout shows a sidebar or two
columns. That layout is the reason to have a separate iPad set at all. Portrait is fine
for any screen that is still a single column. Same captions.

## Mac (2880 × 1800)

Capture on a plain desktop picture with other windows hidden. The menu bar should show the
Motif item.

| # | Screen | What should be visible | Caption |
|---|---|---|---|
| 1 | Main window, Summary | Week at a glance with listening time, trend and highlights | Your listening, remembered |
| 2 | Menu bar extra open | Now playing with cover and transport controls, recent songs below | What's playing, from the menu bar |
| 3 | History | The table with a song selected and the inspector open | Every song, with the details |
| 4 | Top Charts | Top artists for the year | Your year in artists |
| 5 | Statistics | Listening clock and weekday rhythm | When you listen, hour by hour |
| 6 | Desktop widgets | Today and Weekly widgets on the desktop | Today's listening on your desktop |
| 7 | Settings | General pane with menu bar options, open at login | Menu bar, Dock and login options |

## Optional: app previews

Up to three videos per set, 15 to 30 seconds. Not needed for 1.0. If one is made, the Mac menu
bar extra updating as the song changes is the clearest thing Motif does that a still can't
show.
