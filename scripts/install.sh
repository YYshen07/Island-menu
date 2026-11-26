#!/bin/sh
# Build and install into /Applications, then launch. The fan helper is a launch daemon that runs
# from inside the app bundle, so the app has to live at a stable path outside the user's folders.
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle.sh >/dev/null
DEST="/Applications/Island Menu.app"
pkill -x IslandMenu 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "build/Island Menu.app" "$DEST"
open "$DEST"
echo "$DEST"
