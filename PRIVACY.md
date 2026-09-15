# Motif privacy policy

**Effective date: September 2026**

Motif is an app for iPhone, iPad and Mac that keeps a history of the music you play in Apple
Music and turns it into statistics. This policy explains what Motif stores, where it stores it,
and what leaves your device.

The short version is that **Motif DOES NOT collect your data.** I don't run any servers, and nothing Motif records is sent to me. Your listening history lives on your devices and in your own iCloud account. If you choose to connect Last.fm, Motif sends your listening to your Last.fm account, and nowhere else.

## What Motif stores, and where

### Your listening history

For each song Motif records, it keeps the title, artist, album, a link to the album artwork, the Apple Music identifier for the song, when you played it, whether it came from radio, from on-demand listening or from Apple Music's Recently Played list, and which radio station it was heard on. It also keeps whether it has been added to your "Heard on Radio" playlist, played back, or sent to Last.fm. All of this is stored in a database inside the app's own storage on your device. Motif's widgets read the same database, on the same device.

### A device identifier made by Motif

Motif creates a random identifier the first time it runs on a device and stores it with each song recorded on that device. It exists so that two of your devices don't both add the same song to your playlist. It is not your device's serial number or advertising identifier, it can't be used to identify you, and it is only ever stored on your devices and in your iCloud account.

### Your settings

Preferences such as your playlist name, which stations you've excluded, and how the menu bar looks are stored on each device. So is a list of the songs you have deleted, so that Motif doesn't add them back from Apple Music's Recently Played list.

### Your Last.fm sign-in, if you connect Last.fm

Your Last.fm username is stored with your settings on the device. The key that lets Motif scrobble on your behalf is stored in the device's Keychain, the system's secure storage for passwords. Neither is synced to iCloud or sent anywhere except to Last.fm.

## iCloud

If you're signed in to iCloud, Motif syncs your listening history between your devices using your private iCloud database. This is storage in your own iCloud account, provided by Apple under [Apple's privacy policy](https://www.apple.com/legal/privacy/). Only you, and Apple as your iCloud provider, can see what's in it.

What syncs are your listening history, including your listening sessions and the stations you've heard, and Motif's device identifier described above. What doesn't sync are your settings, your Last.fm sign-in, and the list of songs that you've deleted.

You can turn sync off in Motif's settings ("Sync with iCloud"); the change takes effect the next time Motif opens. You can also stop Motif using iCloud entirely in your device's iCloud settings.

## Apple Music

With your permission, Motif uses Apple's MusicKit to:

- See what's playing in Apple Music, so that it can record it
- Read your Recently Played list, so that it can fill in songs you played while Motif wasn't open
- Look up songs in the Apple Music catalog, so that each recorded song is matched to the right one
- Create a playlist called "Heard on Radio" in your library and add radio songs to it (you can turn this off in settings)
- Play songs, when you use Play Back.

These requests go directly from your device to Apple and are covered by [Apple's privacy policy](https://www.apple.com/legal/privacy/). Nothing Motif reads from Apple Music is sent elsewhere.

Songs that Motif has added to your "Heard on Radio" playlist stay there if you delete them from Motif, because Apple doesn't let apps remove songs from a playlist. You can remove them in the Music app.

You can withdraw Motif's access to Apple Music at any time in Settings → Privacy & Security → Media & Apple Music on iPhone and iPad, or System Settings → Privacy & Security → Media & Apple Music on Mac.

## On the Mac: controlling Music and Spotify

On the Mac, Motif asks Music, and Spotify if you have it, what is playing and sends them playback commands (play, pause, next, previous) from the menu bar. macOS asks for your permission the first time, and you can change your answer in System Settings → Privacy & Security → Automation.

Motif shows what Spotify is playing in the menu bar, but never records Spotify listening. When Spotify is playing, the menu bar may load the album cover from Spotify's servers, as the Spotify app itself does.

If you turn on automatic play-back on the Mac, Motif checks how many seconds have passed since you last used the keyboard, mouse or trackpad before it starts any music, so that it never plays to an empty room. It only reads that number of seconds, never what you typed or clicked, and it doesn't store or send it.

## Last.fm (optional)

Last.fm is a separate service with its own account and its own [privacy policy](https://www.last.fm/legal/privacy). Motif works fully without it.

If you connect your Last.fm account, Motif opens Last.fm's website in your browser so you can approve the connection there. Motif never sees your Last.fm password. From then on, Motif sends Last.fm the artist, title and album of each song you listen to, and the time you played it ("scrobbling"), plus what's playing right now. These are sent directly from your device to Last.fm over an encrypted connection, to your own Last.fm profile. Songs Motif found in Apple Music's Recently Played list, rather than saw playing, are only sent if you turn on the setting that allows it.

You can turn scrobbling off, or disconnect Last.fm, in Motif's settings at any time. Disconnecting deletes Motif's Last.fm key from that device. Scrobbles already sent stay on your Last.fm profile; you can delete them on Last.fm's website.

## What leaves your device

Motif connects only to:

- **Apple**, for Apple Music (through MusicKit), album artwork, and iCloud sync
- **Last.fm**, only if you connect your account
- **Spotify's image servers**, only if you use Spotify, on the Mac, only to show the cover of a song Spotify is playing

As with any internet connection, these services can see your device's IP address when Motif talks to them.

## What Motif doesn't do

- No analytics, usage tracking or advertising, and no third-party code that does any of these.
- No tracking across apps or websites, and no advertising identifier.
- No accounts: you never sign up for anything to use Motif.
- Your data is never sold or shared. I don't have it in the first place.

If you've chosen to share analytics with app developers in your device's settings, Apple may send me anonymous crash reports and usage figures for Motif. That is controlled by Apple and by you, in Settings → Privacy & Security → Analytics & Improvements (or System Settings on Mac), and it never includes your listening history.

## Deleting your data

- **Delete a song:** remove it from your history in Motif. It is deleted from every device synced through iCloud. The device you deleted it on also remembers the deletion, so Motif there won't add the song back from Recently Played.
- **Stop syncing:** turn off "Sync with iCloud" in Motif's settings, or turn off iCloud for Motif in your device's settings. To remove the copy already in iCloud, delete Motif's data from your iCloud storage settings where your device offers it (Settings → your name → iCloud → Manage Account Storage on iPhone and iPad; System Settings → your name → iCloud → Manage on Mac).
- **Disconnect Last.fm:** in Motif's settings. This removes the Last.fm key from the device. Scrobbles already on Last.fm are managed on Last.fm's website.
- **Delete the app:** removes Motif's database and settings from that device. Your history remains in iCloud until you delete it there, and on your other devices. On iPhone and iPad the system can keep Keychain items after an app is deleted, so disconnect Last.fm in Motif first if you want its key removed straight away.

## Children

Motif isn't directed at children and doesn't knowingly collect anything from anyone, of any age.

## Changes to this policy

If Motif's handling of your data changes, this page will be updated and the effective date above changed. The history of every change is public in the project's [repository](https://github.com/reallukedev/motif/commits/main/PRIVACY.md).

## Contact

Questions about privacy, or about anything else in Motif, are welcome as an issue on GitHub: <https://github.com/reallukedev/motif/issues>. Please don't include personal information in a public issue; if you need to share something privately, open an issue asking for a private contact and I'll reply there.
