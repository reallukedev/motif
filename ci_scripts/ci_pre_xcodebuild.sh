#!/bin/sh
# Xcode Cloud runs this before each xcodebuild command. See docs/Releasing.md, "Xcode Cloud".

set -e

# An archive is what reaches TestFlight. Without the Last.fm credentials it still builds
# and uploads, and every tester gets "This build has no Last.fm API key", so stop here.
# Build and test actions don't need them.
if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  if [ -z "$MOTIF_LASTFM_API_KEY" ] || [ -z "$MOTIF_LASTFM_SECRET" ]; then
    echo "error: MOTIF_LASTFM_API_KEY and MOTIF_LASTFM_SECRET must be set as secret"
    echo "environment variables in this workflow's Environment settings to archive."
    exit 1
  fi
fi
