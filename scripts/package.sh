#!/bin/sh
# Build the app and zip it for distribution: build/IslandMenu-<version>.zip
# If the notarytool keychain profile exists (NOTARY_PROFILE, default "islandmenu-notary"), the app
# is notarized and stapled first; otherwise the zip is left un-notarized.
set -eu
cd "$(dirname "$0")/.."
./scripts/bundle.sh >/dev/null
APP="build/Island Menu.app"
PROFILE="${NOTARY_PROFILE:-islandmenu-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
OUT="build/IslandMenu-$VERSION.zip"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$OUT"
    ditto -c -k --keepParent "$APP" "$OUT"
else
    echo "warning: notary profile '$PROFILE' not found; $OUT is not notarized" >&2
fi
echo "$OUT"
