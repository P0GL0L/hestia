# Stream E — Exchange

Owner: Grok CLI. Do not start before `contracts-v1.0`.

## Start point

`contracts-v1.0` display-list and mesh types, plus the three fixtures. Linux is enough. No Mac required except the Quick Look check, which can be a later macOS CI job.

## Done when

- [ ] DXF writer, ASCII R2013 (AC1027), `$INSUNITS` set, true-scale geometry, and these layer names: A-WALL, A-DOOR, A-GLAZ, A-FLOR, A-ROOF, A-AREA, A-ANNO-DIMS, A-ANNO-TEXT, E-LITE, E-POWR, P-FIXT, C-TOPO, L-PLNT.
- [ ] DXF reader imports lines, polylines, arcs, circles, and text as an underlay layer.
- [ ] SVG writer from the display list, true scale, with lineweights.
- [ ] glTF 2.0 binary (`.glb`) writer with PBR materials and embedded textures.
- [ ] OBJ plus MTL writer. Binary STL writer.
- [ ] USDZ writer, pure Swift.
- [ ] CI: every `.glb` passes the Khronos glTF validator with zero errors. DXF fixtures open in LibreCAD or QCAD with correct layers and scale, checked by script where possible.
- [ ] Round-trip: export `rect-cottage` to DXF, re-import, and match wall endpoints within 1 tick (1/320 mm).

## Out of scope

DWG. Do not add a DWG reader or writer to this repo.
