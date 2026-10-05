# Architecture locks

These are fixed before Stream 0 writes code. Changing them is a `contract-change` and needs P0GL0L's approval.

## Repo shape

```text
hestia/
  Package.swift            # Stream 0
  Sources/
    ATContracts/           # 0  data model, units, commands, module protocols
    ATGeometry/            # A  walls, joins, rooms, openings, stairs, roofs, meshes, section cuts
    ATDrawings/            # D  sheets, dimensions, views, schedules, display list, PDF writer
    ATExchange/            # E  DXF, SVG, glTF, OBJ, STL, USDZ
    ATAgent/               # F  providers, tool schemas, agent loop, MCP server
    ATCatalog/             # G  catalog, terrain, MEP symbols
  Apps/ArchITect/          # B + C  macOS app. Rename the Xcode target to Hestia in Stream B.
  Tests/<Module>Tests/
  Fixtures/
  docs/briefs/
```

Stream B renames `Apps/ArchITect` to `Apps/Hestia` if Stream 0 has not already done that. The product name is Hestia. Do not revive the ArchI-Tect codename in user-facing strings.

## Platform

Every `Sources/` module builds with the open-source Swift 6 toolchain on Linux and Windows: Foundation only. No AppKit, SwiftUI, RealityKit, CoreGraphics, or Keychain. Apple frameworks live only under `Apps/`.

CI starts with a Linux job and a macOS job. Add the Windows job when that toolchain is available to GitHub Actions. Do not put Apple-only code in `Sources/` to dodge the Windows target.

## Units

All lengths are `Length`, an `Int64` count of 1/320 mm.

- 1 mm = 320 ticks
- 1/64 inch = 127 ticks

No `Double` lengths in the model. Angles are `Int64` micro-degrees.

## Commands

UI, agent, and import code submit `Command` values. Each command validates, applies, and returns its inverse for undo.

## Fixtures Stream 0 must land

- `rect-cottage` — 6 rooms, multi-layer exterior wall, hip roof
- `l-house` — 2 storeys, 1 stair
- `wall-joins` — L, T, X, 30-degree oblique, arc

## Output honesty

Sheet export, framing display, and cut-and-fill numbers are schematic. Framing is visual only and non-engineered. The app must not present output as a permit set or a sealed construction document.

## Licensing

Apache-2.0 for code. CC0 or equivalent for bundled assets. No Plan7Architect derivation. DWG is out of this repo.
