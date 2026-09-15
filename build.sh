#!/bin/bash
# Builds both apps with the right signing.
#
# The macOS app must be signed with the real team. CODE_SIGNING_ALLOWED=NO strips the
# App Group entitlement, and the app falls back to an in-memory store with no data.
#
#   ./build.sh [all]   signed macOS build with its checks, iOS simulator build, tests
#   ./build.sh mac     signed macOS build, then checks the entitlements actually landed
#   ./build.sh ios     iOS simulator build
#   ./build.sh test    MotifCore tests on macOS and the iOS Simulator
#   ./build.sh ci      what CI runs: tests on both, then unsigned iOS and macOS builds
set -e
# Uses whichever Xcode `xcode-select -p` points at; set DEVELOPER_DIR to override.
cd "$(dirname "$0")"

# `swift test` only runs on the Mac, so this runs the package tests in the Simulator, on an
# iPhone from the newest iOS runtime. Same as the iOS test job in CI.
ios_test() {
  local udid
  udid="$(xcrun simctl list devices available | awk '
    /^-- iOS / { ios = 1; next }
    /^-- /     { ios = 0; next }
    ios && /iPhone/ { match($0, /[0-9A-F-]{36}/); id = substr($0, RSTART, RLENGTH) }
    END { print id }')"
  if [ -z "$udid" ]; then
    echo "✗ no iPhone simulator. Add an iOS runtime in Xcode › Settings › Components."
    return 1
  fi
  # Without -collect-test-diagnostics never, a failing test waits 10 minutes for a
  # simulator sysdiagnose.
  (
    cd MotifCore && xcodebuild test -scheme MotifCore-Package -destination "id=$udid" \
      -skipPackagePluginValidation -collect-test-diagnostics never 2>&1 \
      | grep -E "error:|recorded an issue|Test run with"
    exit "${PIPESTATUS[0]}"
  )
}

case "${1:-all}" in
  mac|all)
    echo "── macOS (signed)"
    # Automatic signing creates the iCloud container. Without -allowProvisioningUpdates the
    # build fails with "no profiles were found", which doesn't mention iCloud.
    xcodebuild -project Motif.xcodeproj -scheme "Motif (macOS)" \
      -configuration Debug -allowProvisioningUpdates build 2>&1 | grep -E "error:|warning: .*deprecat|BUILD" | sort -u
    # xcodebuild's status, not grep's. Otherwise a failed build carries on and the checks
    # below inspect the previous build's product.
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      echo "✗ macOS build failed"
      exit 1
    fi
    APP=$(xcodebuild -project Motif.xcodeproj -scheme "Motif (macOS)" \
      -configuration Debug -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')
    if ! codesign -d --entitlements - "$APP" 2>&1 | grep -q "application-groups"; then
      echo "✗ macOS app has no App Group entitlement, so it would run with no database."
      exit 1
    fi
    echo "✓ App Group entitlement present"
    # Without this the app runs fine locally but never syncs.
    if ! codesign -d --entitlements - "$APP" 2>&1 | grep -q "icloud-container-identifiers"; then
      echo "✗ macOS app has no iCloud container entitlement, so it would never sync."
      exit 1
    fi
    echo "✓ iCloud container entitlement present"
    WIDGET="$APP/Contents/PlugIns/MotifWidgets.appex"
    if [ ! -d "$WIDGET" ]; then
      echo "✗ widget extension not embedded, so the widget would simply not appear."
      exit 1
    fi
    # The widget reads the shared store too; without the entitlement it shows nothing.
    if ! codesign -d --entitlements - "$WIDGET" 2>&1 | grep -q "application-groups"; then
      echo "✗ widget extension has no App Group entitlement, so it would show an empty widget."
      exit 1
    fi
    echo "✓ widget embedded and entitled"
    ;;
esac

case "${1:-all}" in
  ios|all)
    echo "── iOS"
    xcodebuild -project Motif.xcodeproj -scheme "Motif (iOS)" -configuration Debug \
      -destination "platform=iOS Simulator,name=iPhone Air" CODE_SIGNING_ALLOWED=NO \
      build 2>&1 | grep -E "error:|BUILD" | sort -u
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      echo "✗ iOS build failed"
      exit 1
    fi
    ;;
esac

case "${1:-all}" in
  test|all)
    echo "── tests (macOS)"
    (
      cd MotifCore && swift test 2>&1 | grep -E "Test run with|recorded an issue"
      if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "✗ tests failed"
        exit 1
      fi
    )
    echo "── tests (iOS Simulator)"
    if ! ios_test; then
      echo "✗ iOS tests failed"
      exit 1
    fi
    ;;
esac

# Same steps as .github/workflows/ci.yml. Unsigned, so it only proves the apps compile;
# don't run the Mac app it builds (no App Group, so no data). Not part of `all`.
case "${1:-all}" in
  ci)
    xcodebuild -version

    echo "── tests (macOS)"
    if ! (cd MotifCore && swift test); then
      echo "✗ tests failed"
      exit 1
    fi

    echo "── tests (iOS Simulator)"
    if ! ios_test; then
      echo "✗ iOS tests failed"
      exit 1
    fi

    # CI generates the project from a clean checkout, so this does too.
    if ! command -v xcodegen >/dev/null 2>&1; then
      echo "✗ xcodegen not found. Install it with: brew install xcodegen"
      exit 1
    fi
    xcodegen generate --quiet

    # Same flags as CI. Uses xcbeautify if installed, otherwise greps like the modes above.
    ci_build() {
      local args=(
        -project Motif.xcodeproj -scheme "$1" -configuration Debug -destination "$2"
        -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
      )
      if command -v xcbeautify >/dev/null 2>&1; then
        xcodebuild "${args[@]}" 2>&1 | xcbeautify
        return "${PIPESTATUS[0]}"
      fi
      xcodebuild "${args[@]}" 2>&1 | grep -E "error:|BUILD" | sort -u
      return "${PIPESTATUS[0]}"
    }

    echo "── iOS (unsigned)"
    if ! ci_build "Motif (iOS)" "generic/platform=iOS Simulator"; then
      echo "✗ iOS build failed"
      exit 1
    fi

    echo "── macOS (unsigned, compile check only)"
    if ! ci_build "Motif (macOS)" "generic/platform=macOS"; then
      echo "✗ macOS build failed"
      exit 1
    fi
    echo "✓ tests pass and both apps build"
    ;;
esac
