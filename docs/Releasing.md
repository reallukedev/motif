# Releasing Motif

How to get a build of Motif from this repository onto the App Store, for iOS and for macOS.
The first half is one-time setup. The second half is what to do for every release.

Everything here assumes the maintainer's team (`W3Y3Z7CJH2`) and the published bundle
identifier, `dev.luke.Backtrack`. That identifier predates the name Motif and is kept on
purpose: the App Group, the iCloud container, the Keychain entry for Last.fm and the MusicKit
registration are all keyed to it. Don't change it for a release.

| Thing | Identifier |
|---|---|
| App (iOS and macOS) | `dev.luke.Backtrack` |
| Widget extension (both) | `dev.luke.Backtrack.Widgets` |
| App Group, iOS | `group.dev.luke.Backtrack` |
| App Group, macOS | `W3Y3Z7CJH2.group.dev.luke.Backtrack` |
| iCloud container | `iCloud.dev.luke.Backtrack` |
| Schemes | `Motif (iOS)`, `Motif (macOS)` |
| Build settings | `Config/Motif.xcconfig` (plus the gitignored `Config/Secrets.xcconfig`) |

## Part 1: one-time setup

Do these once, in this order, before the first upload.

### 1. Apple Developer account

- [ ] Paid Apple Developer Program membership for the team, and the Program License Agreement
  accepted (Account → Membership; a pending agreement blocks uploads with an unhelpful error).
- [ ] In App Store Connect → Business: the Free Apps agreement is always active; if Motif will
  be paid, the **Paid Apps agreement**, tax forms and bank details must be complete and
  "Active" before the app can go on sale.
- [ ] Xcode signed in to an account on the team (Xcode → Settings → Accounts), or an App Store
  Connect API key with the App Manager role for command-line uploads (see Part 2, step 5).

### 2. Identifiers and capabilities

Automatic signing (`CODE_SIGN_STYLE = Automatic`, and `-allowProvisioningUpdates` on the
command line) creates most of this the first time it builds. The one part it can't do is
marked.

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

- [ ] **App ID `dev.luke.Backtrack`** (explicit, not wildcard) with:
  - [ ] **App Groups**: `group.dev.luke.Backtrack` assigned.
  - [ ] **iCloud**: CloudKit, container `iCloud.dev.luke.Backtrack` assigned.
  - [ ] **MusicKit**, under the **App Services** tab. *Not done by automatic signing.* Without
    it every catalog search and playlist write fails with `developerTokenRequestFailed`, and the
    build itself looks fine.
- [ ] **App ID `dev.luke.Backtrack.Widgets`** with **App Groups** (`group.dev.luke.Backtrack`).
- [ ] The macOS App Group (`W3Y3Z7CJH2.group.…`) is team-prefixed, so it needs no portal
  registration.

One App ID serves both platforms. An explicit App ID isn't tied to iOS or macOS.

### 3. CloudKit: deploy the schema to Production

**This is the step that breaks sync for everyone if it's missed, and nothing in the build or
the upload will warn you.**

CloudKit has two environments per container, **Development** and **Production**, with separate
schemas and separate data. Which one an app talks to is set by the
`com.apple.developer.icloud-container-environment` entitlement:

- Builds run from Xcode, and anything signed for development, use **Development**.
- TestFlight and App Store builds are signed for distribution and use **Production**.
  (`Config/ExportOptions-AppStore.plist` also says `iCloudContainerEnvironment = Production`
  explicitly.)

In Development, SwiftData creates CloudKit record types and fields automatically the first time
it saves a record of each kind. That is how Motif's schema came to exist. **Production never
does that.** It only accepts records whose types and fields have already been deployed to it.
Until the schema is deployed, every save a TestFlight or App Store copy of Motif makes to iCloud
is rejected.

Nobody will see an error. `MotifStore` is deliberately built so that a sync failure never costs
the local database. It keeps working locally and sync quietly does nothing. The app looks
healthy, and nothing reaches the user's other devices. The first sign would be a review saying
"iCloud sync doesn't work".

To deploy:

1. Make sure the Development schema is complete. Run a **Debug** build on a device or Mac signed
   in to iCloud and use the app enough that every model type is saved at least once: record a
   few songs, including from a radio station, so there is a `Capture`, a `Session` and a
   `Station`. (`StatsSnapshot` is in the schema but the app never saves one, so it can't reach
   CloudKit in either environment and doesn't matter here.) Wait a minute for the export.
2. Open the [CloudKit Console](https://icloud.developer.apple.com/) → `iCloud.dev.luke.Backtrack`
   → **Development** → Schema → Record Types. Check that `CD_Capture`, `CD_Session` and
   `CD_Station` exist, and that `CD_Capture` has every attribute the current `Capture` model
   has (they appear as `CD_<attribute name>`).
3. Choose **Deploy Schema Changes…**, review the list, and deploy to Production.
4. Confirm under **Production** → Schema that the same record types are there.

Rules that apply from now on:

- **Production schema is additive.** Once deployed, a record type or field can't be deleted or
  have its type changed. Model changes after 1.0 must only add things: new optional attributes,
  or ones with defaults, and new optional relationships. Renaming a property counts as removing
  one and adding another.
- **Deploy before you ship.** Any release that adds a model attribute needs that attribute
  deployed to Production *before* the build reaches TestFlight testers, or their saves fail the
  same silent way.
- **Test sync on TestFlight, not just from Xcode.** A Debug build proves only the Development
  environment. Part 2, step 6 covers this.

### 4. Last.fm API account for production

- [ ] Create an API account at <https://www.last.fm/api/account/create> under the name "Motif",
  with a description and the repository URL. The callback URL can be left blank; Motif uses the
  desktop authentication flow.
- [ ] Put the key and shared secret in `Config/Secrets.xcconfig` on the machine that makes
  release builds (copy `Config/Secrets.example.xcconfig`). The file is gitignored; never commit
  it, paste it into an issue, or show it in a screen recording.

```
MOTIF_LASTFM_API_KEY = …
MOTIF_LASTFM_SECRET = …
```

The build copies both into each app's Info.plist. If the file is missing, the build succeeds
and the app says "This build has no Last.fm API key" when someone taps Connect. The pre-flight
check below catches that.

### 5. App Store Connect records

- [ ] **Decide Universal Purchase first** (see "Pricing and Universal Purchase" below), because
  it decides whether there is one app record or two.
- [ ] My Apps → **+** → New App. Platforms: iOS (and macOS if universal). Name: "Motif", or the
  fallback in `docs/AppStore/Metadata.md` if the name is taken. Bundle ID `dev.luke.Backtrack`.
  SKU: see Metadata.md. Creating the record reserves the name.
- [ ] App Information: subtitle, categories (Music / Lifestyle), content rights, age rating
  (answers in `docs/AppStore/Metadata.md`).
- [ ] **Privacy policy URL**: `https://github.com/reallukedev/motif/blob/main/PRIVACY.md`. The
  repository has to be public by the time the app is submitted, or the link is a 404 to App
  Review.
- [ ] App Privacy: "Data Not Collected" (reasoning in `docs/AppStore/PrivacyNutritionLabel.md`).
- [ ] Pricing and Availability: price, countries, and whether to make the app available on
  Apple Silicon Macs as an iPad app. Set that last one to **no**: there is a real Mac app, and
  `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` in `project.yml` already stops Xcode offering it.
- [ ] Export compliance is already answered by `ITSAppUsesNonExemptEncryption = false` in both
  Info.plists (Motif only uses HTTPS), so App Store Connect won't ask per build.

### Pricing and Universal Purchase

Both apps are built with the same bundle identifier, `dev.luke.Backtrack`. In App Store Connect
that means **one app record with two platforms**, which is Universal Purchase: one price, and
buying on either platform unlocks both. That's the only arrangement the current identifiers
allow.

Selling the two separately (a price for iPhone and iPad, another for Mac) needs a second app
record, which needs a different bundle identifier for the Mac app, for example
`dev.luke.Backtrack.mac`. That's a real change with consequences to plan for:

- The Mac App Group is derived from the bundle identifier in `Config/Motif.xcconfig`, as are the
  iCloud container and the Keychain service. The Mac app would need those pinned to the current
  values (`iCloud.dev.luke.Backtrack` in particular) so that the Mac and the iPhone keep syncing
  through the same container. A different container means no sync between them at all.
- A new App ID for the Mac, with MusicKit, App Groups and the same iCloud container assigned.
- A second record in App Store Connect with its own screenshots, reviews and ratings.

Nothing is on the App Store yet, so either choice can still be made cheaply. After 1.0 ships,
moving between them means a new app record and, for Universal → separate, asking existing Mac
customers to move to a different app. **This is the maintainer's decision to make before
creating the App Store Connect record.** The simplest path, and the one this runbook assumes
from here, is Universal Purchase.

## Part 2: every release

### Pre-flight checklist

Run through this before archiving. Most of these items catch a build that would upload without
complaint and still be broken.

- [ ] `main` is green: `./build.sh test` passes (or `swift test` in `MotifCore/`).
- [ ] The version is bumped (next section) and the build number is higher than any build
  uploaded for this version.
- [ ] `Config/Secrets.xcconfig` exists and holds the **production** Last.fm key and secret.
- [ ] The iOS Info.plist lists all four orientations for iPad. Upload validation rejects an
  iPad-capable app that leaves one out (ITMS-90474). `UISupportedInterfaceOrientations~ipad`
  with portrait, portrait upside down, landscape left and landscape right is the usual fix.
- [ ] No development-only switches left on: the demo-data argument lives only in schemes and
  launch arguments, never in an Info.plist or a default.
- [ ] The CloudKit schema in Production includes every model attribute this release uses
  (Part 1, step 3). If a model changed since the last release, deploy first.
- [ ] `plutil -lint` passes on every Info.plist, entitlements file, privacy manifest and
  `Config/ExportOptions-AppStore.plist`:
  ```sh
  plutil -lint Apps/*/Resources/*.plist Apps/*/Resources/*.entitlements Apps/*/Resources/PrivacyInfo.xcprivacy \
    Widgets/*/Resources/*.plist Widgets/*/Resources/*.entitlements Widgets/*/Resources/PrivacyInfo.xcprivacy \
    Config/ExportOptions-AppStore.plist
  ```
- [ ] The privacy manifests still match the code (the audit commands at the end of
  `docs/AppStore/PrivacyNutritionLabel.md`).
- [ ] `PRIVACY.md` still describes what the app does, and its effective date is updated if it
  changed.
- [ ] Screenshots, description and review notes still match this version's screens.
- [ ] If Spotify support is in the Mac build, its scripting access groups have been checked
  (`docs/AppStore/ReviewNotes.md`, "Apple events on the Mac").

### 1. Bump the version

Both numbers live in `Config/Motif.xcconfig`, and every Info.plist reads them, so this is the
only edit:

```
MARKETING_VERSION = 1.0          // what people see; x.y or x.y.z
CURRENT_PROJECT_VERSION = 1      // the build number
```

- `MARKETING_VERSION` goes up for each release submitted to review (1.0 → 1.0.1 → 1.1).
- `CURRENT_PROJECT_VERSION` must be higher than every build already uploaded for that version.
  The simplest rule is to never reuse a number and never go down: increment it for every upload,
  TestFlight-only ones included. iOS and macOS builds may share a number.
- `ExportOptions-AppStore.plist` sets `manageAppVersionAndBuildNumber` to `false`, so Xcode
  won't quietly change the build number during upload. If the number was already used, the
  upload fails and says so, which is the behaviour you want.

Commit the bump on its own (`Bump version to 1.0 (1)`).

### 2. Generate the project

The Xcode project is generated from `project.yml` and isn't in the repository.

```sh
xcodegen generate
```

Do this every time, even when nothing seems to have changed. New files are invisible to a build
from a stale project.

### 3. Archive

From the repository root. `build/` is gitignored.

```sh
xcodebuild archive \
  -project Motif.xcodeproj \
  -scheme "Motif (iOS)" \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/Motif-iOS.xcarchive \
  -allowProvisioningUpdates

xcodebuild archive \
  -project Motif.xcodeproj \
  -scheme "Motif (macOS)" \
  -configuration Release \
  -destination generic/platform=macOS \
  -archivePath build/Motif-macOS.xcarchive \
  -allowProvisioningUpdates
```

Both schemes archive the Release configuration (set in `project.yml`); `-configuration Release`
just makes it explicit. The widget extension is a dependency of each app target, so it's built,
signed and embedded as part of the same archive.

### 4. Check the archives before uploading

Five checks, each for a failure that would otherwise only show up in someone's hands:

```sh
IOS=build/Motif-iOS.xcarchive/Products/Applications/Motif.app
MAC=build/Motif-macOS.xcarchive/Products/Applications/Motif.app

# Version and build number are the ones you meant.
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "$IOS/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "$MAC/Contents/Info.plist"

# The Last.fm key made it in. Empty output means Secrets.xcconfig was missing: stop here.
/usr/libexec/PlistBuddy -c "Print :MotifLastFMAPIKey" "$IOS/Info.plist"
/usr/libexec/PlistBuddy -c "Print :MotifLastFMAPIKey" "$MAC/Contents/Info.plist"

# App Group and iCloud entitlements are present on the app and the App Group on the widget.
codesign -d --entitlements - "$IOS" 2>/dev/null | grep -E "application-groups|icloud-container-identifiers"
codesign -d --entitlements - "$IOS/PlugIns/MotifWidgets.appex" 2>/dev/null | grep application-groups
codesign -d --entitlements - "$MAC" 2>/dev/null | grep -E "application-groups|icloud-container-identifiers|scripting-targets"
codesign -d --entitlements - "$MAC/Contents/PlugIns/MotifWidgets.appex" 2>/dev/null | grep application-groups

# A privacy manifest in every bundle: expect two lines per platform (app and widget).
find "$IOS" "$MAC" -name PrivacyInfo.xcprivacy
```

Then, in Xcode's Organizer (Window → Organizer → Archives), select each archive and choose
**Generate Privacy Report**. It should list User Defaults with reasons CA92.1 and 1C8F.1 and
nothing else.

The archive is signed for development at this point, so its entitlements either name the
Development iCloud environment or leave the key out, which also means Development. Distribution
signing during export switches that to Production. To see the
final entitlements, do a local export once (below) and inspect that copy.

### 5. Export and upload

`Config/ExportOptions-AppStore.plist` uses the App Store Connect method with
`destination = upload`, so exporting *is* uploading. No `.ipa` or `.pkg` is left behind to
handle, and `xcrun altool` isn't needed (it's deprecated for this).

```sh
xcodebuild -exportArchive \
  -archivePath build/Motif-iOS.xcarchive \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist \
  -exportPath build/export-iOS \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath build/Motif-macOS.xcarchive \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist \
  -exportPath build/export-macOS \
  -allowProvisioningUpdates
```

The same options file serves both platforms. Automatic signing picks the Apple Distribution
certificate for iOS and the Mac App Distribution and Mac Installer Distribution certificates for
the Mac, creating them in the cloud if needed. `uploadSymbols` sends dSYMs so crash reports in
Xcode's Organizer are symbolicated.

To authenticate, an Xcode account signed in is enough. Without one (a CI
machine, say), add an App Store Connect API key to both commands:

```sh
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
  -authenticationKeyID XXXXXXXXXX \
  -authenticationKeyIssuerID 00000000-0000-0000-0000-000000000000
```

The key comes from App Store Connect → Users and Access → Integrations → App Store Connect API,
and needs the App Manager role. Keep the `.p8` out of the repository.

To inspect a build without uploading it, copy the options file, set `destination` to
`export`, and run the same command. You get a signed `.ipa` (iOS) or `.pkg` (Mac) in the export
path, signed exactly as the upload would be. Check the Production environment there:

```sh
codesign -d --entitlements - Payload/Motif.app | grep -A1 icloud-container-environment   # after unzipping the .ipa
```

Transporter and Xcode's Organizer (Distribute App → App Store Connect → Upload) are equivalent
alternatives to the command line. `xcrun notarytool` is only for Developer ID builds distributed
outside the App Store and plays no part here.

### 6. TestFlight

Builds show up under TestFlight in App Store Connect after processing, usually within half an
hour. Export compliance is pre-answered.

1. Add the build to an internal testing group. Internal testers (members of the team) get it
   without review. External testers need a short beta review the first time.
2. Fill in "What to Test". For 1.0, reuse the What's New text from `docs/AppStore/Metadata.md`.
3. Install on real hardware and check, at least:
   - [ ] First launch asks for Apple Music access, and history appears (Recently Played import).
   - [ ] A radio station is captured, and "Heard on Radio" gets the song.
   - [ ] Play Back plays audibly and the played song is marked as played back.
   - [ ] **iCloud sync between two devices** (an iPhone and the Mac, same Apple Account).
     This is the only place the Production environment is exercised before customers get it.
     Something recorded on one should appear on the other within a few minutes. If it never
     does, the CloudKit schema isn't deployed (Part 1, step 3).
   - [ ] Last.fm: Connect, approve in the browser, and see a scrobble arrive on last.fm.
   - [ ] Widgets and the Control Center control render with real data.
   - [ ] Mac: the Automation prompt for Music appears, the menu bar controls work, and "Open at
     login" can be turned on and off.
   - [ ] Settings → Sync with iCloud shows sync as on, not a failure message.

macOS TestFlight builds install through the TestFlight app for Mac and use the same Production
environment.

### 7. Submit for review

In App Store Connect, under the version (iOS and macOS each have their own version page, even
in a single universal record):

- [ ] Attach the build.
- [ ] Screenshots for every required size (`docs/AppStore/Screenshots.md`).
- [ ] Promotional text, description, keywords, support and marketing URLs
  (`docs/AppStore/Metadata.md`).
- [ ] What's New (not shown for the first version).
- [ ] App Review Information: contact details, "Sign-in required" off, and the notes from
  `docs/AppStore/ReviewNotes.md` for that platform.
- [ ] Version release: **Manually release this version**, so the release can be timed and the
  two platforms can go out together.
- [ ] Submit.

If App Review replies with a question rather than a rejection, answer in Resolution Center. The
answers to the usual questions are in ReviewNotes.md.

### 8. Release

- [ ] Once both platforms are approved, release them from App Store Connect.
- [ ] Tag the commit that was archived, and push the tag:
  ```sh
  git tag -a v1.0 -m "Motif 1.0 (1)"
  git push origin v1.0
  ```
- [ ] Keep the `.xcarchive` files (Organizer keeps them in `~/Library/Developer/Xcode/Archives`
  if you archive there, otherwise copy `build/*.xcarchive` somewhere safe). They hold the
  dSYMs for this exact build.
- [ ] Watch Xcode's Organizer → Crashes and App Store Connect → Ratings and Reviews for the
  first few days. A review mentioning sync is the first thing to take seriously.
