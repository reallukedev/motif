#!/bin/bash
# Renders the app icon to PNG with Icon Composer's command-line tool, for the README and
# anywhere else that needs a flat image. The icon itself is Apps/Shared/Resources/AppIcon.icon;
# edit it in Icon Composer.
set -euo pipefail
cd "$(dirname "$0")/.."
# Icon Composer lives inside Xcode, or on its own in /Applications. (The ictool that xcrun
# finds is a different tool.)
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ictool" ] || ictool="/Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ictool" ] || { echo "Icon Composer isn't installed (it comes with Xcode)."; exit 1; }
mkdir -p images
"$ictool" Apps/Shared/Resources/AppIcon.icon --export-image --output-file images/icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
echo "Wrote images/icon.png"
