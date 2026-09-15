# Tools

## The app icon

The icon lives in `Apps/Shared/Resources/AppIcon.icon`, an Icon Composer document, so the
system can render it with Liquid Glass and produce the dark, clear and tinted variants on
its own. Open it in Icon Composer (it ships with Xcode) to change it. Both apps use the same
file.

It's three white arcs on a violet-to-pink gradient: progress rings for the statistics, and
the grooves of a record. The artwork is plain SVG in `AppIcon.icon/Assets`, so it diffs
cleanly.

`export-icon.sh` renders it to `docs/images/icon.png` for the README:

```
./Tools/export-icon.sh
```

## Screenshots

`screenshots.sh` builds the Debug apps and captures the App Store and README screenshots
from sample data:

```
./Tools/screenshots.sh            # writes to build/screenshots
```

It launches each app with `-MotifDemoData YES`, which fills an in-memory store with invented
listening and never touches real history, iCloud or Last.fm, plus the Debug-only launch
arguments in `Apps/Shared/App/LaunchScene.swift` that open a given tab, section or page.
iPhone and iPad images come out at App Store sizes. The Mac shots need Screen Recording
permission for your terminal (System Settings › Privacy & Security).
