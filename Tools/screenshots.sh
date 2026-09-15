#!/bin/bash
# Captures App Store and README screenshots from sample data.
#
#   ./Tools/screenshots.sh [out-dir]      (default: build/screenshots)
#
# Builds the Debug apps (the launch arguments that pick a screen only exist in Debug), then
# runs each on sample data with -MotifDemoData YES, which uses an in-memory store and never
# touches real history, iCloud or Last.fm. iPhone and iPad shots come out at the sizes App
# Store Connect wants (1320 × 2868 and 2064 × 2752). Mac shots are the main window at its
# default size; for 2880 × 1800 use a Retina display set to "Looks like 1440 × 900".
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build/screenshots}"
derived="build/screenshots-derived-data"
iphone="${IPHONE_SIMULATOR:-iPhone 18 Pro Max}"
ipad="${IPAD_SIMULATOR:-iPad Pro 13-inch (M5)}"
bundle_id="$(xcodebuild -project Motif.xcodeproj -scheme "Motif (iOS)" -showBuildSettings 2>/dev/null | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER /{print $2; exit}')"
mkdir -p "$out"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

capture_ios() {
  local device="$1" prefix="$2"
  local udid
  udid="$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')"
  [ -n "$udid" ] || { echo "No simulator called $device"; return 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$udid" appearance light

  xcodebuild -project Motif.xcodeproj -scheme "Motif (iOS)" -configuration Debug \
    -destination "id=$udid" -derivedDataPath "$derived" build -quiet
  xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/Motif.app"

  shot() {
    local name="$1"; shift
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$bundle_id" -MotifDemoData YES -statsRange month "$@" >/dev/null
    sleep 5
    xcrun simctl io "$udid" screenshot "$out/$prefix-$name.png" >/dev/null
    echo "  $prefix-$name.png"
  }
  shot 1-summary
  shot 2-charts -MotifTab charts -chartKind songs
  shot 3-rhythm -MotifScroll rhythm
  shot 4-history -MotifTab history
  shot 5-artist -MotifOpen "artist:mara solis"
  shot 6-highlights -MotifScroll highlights
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
}

echo "iPhone"
capture_ios "$iphone" iphone
echo "iPad"
capture_ios "$ipad" ipad

echo "Mac"
xcodebuild -project Motif.xcodeproj -scheme "Motif (macOS)" -configuration Debug \
  -derivedDataPath "$derived" -allowProvisioningUpdates build -quiet
app="$derived/Build/Products/Debug/Motif.app/Contents/MacOS/Motif"
window_id() {
  swift -e 'import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Motif" && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String]!); break
}'
}
mac_shot() {
  local name="$1"; shift
  "$app" -MotifDemoData YES -statsRange month "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 7
  screencapture -l "$(window_id)" -o -x "$out/mac-$name.png"
  kill "$pid"
  wait "$pid" 2>/dev/null || true
  echo "  mac-$name.png"
}
mac_shot 1-summary
mac_shot 2-artists -MotifSidebar topArtists
mac_shot 3-history -MotifSidebar history
mac_shot 4-rhythm -MotifScroll rhythm

echo "Saved to $out"
