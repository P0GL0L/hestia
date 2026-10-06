#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo=$(CDPATH= cd -- "$root/../.." && pwd)
swift build -c release --package-path "$repo" --product HestiaApp
app="$root/build/Hestia.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$repo/.build/release/HestiaApp" "$app/Contents/MacOS/Hestia"
cp "$root/Info.plist" "$app/Contents/Info.plist"
echo "$app"
