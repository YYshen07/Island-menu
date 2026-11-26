#!/bin/sh
# Build a release binary and wrap it in build/Island Menu.app.
# Signs with a Developer ID Application certificate when one is in the keychain (override with
# SIGN_IDENTITY), otherwise ad-hoc.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Island Menu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/IslandMenu "$APP/Contents/MacOS/IslandMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp assets/model/macbook-pro-14.usdz "$APP/Contents/Resources/"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "$APP"
