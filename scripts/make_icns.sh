#!/bin/sh
# Regenerate assets/icon/AppIcon.png and AppIcon.icns from scripts/make_icon.swift.
set -eu
cd "$(dirname "$0")/.."
mkdir -p assets/icon
swift scripts/make_icon.swift assets/icon/AppIcon.png
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/icon/AppIcon.png --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" assets/icon/AppIcon.png --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/icon/AppIcon.icns
echo assets/icon/AppIcon.icns
