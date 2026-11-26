#!/bin/sh
# Build and install into /Applications, then launch. The fan helper is a launch daemon that runs
# from inside the app bundle, so the app has to live at a stable path outside the user's folders.
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle.sh >/dev/null
DEST="/Applications/Island Menu.app"
pkill -x IslandMenu 2>/dev/null || true
# The system keeps the old widget extension process alive across an update; it would then fail to
# decode the new activity state, and the system would drop the alert the moment it is raised.
pkill -x IslandMenuWidgets 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "build/Island Menu.app" "$DEST"
open "$DEST"
echo "$DEST"
