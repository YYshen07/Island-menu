#!/bin/sh
# Build a release binary and wrap it in build/Island Menu.app.
# Signs with a Developer ID Application certificate when one is in the keychain (override with
# SIGN_IDENTITY), otherwise ad-hoc.
set -eu
cd "$(dirname "$0")/.."
# Live Activities need the macOS 27.3 SDK; use the Xcode beta when it is installed side by side.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode-beta.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
swift build -c release
# The widget extension (the Live Activity's views) is an Xcode target; everything else is SwiftPM.
xcodegen generate --quiet --spec Widgets/project.yml
xcodebuild -quiet -project Widgets/IslandMenuWidgets.xcodeproj -target IslandMenuWidgets -configuration Release SYMROOT=build build 2>/dev/null
APP="build/Island Menu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/IslandMenu "$APP/Contents/MacOS/IslandMenu"
cp .build/release/IslandMenuHelper "$APP/Contents/MacOS/IslandMenuHelper"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp Resources/dev.yan.islandmenu.helper.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp assets/model/macbook-pro-14.usdz "$APP/Contents/Resources/"
cp assets/icon/AppIcon.icns "$APP/Contents/Resources/"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
mkdir -p "$APP/Contents/PlugIns"
cp -R Widgets/build/Release/IslandMenuWidgets.appex "$APP/Contents/PlugIns/"
WIDGETS="$APP/Contents/PlugIns/IslandMenuWidgets.appex"
HELPER="$APP/Contents/MacOS/IslandMenuHelper"
# Nested code is signed first (the helper with its own identifier, the widget extension with its
# sandbox entitlement); the app's signature then seals them.
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --identifier dev.yan.islandmenu.helper --sign "$IDENTITY" "$HELPER"
    codesign --force --options runtime --timestamp --entitlements Widgets/Widgets.entitlements --sign "$IDENTITY" "$WIDGETS"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --identifier dev.yan.islandmenu.helper --sign - "$HELPER"
    codesign --force --entitlements Widgets/Widgets.entitlements --sign - "$WIDGETS"
    codesign --force --sign - "$APP"
fi
echo "$APP"
