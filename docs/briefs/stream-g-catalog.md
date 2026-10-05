# Stream G — Catalog, terrain, symbols

Owner: whichever agent Jarvis assigns when capacity exists. Do not start before `contracts-v1.0`. This stream can be split.

## Start point

`contracts-v1.0` types `Placement`, `TerrainPatch`, and `MEPSymbol`, plus the `CatalogStore` protocol.

## Done when

- [ ] Catalog item format: `item.json` (name, category, dimensions, mount type, license, source URL), `model.glb`, `thumb.png`.
- [ ] At least 300 items from CC0 sources such as Poly Haven, Kenney, and ambientCG, covering kitchen, bath, bedroom, living, office, exterior, and plants.
- [ ] Parametric generators: base and wall cabinets, countertops with cutouts, closets, shelving, fences, railings.
- [ ] Import of a user's own glTF, OBJ, and USDZ models and image textures into a project-local catalog.
- [ ] License audit script fails CI if a bundled asset lacks a recorded CC0 or equivalent license.
- [ ] Terrain: property boundary, contour import from DXF, sculpt points, pads, driveways, paths, ponds, retaining edges, approximate cut-and-fill report marked approximate.
- [ ] MEP symbols: outlets, switches, lights, fans, panel, plumbing fixtures, radiators. Each has a 2D symbol, a simple 3D proxy, and a default layer.
- [ ] Golden test: `rect-cottage` with 50 catalog items on a sloped lot exports and renders without errors.

## Out of scope

Geometry joins, sheet layout, and provider adapters.
