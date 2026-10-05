# Stream B — App shell and 2D

Owner: Cursor. Do not start before `contracts-v1.0`.

## Start point

Tag `contracts-v1.0`, the mock `GeometryEngine`, and a Mac with current Xcode. Do not wait on Stream A.

## Done when

- [ ] SwiftUI document app. Package document holds `model.json`, textures, meshes, and sheets. New, open, save, autosave, versions.
- [ ] Every edit goes through the command API. Undo and redo cover every tool, including later agent changes.
- [ ] 2D canvas: pan, zoom, grid, snaps, guidelines, live length and angle readout.
- [ ] Numeric entry mid-draw, feet-inches-fractions or metric.
- [ ] Tools: wall, door, window, room, stair, roof, slab, column, beam, dimension, text, MEP symbol, catalog placement.
- [ ] Selection and an inspector for every element type. Multi-select. Move, copy, mirror, rotate.
- [ ] Storey switcher, layer panel, unit toggle.
- [ ] Image or PDF underlay with two-point scale calibration.
- [ ] Split view hosts the 3D view and the chat panel. Selection syncs between 2D and 3D.
- [ ] Menu bar and keyboard shortcuts.
- [ ] Proof: draw `rect-cottage` from scratch in under 30 minutes. Link the screen capture on the issue.

## Out of scope

Geometry math, PDF writer internals, and provider HTTP clients. Call the protocols.
