#!/bin/sh
# Build the app and zip it for distribution: build/IslandMenu-<version>.zip
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle.sh >/dev/null
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
OUT="build/IslandMenu-$VERSION.zip"
rm -f "$OUT"
ditto -c -k --keepParent "build/Island Menu.app" "$OUT"
echo "$OUT"
