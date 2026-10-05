# Stream A — Geometry

Owner: Claude Code. Do not start before `contracts-v1.0`.

## Start point

Tag `contracts-v1.0`. `ATGeometry` stub conforms to `GeometryEngine`. Fixtures `rect-cottage`, `l-house`, and `wall-joins` exist.

## Interim tag `geometry-v0.5`

- [ ] Straight walls with layer-stack offsets. L, T, and X joins clean up.
- [ ] Room detection from closed wall loops, including virtual walls. Net and gross area.
- [ ] Doors and windows hosted in walls: cut the wall, move with it, reject placement past the wall ends.
- [ ] Auto hip roof from the exterior footprint.
- [ ] One straight stair that cuts the slab above.
- [ ] Mesh output for the above. Section-cut API returns classified 2D geometry.
- [ ] Tag `geometry-v0.5`.

This tag unblocks drawings and the real 3D meshes. Ship it before the long list below.

## Done tag `geometry-v1.0`

- [ ] Straight and arc walls. Oblique joins down to 15 degrees. Multi-layer joins. Phase: existing, new, demolish.
- [ ] Room area-rule presets. Floor-finish polygon independent of the room polygon.
- [ ] Door kinds: single, double, sliding, pocket, folding, garage. Window kinds: single, bay, corner, round, floor-to-ceiling, skylight. Parametric meshes.
- [ ] Stairs: straight, L, U, curved, spiral. Rise, run, and headroom checks.
- [ ] Roofs: gable, hip, flat, shed, mansard, gambrel, butterfly, free multi-plane. Pitch in degrees or rise/12. Overhangs, intersections, dormers, chimneys, skylights.
- [ ] Slab and stem-wall foundation, columns, beams, carport preset, deck with railing.
- [ ] Framing display mode, visual only, flagged non-engineered.
- [ ] Clipper2 stays behind a Swift wrapper. No C++ types in the public API.
- [ ] Golden tests pass. Regenerating a 200-wall house takes under 100 ms on an M-series Mac.
- [ ] Property tests: random wall layouts do not produce self-intersecting outlines or open room loops.

## Out of scope

UI, PDF, file exporters, and model-provider code.
