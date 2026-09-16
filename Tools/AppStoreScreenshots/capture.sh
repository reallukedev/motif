#!/bin/bash
# Captures the raw iPhone and Mac screens that the App Store frames are built from.
#
#   ./Tools/AppStoreScreenshots/capture.sh          (writes to build/raw/{iphone,mac})
#   python3 Tools/AppStoreScreenshots/render.py     (then builds the framed set)
#
# Both apps run on sample data (-MotifDemoData YES), so no real history, iCloud or Last.fm
# is touched. The Mac window is found by the demo process's PID, so a copy of Motif you
# already have running is never captured. The Mac capture passes -AppleAccentColor 0 to
# the demo process only, so it's drawn in red whatever accent colour the Mac is set to.
# The Mac shots need Screen Recording permission for your terminal.
set -euo pipefail
cd "$(dirname "$0")/../.."

derived="build/screenshots-derived-data"
out="build/raw"
iphone="${IPHONE_SIMULATOR:-iPhone 18 Pro Max}"
mkdir -p "$out/iphone" "$out/mac"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null
bundle_id="$(xcodebuild -project Motif.xcodeproj -scheme "Motif (iOS)" -showBuildSettings 2>/dev/null | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER /{print $2; exit}')"

echo "iPhone"
udid="$(xcrun simctl list devices available | grep -F "$iphone (" | head -1 | grep -oE '[0-9A-F-]{36}')"
[ -n "$udid" ] || { echo "No simulator called $iphone"; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl status_bar "$udid" clear
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100 \
  --operatorName ""
xcrun simctl ui "$udid" appearance light

xcodebuild -project Motif.xcodeproj -scheme "Motif (iOS)" -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$derived" build -quiet
xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/Motif.app"

# Opening another app first stops the status bar showing a "◂ back to" link.
xcrun simctl launch "$udid" com.apple.Preferences >/dev/null
sleep 2
xcrun simctl terminate "$udid" com.apple.Preferences

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle_id" -MotifDemoData YES -statsRange month "$@" >/dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot "$out/iphone/$name.png" >/dev/null 2>&1
  echo "  $name"
}
shot summary
shot charts-songs -MotifTab charts -chartKind songs
shot rhythm -MotifScroll rhythm
shot history -MotifTab history
shot artist -MotifOpen "artist:mara solis"
shot records -MotifScroll records
xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true

echo "Mac"
xcodebuild -project Motif.xcodeproj -scheme "Motif (macOS)" -configuration Debug \
  -derivedDataPath "$derived" -allowProvisioningUpdates build -quiet
app="$derived/Build/Products/Debug/Motif.app/Contents/MacOS/Motif"

window_of() {
  swift -e 'import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String]!); break
}' "$1"
}

mac_shot() {
  local name="$1"; shift
  "$app" -MotifDemoData YES -MotifActivate YES -AppleAccentColor 0 "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 8
  local wid
  wid="$(window_of "$pid")"
  if [ -n "$wid" ]; then
    screencapture -l "$wid" -o -x "$out/mac/$name.png"
    echo "  $name"
  else
    echo "  $name: no window found"
  fi
  kill "$pid"
  wait "$pid" 2>/dev/null || true
}
mac_shot summary -statsRange month
mac_shot history -statsRange month -MotifSidebar history
mac_shot artists-year -statsRange year -MotifSidebar topArtists
mac_shot rhythm -statsRange month -MotifScroll rhythm
mac_shot artist -statsRange month -MotifOpen "artist:mara solis"

echo "Saved to $out"
