#!/bin/sh
# Platform rule from docs/ARCHITECTURE.md: every module under Sources/ builds with the open-source Swift
# toolchain on Linux and Windows, Foundation only. Apple frameworks (AppKit, SwiftUI, RealityKit,
# CoreGraphics, Security/Keychain, ...) live only under Apps/.
#
# This check allows exactly these imports under Sources/: Foundation and Hestia's own modules.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
allowed='^(Foundation|ATContracts|ATGeometry|ATDrawings|ATExchange|ATAgent|ATCatalog)$'
status=0
for file in $(find "$root/Sources" -name '*.swift' | sort); do
    # Every import line, with @testable / @_exported / kind keywords stripped, down to the module name.
    grep -nE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$file" | while IFS= read -r line; do
        module=$(printf '%s\n' "$line" | sed -E 's/^[0-9]+:[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\4/')
        if ! printf '%s\n' "$module" | grep -qE "$allowed"; then
            echo "${file#$root/}:${line%%:*}: imports $module; Sources/ may import only Foundation and Hestia modules" >&2
            echo fail > "$root/.platform-rule-failed"
        fi
    done
done
if [ -f "$root/.platform-rule-failed" ]; then
    rm -f "$root/.platform-rule-failed"
    exit 1
fi
echo "platform rule ok: Sources/ imports only Foundation and Hestia modules"
