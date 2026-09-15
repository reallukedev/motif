# Security policy

## Reporting a vulnerability

Report security problems privately through GitHub's private vulnerability reporting: open
the repository's Security tab and choose "Report a vulnerability", or go straight to
[the advisory form](https://github.com/reallukedev/motif/security/advisories/new).

Don't open a public issue, pull request or discussion for a vulnerability.

Please include what you found, how to reproduce it, the platform and OS version, and the
commit or release you tested. You can expect an acknowledgement within a week. Motif is
maintained by one person, so a fix may take longer, but you'll be kept informed, and credited
in the advisory if you'd like to be.

## Supported versions

Security fixes are made on `main` and included in the next release. Older releases are not
patched.

## Scope

Motif has no server. What there is to attack is the app, its extensions, and the data they
keep on the device and in iCloud.

The Last.fm session key never expires and is enough by itself to scrobble as the user, so
Motif stores it in the Keychain and not in `UserDefaults` or the App Group container. Any way
of getting at it is in scope, whether through another app, an extension that shouldn't have
it, a log or crash report, or a request to anywhere other than Last.fm.

The Last.fm API key and shared secret identify the application. They're read from the
gitignored `Config/Secrets.xcconfig`, and the tracked `Config/Motif.xcconfig` leaves them
empty. A commit, workflow or build step that would publish them is in scope. Any Last.fm
desktop client has to ship its secret inside the app, where it can be extracted, and that
alone is a limitation of Last.fm's authentication that Motif can't fix.

Listening history is stored with SwiftData in an App Group container that only Motif's
widgets share, and mirrored to the user's private CloudKit database. Report anything that
lets another app or another iCloud user read it, or that sends it anywhere except the user's
iCloud and, if connected, Last.fm.

The Mac app sends Apple events to Music and Spotify under scripting-target entitlements
limited to specific access groups. A way to make Motif control another app, or run a script,
beyond those groups is in scope.

### Out of scope

- Vulnerabilities in Apple's frameworks, Apple Music, iCloud or Last.fm themselves. Please
  report those to Apple or Last.fm.
- Attacks that need a jailbroken or already-compromised device, or physical access to an
  unlocked one.
- Missing hardening with no demonstrated impact.

## Keeping your own credentials safe

If you build Motif yourself, keep your Last.fm key and secret in `Config/Secrets.xcconfig`,
which is gitignored, and never paste them into an issue, a screenshot or a log. If a secret
does leak, register a new Last.fm API application and stop using the old one.
