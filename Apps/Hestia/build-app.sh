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
mkdir -p "$app/Contents/Resources"
cp "$repo/fixtures/rect-cottage.json" "$app/Contents/Resources/rect-cottage.json"
cp "$repo/tools/blender/hestia_render.py" "$app/Contents/Resources/hestia_render.py"

# The asset library for the live 3D view: materials, models, and sky, built once with Blender by
# tools/blender/hestia_library.py and kept in build/Library until the builder changes. HESTIA_LIBRARY_SOURCE
# names a library built elsewhere. The build fails closed: with no library (no Blender to build one, no cache, no
# source) it stops, unless HESTIA_ALLOW_FLAT=1 asks for a development build that draws the house in flat colors.
library="$root/build/Library"
stamp=$(cat "$repo/tools/blender/hestia_library.py" "$repo/tools/blender/hestia_render.py" | shasum | cut -c1-16)
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
if [ -n "${HESTIA_LIBRARY_SOURCE:-}" ]; then
  library="$HESTIA_LIBRARY_SOURCE"
elif [ "$(cat "$library/.stamp" 2>/dev/null || true)" != "$stamp" ] && [ -x "$blender" ]; then
  rm -rf "$library.new"
  # A library missing any model, surface, or the sky fails here and is never stamped or copied.
  if ! "$blender" -b --factory-startup --python-exit-code 1 --python "$repo/tools/blender/hestia_library.py" \
    -- --out "$library.new" >"$root/build/library.log" 2>&1; then
    tail -n 20 "$root/build/library.log" >&2
    echo "error: the asset library did not build; see $root/build/library.log" >&2
    exit 1
  fi
  echo "$stamp" >"$library.new/.stamp"
  rm -rf "$library"
  mv "$library.new" "$library"
fi
if [ -n "${HESTIA_LIBRARY_SOURCE:-}" ] || [ -e "$library" ]; then
  # Whatever its source (a fresh build, the stamped cache, or HESTIA_LIBRARY_SOURCE), a library is checked just
  # before it is packaged: complete, not a partial build, and holding every file it names. A library that was
  # named or cached but has no library.json fails here too, rather than quietly building a flat-colored app.
  if ! python3 "$repo/tools/blender/check_library.py" "$library"; then
    echo "error: the asset library at $library is incomplete or damaged; rebuild it" >&2
    exit 1
  fi
  mkdir -p "$app/Contents/Resources/Library"
  cp -R "$library/." "$app/Contents/Resources/Library/"
  rm -f "$app/Contents/Resources/Library/.stamp"
elif [ "${HESTIA_ALLOW_FLAT:-}" = "1" ]; then
  echo "note: HESTIA_ALLOW_FLAT=1 and no asset library; this development build draws in flat colors" >&2
else
  echo "error: no asset library: install Blender (or set BLENDER) to build one, or set HESTIA_LIBRARY_SOURCE;" \
    "HESTIA_ALLOW_FLAT=1 builds a flat-colored development app instead" >&2
  exit 1
fi
echo "$app"
