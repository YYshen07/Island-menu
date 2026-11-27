#!/bin/sh
# Capture the README screenshots and clips from the built app. Only the card's own window is
# captured, so nothing else on screen ends up in the images.
# Usage: scripts/screenshots.sh <output dir> [extra app args, e.g. --notch]
set -eu
cd "$(dirname "$0")/.."
OUT="$1"; shift
# The fan section only shows its controls when the app runs from /Applications, so point APP there for the README set.
APP="${APP:-$PWD/build/Island Menu.app}"
mkdir -p "$OUT"
window() {
    swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Island Menu" {
    if let b = w["kCGWindowBounds"] as? [String: Any], (b["Height"] as? Double ?? 0) > 300, (b["Width"] as? Double ?? 0) == 560 { print(w["kCGWindowNumber"]!) }
}
SWIFT
}
send() { open -g -a "$APP" "islandmenu://$1"; }
shot() { screencapture -x -o -l "$WINDOW" "$OUT/$1.png"; }
# Frames at the capture's own pace (about 8 per second) for the given number of frames.
clip() {
    mkdir -p "$OUT/$1"
    i=0
    while [ "$i" -lt "$2" ]; do
        screencapture -x -o -l "$WINDOW" "$OUT/$1/$(printf %03d "$i").png"
        i=$((i + 1))
    done
}
pkill -x IslandMenu || true
sleep 1
open "$APP" --args --open --pin "$@"
sleep 5
WINDOW="$(window | head -1)"
shot side-a
send flip & clip flip 22
shot side-b
send lid & clip lid 22
shot lid-open
send lid; sleep 2
send flip; sleep 2
send bottom; sleep 2
shot bottom
send top; sleep 1
pkill -USR1 -x IslandMenu & clip close 8
pkill -USR1 -x IslandMenu & clip open 12
pkill -x IslandMenu
