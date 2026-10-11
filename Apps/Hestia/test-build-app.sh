#!/bin/sh
# Checks that build-app.sh fails closed on its asset library, without building anything: swift is stubbed and the
# script runs in a scratch copy of the parts of the repository it reads.
#
#   sh Apps/Hestia/test-build-app.sh
set -u
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/Apps/Hestia" "$scratch/repo/fixtures" "$scratch/repo/tools/blender" "$scratch/bin" \
  "$scratch/repo/.build/release"
cp "$here/build-app.sh" "$here/Info.plist" "$scratch/repo/Apps/Hestia/"
cp "$repo/fixtures/rect-cottage.json" "$scratch/repo/fixtures/"
cp "$repo/tools/blender/"*.py "$scratch/repo/tools/blender/"
printf '#!/bin/sh\nexit 0\n' >"$scratch/bin/swift"
chmod +x "$scratch/bin/swift"
: >"$scratch/repo/.build/release/HestiaApp"
failures=0
run() {
  # run EXPECTED LABEL [VAR=value ...]: build-app.sh's exit status must be EXPECTED.
  expected=$1 label=$2
  shift 2
  env PATH="$scratch/bin:$PATH" BLENDER=/nonexistent "$@" sh "$scratch/repo/Apps/Hestia/build-app.sh" \
    >/dev/null 2>"$scratch/err"
  status=$?
  if [ "$status" -eq "$expected" ]; then
    echo "ok: $label"
  else
    echo "FAIL: $label (exit $status)"
    cat "$scratch/err"
    failures=$((failures + 1))
  fi
}
rm -rf "$scratch/repo/Apps/Hestia/build/Library"
run 1 "no Blender, no cache, no source: the build stops"
run 0 "HESTIA_ALLOW_FLAT=1 builds a flat development app" HESTIA_ALLOW_FLAT=1
mkdir -p "$scratch/empty"
run 1 "a named library with no library.json stops the build" HESTIA_LIBRARY_SOURCE="$scratch/empty"
run 1 "a named library with no library.json stops the build even with HESTIA_ALLOW_FLAT=1" \
  HESTIA_LIBRARY_SOURCE="$scratch/empty" HESTIA_ALLOW_FLAT=1
mkdir -p "$scratch/repo/Apps/Hestia/build/Library"
run 1 "a cached library with no library.json stops the build"
echo "{}" >"$scratch/repo/Apps/Hestia/build/Library/library.json"
run 1 "a cached library that fails its check stops the build"
if [ "$failures" -eq 0 ]; then echo "ALL OK"; else echo "$failures FAILED"; exit 1; fi
