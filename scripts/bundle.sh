#!/bin/sh
# Build a release binary and wrap it in build/Island Menu.app (ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Island Menu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/IslandMenu "$APP/Contents/MacOS/IslandMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
