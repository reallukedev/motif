#!/bin/sh
# Xcode Cloud runs this after cloning, once per action, from inside ci_scripts/.
# See docs/Releasing.md, "Xcode Cloud".

set -e

# project.yml, Config/ and the generated project all live at the repository root.
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# The project is gitignored and generated from project.yml, so it has to exist before
# Xcode Cloud looks for the workflow's scheme.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew install xcodegen
xcodegen generate

# Last.fm credentials come from the workflow's secret environment variables. The committed
# xcconfig leaves them empty and includes Config/Secrets.xcconfig if it exists, the same
# file a local release build uses. ci_pre_xcodebuild.sh stops an archive without them.
if [ -n "$MOTIF_LASTFM_API_KEY" ] && [ -n "$MOTIF_LASTFM_SECRET" ]; then
  printf 'MOTIF_LASTFM_API_KEY = %s\nMOTIF_LASTFM_SECRET = %s\n' \
    "$MOTIF_LASTFM_API_KEY" "$MOTIF_LASTFM_SECRET" > Config/Secrets.xcconfig
  echo "Wrote Config/Secrets.xcconfig"
else
  echo "MOTIF_LASTFM_API_KEY or MOTIF_LASTFM_SECRET not set; Last.fm will report it isn't set up."
fi
